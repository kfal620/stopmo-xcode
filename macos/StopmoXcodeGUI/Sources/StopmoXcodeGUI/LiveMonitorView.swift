import SwiftUI

private enum ActivityFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case warnings = "Warnings"
    case errors = "Errors"
    case system = "System"

    var id: String { rawValue }
}

struct LiveMonitorView: View {
    @EnvironmentObject private var state: AppState
    var embedded: Bool = false

    @State private var activityFilter: ActivityFilter = .all
    @State private var pauseActivityUpdates: Bool = false
    @State private var frozenEvents: [String] = []
    @State private var activitySearchText: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.lg) {
                if !embedded {
                    ScreenHeader(
                        title: "Live Monitor",
                        subtitle: "Watch controls, queue telemetry, throughput, and live activity."
                    )
                }

                watchControlsCard
                if shouldShowRecoveryCard {
                    monitoringRecoveryCard
                }
                liveKpiCard
                queueTrendCard
                watchServiceCard

                if let logTail = state.watchServiceState?.logTail, !logTail.isEmpty {
                    watchLogTailCard(logTail)
                }

                activityCard
            }
            .padding(embedded ? StopmoUI.Spacing.md : StopmoUI.Spacing.lg)
        }
        .onChange(of: pauseActivityUpdates) { _, paused in
            if paused {
                frozenEvents = state.liveEvents
            } else {
                frozenEvents = []
            }
        }
    }

    private var watchControlsCard: some View {
        SectionCard("Watch Controls", subtitle: "Start/stop watch and refresh snapshots.") {
            HStack(spacing: StopmoUI.Spacing.sm) {
                Button("Start Watch") {
                    Task { await state.startWatchService() }
                }
                .disabled(state.isBusy || (state.watchServiceState?.running ?? false))

                Button("Stop Watch") {
                    Task { await state.stopWatchService() }
                }
                .disabled(state.isBusy || !(state.watchServiceState?.running ?? false))

                Button("Refresh") {
                    Task { await state.refreshLiveData() }
                }
                .disabled(state.isBusy)
            }

            HStack(spacing: StopmoUI.Spacing.sm) {
                StatusChip(
                    label: (state.watchServiceState?.running ?? false) ? "Running" : "Stopped",
                    tone: (state.watchServiceState?.running ?? false) ? .success : .warning
                )
                StatusChip(
                    label: "Polling \(state.monitoringStatusLabel)",
                    tone: monitoringTone
                )
                if state.monitoringBackoffActive {
                    StatusChip(
                        label: String(format: "Backoff %.1fs", state.monitoringPollIntervalSeconds),
                        tone: .warning
                    )
                }

                if let watch = state.watchServiceState {
                    if watch.startBlocked == true {
                        StatusChip(label: "Start Blocked", tone: .danger)
                    }
                    if let launchError = watch.launchError, !launchError.isEmpty {
                        StatusChip(label: "Launch Error", tone: .danger)
                    }
                }
            }

            if let watch = state.watchServiceState {
                if watch.startBlocked == true, let preflight = watch.preflight, !preflight.blockers.isEmpty {
                    Text("Blocked by preflight: \(preflight.blockers.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if let launchError = watch.launchError, !launchError.isEmpty {
                    Text("Launch error: \(launchError)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var monitoringRecoveryCard: some View {
        SectionCard("Recovery", subtitle: "Bridge/watch failure handling with safe restart controls.") {
            if let message = state.monitoringLastFailureMessage, !message.isEmpty {
                Text(message)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if let launchError = state.watchServiceState?.launchError, !launchError.isEmpty {
                Text(launchError)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack(spacing: StopmoUI.Spacing.sm) {
                StatusChip(label: "Failures \(state.monitoringConsecutiveFailures)", tone: state.monitoringBackoffActive ? .danger : .success)
                if let nextPoll = state.monitoringNextPollAt {
                    TimelineView(.periodic(from: Date(), by: 1)) { context in
                        StatusChip(label: nextPollLabel(at: context.date, nextPollAt: nextPoll), tone: .warning)
                    }
                }
                if let lastSuccess = state.monitoringLastSuccessAt {
                    TimelineView(.periodic(from: Date(), by: 1)) { context in
                        StatusChip(label: "Last success \(relativeTimeLabel(from: lastSuccess, now: context.date))", tone: .neutral)
                    }
                }
            }

            HStack(spacing: StopmoUI.Spacing.sm) {
                Button("Retry Now") {
                    Task { await state.refreshLiveData() }
                }
                .disabled(state.isBusy)

                Button("Restart Monitoring") {
                    state.restartMonitoringLoop()
                }
                .disabled(!state.monitoringEnabled && state.selectedHub != .capture)

                Button("Restart Watch") {
                    Task { await state.restartWatchService() }
                }
                .disabled(state.isBusy)

                Button("Check Runtime Health") {
                    Task { await state.refreshHealth() }
                }
                .disabled(state.isBusy)
            }
        }
    }

    private var liveKpiCard: some View {
        SectionCard("Live KPIs", subtitle: "Queue states, throughput, worker load, and ETA heuristic.") {
            let counts = state.queueSnapshot?.counts ?? [:]
            let detected = counts["detected", default: 0]
            let decoding = counts["decoding", default: 0]
            let xform = counts["xform", default: 0]
            let dpxWrite = counts["dpx_write", default: 0]
            let done = counts["done", default: 0]
            let failed = counts["failed", default: 0]
            let inflight = state.watchServiceState?.inflightFrames ?? 0
            let workers = state.config.watch.maxWorkers
            let throughput = state.throughputFramesPerMinute

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: StopmoUI.Spacing.sm) {
                    StatusChip(label: "detected \(detected)", tone: detected > 0 ? .warning : .neutral)
                    StatusChip(label: "decoding \(decoding)", tone: decoding > 0 ? .warning : .neutral)
                    StatusChip(label: "xform \(xform)", tone: xform > 0 ? .warning : .neutral)
                    StatusChip(label: "dpx_write \(dpxWrite)", tone: dpxWrite > 0 ? .warning : .neutral)
                    StatusChip(label: "done \(done)", tone: done > 0 ? .success : .neutral)
                    StatusChip(label: "failed \(failed)", tone: failed > 0 ? .danger : .neutral)
                    StatusChip(label: String(format: "%.1f frames/min", throughput), tone: throughput > 0 ? .success : .neutral)
                    StatusChip(label: "Workers \(inflight)/\(max(1, workers))", tone: inflight > 0 ? .warning : .neutral)
                    StatusChip(label: etaLabel(), tone: throughput > 0 ? .neutral : .warning)
                    TimelineView(.periodic(from: Date(), by: 1)) { context in
                        StatusChip(label: "Last frame \(lastFrameAgeLabel(at: context.date))", tone: state.lastFrameAt == nil ? .warning : .neutral)
                    }
                }
            }
        }
    }

    private var queueTrendCard: some View {
        SectionCard("Queue Depth Trend", subtitle: "Rolling depth for active queue states.") {
            if state.queueDepthTrend.count < 2 {
                EmptyStateCard(message: "Collecting samples. Keep live monitoring active for trend visibility.")
            } else {
                QueueDepthSparkline(values: state.queueDepthTrend)
                    .frame(height: 90)
                HStack(spacing: StopmoUI.Spacing.sm) {
                    StatusChip(label: "Current \(state.queueDepthTrend.last ?? 0)", tone: .warning)
                    StatusChip(label: "Peak \(state.queueDepthTrend.max() ?? 0)", tone: .danger)
                    StatusChip(label: "Samples \(state.queueDepthTrend.count)", tone: .neutral)
                }
            }
        }
    }

    private var watchServiceCard: some View {
        SectionCard("Watch Service", subtitle: "Runtime details and progress counters.") {
            if let watch = state.watchServiceState {
                KeyValueRow(
                    key: "Running",
                    value: watch.running ? "yes" : "no",
                    tone: watch.running ? .success : .warning
                )
                KeyValueRow(
                    key: "PID",
                    value: watch.pid.map(String.init) ?? "-",
                    tone: watch.running ? .neutral : .warning
                )
                KeyValueRow(
                    key: "Started",
                    value: watch.startedAtUtc ?? "-",
                    tone: watch.running ? .neutral : .warning
                )
                KeyValueRow(key: "Config", value: watch.configPath)
                if let logPath = watch.logPath {
                    KeyValueRow(key: "Log", value: logPath)
                }
                if let crash = watch.crashRecovery {
                    KeyValueRow(key: "Last Startup", value: crash.lastStartupUtc ?? "-")
                    KeyValueRow(key: "Last Shutdown", value: crash.lastShutdownUtc ?? "-")
                    KeyValueRow(
                        key: "Crash Recovery",
                        value: "reset \(crash.lastInflightResetCount) inflight jobs",
                        tone: crash.lastInflightResetCount == 0 ? .success : .warning
                    )
                }
                if let preflight = watch.preflight, !preflight.ok {
                    KeyValueRow(
                        key: "Preflight",
                        value: "blocked: \(preflight.blockers.joined(separator: ", "))",
                        tone: .danger
                    )
                }
                ProgressView(value: watch.progressRatio)
                    .padding(.top, StopmoUI.Spacing.xs)
                HStack(spacing: StopmoUI.Spacing.xs) {
                    StatusChip(label: "Progress \(Int((watch.progressRatio * 100.0).rounded()))%", tone: watch.running ? .success : .neutral)
                    StatusChip(label: "Completed \(watch.completedFrames)", tone: .success)
                    StatusChip(label: "Inflight \(watch.inflightFrames)", tone: .warning)
                    StatusChip(label: "Total \(watch.totalFrames)", tone: .neutral)
                }
            } else {
                EmptyStateCard(message: "No watch state yet. Click Refresh.")
            }
        }
    }

    private func watchLogTailCard(_ logTail: [String]) -> some View {
        SectionCard("Watch Log Tail") {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(logTail.indices, id: \.self) { idx in
                        Text(logTail[idx])
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(minHeight: 120, maxHeight: 220)
        }
    }

    private var activityCard: some View {
        SectionCard("Activity Feed", subtitle: "Job transitions, warnings/errors, and watch assembly events.") {
            HStack(spacing: StopmoUI.Spacing.sm) {
                Picker("Filter", selection: $activityFilter) {
                    ForEach(ActivityFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)

                Toggle("Pause", isOn: $pauseActivityUpdates)

                TextField("Search activity", text: $activitySearchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }

            if filteredActivityEvents.isEmpty {
                EmptyStateCard(message: "No activity matches the current filter.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: StopmoUI.Spacing.xxs) {
                        ForEach(filteredActivityEvents.indices, id: \.self) { idx in
                            let line = filteredActivityEvents[idx]
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(minHeight: 140, maxHeight: 320)
            }
        }
    }

    private var sourceActivityEvents: [String] {
        pauseActivityUpdates ? frozenEvents : state.liveEvents
    }

    private var filteredActivityEvents: [String] {
        sourceActivityEvents.filter { line in
            if !activitySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !line.localizedCaseInsensitiveContains(activitySearchText)
            {
                return false
            }
            switch activityFilter {
            case .all:
                return true
            case .warnings:
                return activityKind(for: line) == .warnings
            case .errors:
                return activityKind(for: line) == .errors
            case .system:
                return activityKind(for: line) == .system
            }
        }
    }

    private func activityKind(for line: String) -> ActivityFilter {
        let lower = line.lowercased()
        if lower.contains("error") || lower.contains("failed") {
            return .errors
        }
        if lower.contains("warning") || lower.contains("blocked") || lower.contains("missing") {
            return .warnings
        }
        if lower.contains("watch process")
            || lower.contains("queue counts updated")
            || lower.contains("monitoring")
            || lower.contains("service started")
            || lower.contains("service stopped")
        {
            return .system
        }
        return .all
    }

    private func etaLabel() -> String {
        guard let watch = state.watchServiceState else {
            return "ETA --"
        }
        let remaining = max(0, watch.totalFrames - watch.completedFrames)
        guard remaining > 0, state.throughputFramesPerMinute > 0.01 else {
            return "ETA --"
        }
        let minutes = Double(remaining) / state.throughputFramesPerMinute
        if minutes < 1 {
            return "ETA <1m"
        }
        if minutes < 60 {
            return "ETA \(Int(minutes.rounded()))m"
        }
        let hours = Int(minutes) / 60
        let mins = Int(minutes) % 60
        return "ETA \(hours)h \(mins)m"
    }

    private func lastFrameAgeLabel(at now: Date) -> String {
        guard let last = state.lastFrameAt else {
            return "--"
        }
        return relativeTimeLabel(from: last, now: now)
    }

    private func nextPollLabel(at now: Date, nextPollAt: Date) -> String {
        let delta = max(0, Int(nextPollAt.timeIntervalSince(now)))
        return "Next poll \(delta)s"
    }

    private func relativeTimeLabel(from start: Date, now: Date) -> String {
        let delta = max(0, Int(now.timeIntervalSince(start)))
        if delta < 60 {
            return "\(delta)s ago"
        }
        let mins = delta / 60
        let secs = delta % 60
        return "\(mins)m \(secs)s ago"
    }

    private var monitoringTone: StatusTone {
        if state.monitoringConsecutiveFailures >= 3 {
            return .danger
        }
        if state.monitoringConsecutiveFailures > 0 {
            return .warning
        }
        return state.monitoringEnabled ? .success : .neutral
    }

    private var shouldShowRecoveryCard: Bool {
        state.monitoringConsecutiveFailures > 0
            || ((state.watchServiceState?.launchError?.isEmpty == false))
            || (state.watchServiceState?.startBlocked == true)
    }
}

private struct QueueDepthSparkline: View {
    let values: [Int]

    var body: some View {
        GeometryReader { geo in
            let maxValue = max(values.max() ?? 1, 1)
            let width = geo.size.width
            let height = geo.size.height
            let denom = max(values.count - 1, 1)

            ZStack {
                RoundedRectangle(cornerRadius: StopmoUI.Radius.card, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))

                Path { path in
                    guard !values.isEmpty else {
                        return
                    }
                    for (idx, value) in values.enumerated() {
                        let x = width * CGFloat(idx) / CGFloat(denom)
                        let y = height - (height * CGFloat(value) / CGFloat(maxValue))
                        if idx == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                Path { path in
                    guard !values.isEmpty else {
                        return
                    }
                    path.move(to: CGPoint(x: 0, y: height))
                    for (idx, value) in values.enumerated() {
                        let x = width * CGFloat(idx) / CGFloat(denom)
                        let y = height - (height * CGFloat(value) / CGFloat(maxValue))
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.closeSubpath()
                }
                .fill(Color.orange.opacity(0.14))
            }
        }
    }
}
