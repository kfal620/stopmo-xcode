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

    private let initialActivityDisplayLimit: Int = 80
    private let activityDisplayIncrement: Int = 80
    private let watchLogDisplayLimit: Int = 120
    private let maxActivitySourceLines: Int = 260

    @State private var activityFilter: ActivityFilter = .all
    @State private var pauseActivityUpdates: Bool = false
    @State private var frozenEvents: [String] = []
    @State private var activitySearchText: String = ""
    @State private var debouncedActivitySearchText: String = ""
    @State private var activityDisplayLimit: Int = 80
    @State private var showActivityFeed: Bool = false
    @State private var showWatchLogTail: Bool = false
    @State private var showWatchRuntimeDetails: Bool = false
    @State private var showQueueTrend: Bool = false
    @State private var searchDebounceTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.lg) {
                if !embedded {
                    ScreenHeader(
                        title: "Live Monitor",
                        subtitle: "Active-shot ingest pace, watch runtime state, and lightweight activity."
                    )
                }

                monitorWorkspaceLayout
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(embedded ? StopmoUI.Spacing.sm : StopmoUI.Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: pauseActivityUpdates) { _, paused in
            if paused {
                frozenEvents = state.liveEvents
            } else {
                frozenEvents = []
            }
            activityDisplayLimit = initialActivityDisplayLimit
        }
        .onAppear {
            debouncedActivitySearchText = activitySearchText
        }
        .onChange(of: activityFilter) { _, _ in
            activityDisplayLimit = initialActivityDisplayLimit
        }
        .onChange(of: activitySearchText) { _, _ in
            activityDisplayLimit = initialActivityDisplayLimit
            debounceActivitySearch()
        }
        .onDisappear {
            searchDebounceTask?.cancel()
        }
    }

    private var monitorWorkspaceLayout: some View {
        AdaptiveColumns(breakpoint: 760) {
            leftMonitorColumn
        } secondary: {
            rightMonitorColumn
        }
    }

    private var leftMonitorColumn: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.lg) {
            if shouldShowRecoveryCard {
                monitoringRecoveryCard
            }
            activeShotFocusCard
            liveKpiCard
            queueTrendCard
        }
    }

    private var rightMonitorColumn: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.lg) {
            watchServiceCard
            if let logTail = state.watchServiceState?.logTail, !logTail.isEmpty {
                watchLogTailCard(logTail)
            }
            activityCard
        }
    }

    private var monitoringRecoveryCard: some View {
        SectionCard(
            "Recovery",
            subtitle: "Bridge/watch failure handling with safe restart controls.",
            density: .compact,
            surfaceLevel: .panel,
            chrome: .outlined,
            showSubtitle: false
        ) {
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

    private var activeShotFocusCard: some View {
        SectionCard(
            "Active Shot Focus",
            subtitle: "Current shot ingest parity and conversion health.",
            density: .compact,
            surfaceLevel: .raised,
            chrome: .standard,
            showSubtitle: false
        ) {
            if let evaluation = activeShotEvaluation {
                let shot = evaluation.shot
                HStack(spacing: StopmoUI.Spacing.sm) {
                    Text(shot.shotName)
                        .font(.title3.weight(.semibold))
                    StatusChip(label: evaluation.healthState.rawValue, tone: evaluation.healthState.tone, density: .compact)
                    StatusChip(label: evaluation.completionLabel, tone: evaluation.isDeliverable ? .success : .warning, density: .compact)
                    Spacer(minLength: 0)
                    if captureNeedsTriageAttention {
                        Button("Open Triage") {
                            state.selectedHub = .triage
                            state.selectedTriagePanel = .shots
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }

                ProgressView(value: activeShotProgress(for: shot))
                    .tint(AppVisualTokens.stageAccent(hub: .capture))

                HStack(spacing: StopmoUI.Spacing.sm) {
                    StatusChip(label: "Done \(shot.doneFrames)", tone: .success, density: .compact)
                    StatusChip(label: "Inflight \(shot.inflightFrames)", tone: shot.inflightFrames > 0 ? .warning : .neutral, density: .compact)
                    StatusChip(label: "Failed \(shot.failedFrames)", tone: shot.failedFrames > 0 ? .danger : .neutral, density: .compact)
                    StatusChip(label: "Total \(shot.totalFrames)", tone: .neutral, density: .compact)
                    Text(ShotHealthModel.updatedDisplayLabel(for: shot))
                        .metadataTextStyle(.tertiary)
                        .help(shot.lastUpdatedAt ?? "No update timestamp")
                }

                HStack(spacing: StopmoUI.Spacing.sm) {
                    Button("Open Shot Folder") {
                        state.openPathInFinder(shotRootPath(for: shot))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    if evaluation.isDeliverable {
                        Button("Open Deliver") {
                            state.selectedHub = .deliver
                            state.selectedDeliverPanel = .dayWrap
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    if let reason = evaluation.readinessReason, !reason.isEmpty {
                        StatusChip(label: reason, tone: .warning, density: .compact)
                    }
                }
            } else {
                EmptyStateCard(message: "No active shot is available yet. Keep watch running while frames arrive.")
                if captureNeedsTriageAttention {
                    Button("Open Triage") {
                        state.selectedHub = .triage
                        state.selectedTriagePanel = .shots
                    }
                }
            }
        }
    }

    private var liveKpiCard: some View {
        SectionCard(
            "Live KPIs",
            subtitle: "Queue states, throughput, worker load, and ETA heuristic.",
            density: .compact,
            surfaceLevel: .panel,
            chrome: .quiet,
            showSubtitle: false
        ) {
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

            MetricWrap(minItemWidth: 145) {
                StatusChip(label: "detected \(detected)", tone: .neutral, density: .compact)
                StatusChip(label: "decoding \(decoding)", tone: .neutral, density: .compact)
                StatusChip(label: "xform \(xform)", tone: .neutral, density: .compact)
                StatusChip(label: "dpx_write \(dpxWrite)", tone: .neutral, density: .compact)
                StatusChip(label: "done \(done)", tone: done > 0 ? .success : .neutral, density: .compact)
                StatusChip(label: "failed \(failed)", tone: failed > 0 ? .danger : .neutral, density: .compact)
                StatusChip(label: String(format: "%.1f frames/min", throughput), tone: throughput > 0 ? .success : .neutral, density: .compact)
                StatusChip(label: "Workers \(inflight)/\(max(1, workers))", tone: .neutral, density: .compact)
                StatusChip(label: etaLabel(), tone: throughput > 0 ? .neutral : .warning, density: .compact)
                TimelineView(.periodic(from: Date(), by: 1)) { context in
                    StatusChip(label: "Last frame \(lastFrameAgeLabel(at: context.date))", tone: state.lastFrameAt == nil ? .warning : .neutral, density: .compact)
                }
            }
        }
    }

    private var queueTrendCard: some View {
        SectionCard(
            "Queue Depth Trend",
            subtitle: "Secondary telemetry for queue fluctuations.",
            density: .compact,
            surfaceLevel: .panel,
            chrome: .quiet,
            showSubtitle: false
        ) {
            DisclosureGroup(isExpanded: $showQueueTrend) {
                if state.queueDepthTrend.count < 2 {
                    EmptyStateCard(message: "Collecting samples. Keep live monitoring active for trend visibility.")
                } else {
                    QueueDepthSparkline(values: state.queueDepthTrend)
                        .frame(height: 90)
                    HStack(spacing: StopmoUI.Spacing.sm) {
                        StatusChip(label: "Current \(state.queueDepthTrend.last ?? 0)", tone: .warning, density: .compact)
                        StatusChip(label: "Peak \(state.queueDepthTrend.max() ?? 0)", tone: .danger, density: .compact)
                        StatusChip(label: "Samples \(state.queueDepthTrend.count)", tone: .neutral, density: .compact)
                    }
                }
            } label: {
                DisclosureRowLabel(
                    title: "Show Queue Trend",
                    isExpanded: $showQueueTrend
                )
            }
        }
    }

    private var watchServiceCard: some View {
        SectionCard(
            "Watch Service",
            subtitle: "Runtime details, watch controls, and progress counters.",
            density: .compact,
            surfaceLevel: .panel,
            chrome: .quiet,
            showSubtitle: false
        ) {
            HStack(spacing: StopmoUI.Spacing.sm) {
                ToolbarActionCluster {
                    CommandIconButton(
                        systemImage: "play.fill",
                        tooltip: "Start watch service",
                        accessibilityLabel: "Start Watch",
                        isDisabled: state.isBusy || (state.watchServiceState?.running ?? false)
                    ) {
                        Task { await state.startWatchService() }
                    }

                    CommandIconButton(
                        systemImage: "stop.fill",
                        tooltip: "Stop watch service",
                        accessibilityLabel: "Stop Watch",
                        isDisabled: state.isBusy || !(state.watchServiceState?.running ?? false)
                    ) {
                        Task { await state.stopWatchService() }
                    }
                }

                StatusChip(
                    label: (state.watchServiceState?.running ?? false) ? "Running" : "Stopped",
                    tone: (state.watchServiceState?.running ?? false) ? .success : .warning,
                    density: .compact
                )
                StatusChip(
                    label: "Polling \(state.monitoringStatusLabel)",
                    tone: monitoringTone,
                    density: .compact
                )
                if state.monitoringBackoffActive {
                    StatusChip(
                        label: String(format: "Backoff %.1fs", state.monitoringPollIntervalSeconds),
                        tone: .warning,
                        density: .compact
                    )
                }
                if let watch = state.watchServiceState {
                    if watch.startBlocked == true {
                        StatusChip(label: "Start Blocked", tone: .danger, density: .compact)
                    }
                    if let launchError = watch.launchError, !launchError.isEmpty {
                        StatusChip(label: "Launch Error", tone: .danger, density: .compact)
                    }
                }
            }

            if let watch = state.watchServiceState {
                if watch.startBlocked == true, let preflight = watch.preflight, !preflight.blockers.isEmpty {
                    Text("Blocked by preflight: \(preflight.blockers.joined(separator: ", "))")
                        .metadataTextStyle(.secondary)
                        .foregroundStyle(.red.opacity(0.88))
                }
                if let launchError = watch.launchError, !launchError.isEmpty {
                    Text("Launch error: \(launchError)")
                        .metadataTextStyle(.secondary)
                        .foregroundStyle(.red.opacity(0.88))
                }
            }

            if let watch = state.watchServiceState {
                ProgressView(value: watch.progressRatio)
                    .padding(.top, StopmoUI.Spacing.xs)
                HStack(spacing: StopmoUI.Spacing.xs) {
                    StatusChip(label: "Progress \(Int((watch.progressRatio * 100.0).rounded()))%", tone: watch.running ? .success : .neutral, density: .compact)
                    StatusChip(label: "Completed \(watch.completedFrames)", tone: .success, density: .compact)
                    StatusChip(label: "Inflight \(watch.inflightFrames)", tone: .warning, density: .compact)
                    StatusChip(label: "Total \(watch.totalFrames)", tone: .neutral, density: .compact)
                }

                DisclosureGroup(isExpanded: $showWatchRuntimeDetails) {
                    VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
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
                    }
                    .padding(.top, StopmoUI.Spacing.xs)
                } label: {
                    DisclosureRowLabel(
                        title: "Show Runtime Details",
                        isExpanded: $showWatchRuntimeDetails
                    )
                }
            } else {
                EmptyStateCard(message: "No watch state yet. Start watch or wait for polling.")
            }
        }
    }

    private func watchLogTailCard(_ logTail: [String]) -> some View {
        let visibleTail = Array(logTail.suffix(watchLogDisplayLimit))

        return SectionCard(
            "Watch Log Tail",
            density: .compact,
            surfaceLevel: .panel,
            chrome: .quiet,
            showSubtitle: false
        ) {
            DisclosureGroup(isExpanded: $showWatchLogTail) {
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(visibleTail.indices, id: \.self) { idx in
                                Text(visibleTail[idx])
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(minHeight: 120, maxHeight: 220)

                    if logTail.count > visibleTail.count {
                        Text("Showing latest \(visibleTail.count) lines of \(logTail.count).")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, StopmoUI.Spacing.xs)
            } label: {
                DisclosureRowLabel(
                    title: "Log Tail (\(visibleTail.count) lines)",
                    isExpanded: $showWatchLogTail
                )
            }
        }
    }

    private var activityCard: some View {
        return SectionCard(
            "Activity Feed",
            subtitle: "Job transitions, warnings/errors, and watch assembly events.",
            density: .compact,
            surfaceLevel: .panel,
            chrome: .quiet,
            showSubtitle: false
        ) {
            DisclosureGroup(isExpanded: $showActivityFeed) {
                let filteredEvents = filteredActivityEvents
                let visibleCount = min(activityDisplayLimit, filteredEvents.count)
                let visibleEvents = Array(filteredEvents.prefix(visibleCount))

                VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
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

                    HStack(spacing: StopmoUI.Spacing.sm) {
                        StatusChip(label: "Showing \(visibleCount)/\(filteredEvents.count)", tone: .neutral)
                        if filteredEvents.count > visibleCount {
                            Button("Show More") {
                                activityDisplayLimit = min(
                                    filteredEvents.count,
                                    activityDisplayLimit + activityDisplayIncrement
                                )
                            }
                            .buttonStyle(.borderless)
                        }
                        if visibleCount > initialActivityDisplayLimit {
                            Button("Show Less") {
                                activityDisplayLimit = initialActivityDisplayLimit
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    if filteredEvents.isEmpty {
                        EmptyStateCard(message: "No activity matches the current filter.")
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: StopmoUI.Spacing.xxs) {
                                ForEach(Array(visibleEvents.enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.system(.caption, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .frame(minHeight: 120, maxHeight: 280)
                    }
                }
                .padding(.top, StopmoUI.Spacing.xs)
            } label: {
                HStack(spacing: StopmoUI.Spacing.sm) {
                    DisclosureRowLabel(
                        title: "Activity (\(sourceActivityEvents.count) recent events)",
                        isExpanded: $showActivityFeed
                    )
                    if pauseActivityUpdates {
                        StatusChip(label: "Paused", tone: .warning)
                    }
                }
            }
        }
    }

    private var sourceActivityEvents: [String] {
        let source = pauseActivityUpdates ? frozenEvents : state.liveEvents
        return Array(source.prefix(maxActivitySourceLines))
    }

    private var filteredActivityEvents: [String] {
        let term = debouncedActivitySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return sourceActivityEvents.filter { line in
            if !term.isEmpty,
               !line.localizedCaseInsensitiveContains(term)
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

    private var activeShotEvaluation: ShotHealthEvaluation? {
        guard let shot = ShotHealthModel.resolveActiveShot(from: state.shotsSnapshot) else {
            return nil
        }
        return ShotHealthModel.evaluate(shot)
    }

    private var captureNeedsTriageAttention: Bool {
        let queueFailed = state.queueSnapshot?.counts["failed", default: 0] ?? 0
        let evaluations = ShotHealthModel.evaluate(snapshot: state.shotsSnapshot)
        return queueFailed > 0
            || evaluations.contains(where: { $0.healthState == .issues || $0.healthState == .inflight })
    }

    private func activeShotProgress(for shot: ShotSummaryRow) -> Double {
        guard shot.totalFrames > 0 else {
            return 0
        }
        return min(1.0, max(0.0, Double(shot.doneFrames) / Double(shot.totalFrames)))
    }

    private func shotRootPath(for shot: ShotSummaryRow) -> String {
        let base = state.config.watch.outputDir.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            return shot.shotName
        }
        return (base as NSString).appendingPathComponent(shot.shotName)
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

    private func debounceActivitySearch() {
        searchDebounceTask?.cancel()
        let latest = activitySearchText
        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                debouncedActivitySearchText = latest
            }
        }
    }
}
