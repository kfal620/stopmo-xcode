import SwiftUI

private enum CaptureConsoleTab: String, CaseIterable, Identifiable {
    case activity = "Activity"
    case watchLog = "Watch Log"
    case diagnostics = "Diagnostics"

    var id: String { rawValue }
}

/// Capture workspace surface for live queue progress, telemetry, and recent activity context.
struct LiveMonitorView: View {
    @EnvironmentObject private var state: AppState
    var embedded: Bool = false

    private let initialActivityDisplayLimit: Int = 80
    private let activityDisplayIncrement: Int = 80
    private let watchLogDisplayLimit: Int = 120
    private let maxActivitySourceLines: Int = 260

    @State private var activityFilter: CaptureActivityFilter = .all
    @State private var pauseActivityUpdates: Bool = false
    @State private var frozenEvents: [String] = []
    @State private var activitySearchText: String = ""
    @State private var debouncedActivitySearchText: String = ""
    @State private var activityDisplayLimit: Int = 80
    @State private var showConsole: Bool = false
    @State private var consoleTab: CaptureConsoleTab = .activity
    @State private var showWatchRuntimeDetails: Bool = false
    @State private var showMetricsSummary: Bool = false
    @State private var showQueueTrend: Bool = false
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var previewLightboxItem: ShotLightboxItem?

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            captureHeader

            if let alert = captureAlert {
                inlineAlertBanner(alert)
            }

            ScrollView(.vertical, showsIndicators: true) {
                AdaptiveColumns(breakpoint: 1320, spacing: StopmoUI.Spacing.md) {
                    capturePrimaryArea
                } secondary: {
                    captureInspector
                }
                .padding(.bottom, StopmoUI.Spacing.xs)
            }

            WorkspaceConsoleDock(
                title: consoleTab.rawValue,
                summary: consoleSummary,
                isExpanded: $showConsole
            ) {
                Picker("Console", selection: $consoleTab) {
                    ForEach(CaptureConsoleTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
            } content: {
                consoleContent
            }
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
            if shouldShowAlert {
                showConsole = true
                consoleTab = .diagnostics
            }
        }
        .onChange(of: shouldShowAlert) { _, next in
            if next {
                showConsole = true
                consoleTab = .diagnostics
            }
        }
        .onChange(of: activityFilter) { _, _ in
            activityDisplayLimit = initialActivityDisplayLimit
        }
        .onChange(of: activitySearchText) { _, _ in
            activityDisplayLimit = initialActivityDisplayLimit
            debounceActivitySearch()
        }
        .onChange(of: state.deliveryRunState.status) { _, next in
            if next == .running && !shouldShowAlert {
                showConsole = false
            }
        }
        .onDisappear {
            searchDebounceTask?.cancel()
        }
        .sheet(item: $previewLightboxItem) { item in
            ShotLightboxView(item: item) { shotRoot in
                state.openPathInFinder(shotRoot)
            }
        }
    }

    private var captureHeader: some View {
        ToolbarStrip(title: "Capture") {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                SummaryFactStrip(
                    facts: [
                        SummaryFact(id: "watch", label: "Watcher", value: (state.watchServiceState?.running ?? false) ? "Running" : "Stopped", tone: (state.watchServiceState?.running ?? false) ? .success : .warning),
                        SummaryFact(id: "active", label: "Active Shot", value: activeShotEvaluation?.shot.shotName ?? "None", tone: .neutral),
                        SummaryFact(id: "queue", label: "Queue", value: "\(state.queueSnapshot?.total ?? 0)", tone: .neutral),
                        SummaryFact(id: "monitor", label: "Monitoring", value: state.monitoringStatusLabel, tone: monitoringTone),
                    ],
                    minItemWidth: 110,
                    compact: true
                )
            }
        }
    }

    private func inlineAlertBanner(_ alert: (title: String, message: String, tone: StatusTone)) -> some View {
        SurfaceContainer(level: .raised, chrome: .outlined, cornerRadius: 14) {
            HStack(alignment: .top, spacing: StopmoUI.Spacing.sm) {
                Image(systemName: alert.tone == .danger ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(alert.tone.foreground)
                VStack(alignment: .leading, spacing: 4) {
                    Text(alert.title)
                        .font(.subheadline.weight(.semibold))
                    Text(alert.message)
                        .metadataTextStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Open Review") {
                    state.selectedHub = .triage
                    state.selectedTriagePanel = .shots
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)
        }
    }

    private var capturePrimaryArea: some View {
        SectionCard(
            "Active Shot",
            subtitle: "The current shot is the hero; everything else is inspectable detail.",
            density: .compact,
            surfaceLevel: .raised,
            chrome: .standard,
            showSubtitle: false
        ) {
            if let evaluation = activeShotEvaluation {
                activeShotContent(evaluation)
            } else {
                waitingCaptureContent
            }
        }
    }

    private func activeShotContent(_ evaluation: ShotHealthEvaluation) -> some View {
        let shot = evaluation.shot

        return VStack(alignment: .leading, spacing: StopmoUI.Spacing.md) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: StopmoUI.Spacing.lg) {
                    captureHeroPreview(for: shot)
                    captureHeroMeta(for: shot, evaluation: evaluation)
                        .frame(minWidth: 250, maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: StopmoUI.Spacing.md) {
                    captureHeroPreview(for: shot)
                    captureHeroMeta(for: shot, evaluation: evaluation)
                }
            }

            ProgressView(value: activeShotProgress(for: shot))
                .tint(LifecycleHub.capture.accentColor)

            Text(evaluation.issueSummary)
                .appTextRole(.support)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: StopmoUI.Spacing.sm) {
                    if captureNeedsReviewAttention {
                        Button("Open Review") {
                            state.selectedHub = .triage
                            state.selectedTriagePanel = .shots
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }

                    Button("Open Shot Folder") {
                        state.openPathInFinder(shotRootPath(for: shot))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Show Console") {
                        showConsole = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                    if captureNeedsReviewAttention {
                        Button("Open Review") {
                            state.selectedHub = .triage
                            state.selectedTriagePanel = .shots
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }

                    Button("Open Shot Folder") {
                        state.openPathInFinder(shotRootPath(for: shot))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Show Console") {
                        showConsole = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var waitingCaptureContent: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.md) {
            EmptyStateCard(message: "No active shot yet. Keep watch running while frames arrive.")
            SummaryFactStrip(
                facts: waitingCaptureFacts,
                minItemWidth: 120,
                compact: true
            )

            ViewThatFits(in: .horizontal) {
                HStack(spacing: StopmoUI.Spacing.sm) {
                    Button("Start Watch") {
                        Task { await state.startWatchService() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(state.isBusy || (state.watchServiceState?.running ?? false))

                    Button("Health & Preflight") {
                        state.selectedHub = .configure
                        state.selectedConfigurePanel = .workspaceHealth
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                    Button("Start Watch") {
                        Task { await state.startWatchService() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(state.isBusy || (state.watchServiceState?.running ?? false))

                    Button("Health & Preflight") {
                        state.selectedHub = .configure
                        state.selectedConfigurePanel = .workspaceHealth
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var captureInspector: some View {
        WorkspaceInspectorPane(title: "Capture Inspector", subtitle: "Watch state, queue health, and deterministic recipe") {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.md) {
                watchInspectorCard
                metricsInspectorCard
                recipeInspectorCard
            }
        }
    }

    private var watchInspectorCard: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            SummaryFactStrip(
                facts: watchServiceFacts,
                minItemWidth: 88,
                compact: true
            )

            ViewThatFits(in: .horizontal) {
                HStack(spacing: StopmoUI.Spacing.xs) {
                    Button("Start") {
                        Task { await state.startWatchService() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(state.isBusy || (state.watchServiceState?.running ?? false))

                    Button("Stop") {
                        Task { await state.stopWatchService() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(state.isBusy || !(state.watchServiceState?.running ?? false))

                    Button("Restart") {
                        Task { await state.restartWatchService() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(state.isBusy)
                }

                VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                    Button("Start") {
                        Task { await state.startWatchService() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(state.isBusy || (state.watchServiceState?.running ?? false))

                    Button("Stop") {
                        Task { await state.stopWatchService() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(state.isBusy || !(state.watchServiceState?.running ?? false))

                    Button("Restart") {
                        Task { await state.restartWatchService() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(state.isBusy)
                }
            }

            if let watch = state.watchServiceState {
                if watch.startBlocked == true, let preflight = watch.preflight, !preflight.blockers.isEmpty {
                    Text(preflight.blockers.joined(separator: ", "))
                        .metadataTextStyle(.secondary)
                        .foregroundStyle(.red)
                }
                if let launchError = watch.launchError, !launchError.isEmpty {
                    Text(launchError)
                        .metadataTextStyle(.secondary)
                        .foregroundStyle(.red)
                }

                DisclosureGroup(isExpanded: $showWatchRuntimeDetails) {
                    VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                        KeyValueRow(key: "PID", value: watch.pid.map(String.init) ?? "-", layout: .adaptive(availableWidth: 280))
                        KeyValueRow(key: "Started", value: watch.startedAtUtc ?? "-", layout: .adaptive(availableWidth: 280))
                        KeyValueRow(key: "Config", value: watch.configPath, layout: .stacked, valueStyle: .path)
                        if let logPath = watch.logPath {
                            KeyValueRow(key: "Log", value: logPath, layout: .stacked, valueStyle: .path)
                        }
                        if let crash = watch.crashRecovery {
                            KeyValueRow(key: "Crash Recovery", value: "reset \(crash.lastInflightResetCount) inflight jobs", tone: crash.lastInflightResetCount == 0 ? .success : .warning, layout: .stacked)
                        }
                    }
                    .padding(.top, StopmoUI.Spacing.xs)
                } label: {
                    DisclosureRowLabel(title: "Runtime Details", isExpanded: $showWatchRuntimeDetails)
                }
            }
        }
    }

    private var metricsInspectorCard: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            DisclosureGroup(isExpanded: $showMetricsSummary) {
                let counts = state.queueSnapshot?.counts ?? [:]
                let inflight = state.watchServiceState?.inflightFrames ?? 0
                let workers = state.config.watch.maxWorkers
                let throughput = state.throughputFramesPerMinute

                TimelineView(.periodic(from: Date(), by: 1)) { context in
                    let secondaryMetrics = CaptureMonitorFormatting.compactSecondaryKPIs(
                        throughputFramesPerMinute: throughput,
                        workersInFlight: inflight,
                        maxWorkers: workers,
                        etaLabel: compactETAValueLabel(),
                        lastFrameLabel: lastFrameAgeLabel(at: context.date),
                        hasLastFrame: state.lastFrameAt != nil
                    )

                    VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                        SummaryFactStrip(
                            facts: CaptureMonitorFormatting.compactPrimaryKPIs(queueCounts: counts).map(summaryFact(from:)),
                            minItemWidth: 90,
                            compact: true
                        )
                        SummaryFactStrip(
                            facts: secondaryMetrics.map(summaryFact(from:)),
                            minItemWidth: 110,
                            compact: true
                        )
                    }
                    .padding(.top, StopmoUI.Spacing.xs)
                }
            } label: {
                DisclosureRowLabel(title: "Live Metrics", isExpanded: $showMetricsSummary)
            }

            DisclosureGroup(isExpanded: $showQueueTrend) {
                if state.queueDepthTrend.count < 2 {
                    EmptyStateCard(message: "Collecting queue samples.")
                } else {
                    QueueDepthSparkline(values: state.queueDepthTrend)
                        .frame(height: 90)
                    SummaryFactStrip(
                        facts: [
                            SummaryFact(id: "current", label: "Current", value: "\(state.queueDepthTrend.last ?? 0)", tone: .warning),
                            SummaryFact(id: "peak", label: "Peak", value: "\(state.queueDepthTrend.max() ?? 0)", tone: .danger),
                            SummaryFact(id: "samples", label: "Samples", value: "\(state.queueDepthTrend.count)", tone: .neutral),
                        ],
                        minItemWidth: 84,
                        compact: true
                    )
                }
            } label: {
                DisclosureRowLabel(title: "Queue Trend", isExpanded: $showQueueTrend)
            }
        }
    }

    private var recipeInspectorCard: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
            Text("Deterministic Recipe")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppVisualTokens.textSecondary)
            KeyValueRow(key: "Plate", value: "ARRI LogC3 EI800 + AWG", layout: .adaptive(availableWidth: 280))
            KeyValueRow(
                key: "White Balance",
                value: state.config.pipeline.lockWbFromFirstFrame ? "Shot-locked" : "Manual",
                tone: state.config.pipeline.lockWbFromFirstFrame ? .success : .warning,
                layout: .adaptive(availableWidth: 280)
            )
            KeyValueRow(key: "Exposure", value: String(format: "%.2f stops", state.config.pipeline.exposureOffsetStops), layout: .adaptive(availableWidth: 280))
            KeyValueRow(key: "Output Root", value: state.config.watch.outputDir, layout: .stacked, valueStyle: .path)
        }
    }

    @ViewBuilder
    private var consoleContent: some View {
        switch consoleTab {
        case .activity:
            activityConsole
        case .watchLog:
            watchLogConsole
        case .diagnostics:
            diagnosticsConsole
        }
    }

    private var activityConsole: some View {
        let filteredRows = filteredActivityRows
        let visibleCount = min(activityDisplayLimit, filteredRows.count)
        let visibleRows = Array(filteredRows.prefix(visibleCount))

        return VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: StopmoUI.Spacing.sm) {
                    Picker("Filter", selection: $activityFilter) {
                        ForEach(CaptureActivityFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)

                    Toggle("Pause updates", isOn: $pauseActivityUpdates)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .fixedSize()

                    TextField("Search activity", text: $activitySearchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                }

                VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                    Picker("Filter", selection: $activityFilter) {
                        ForEach(CaptureActivityFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    Toggle("Pause updates", isOn: $pauseActivityUpdates)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    TextField("Search activity", text: $activitySearchText)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack(spacing: StopmoUI.Spacing.sm) {
                StatusChip(label: "Showing \(visibleCount)/\(filteredRows.count)", tone: .neutral, density: .compact)
                if filteredRows.count > visibleCount {
                    Button("Show more") {
                        activityDisplayLimit = min(filteredRows.count, activityDisplayLimit + activityDisplayIncrement)
                    }
                    .buttonStyle(.borderless)
                }
                if visibleCount > initialActivityDisplayLimit {
                    Button("Show less") {
                        activityDisplayLimit = initialActivityDisplayLimit
                    }
                    .buttonStyle(.borderless)
                }
                Spacer(minLength: 0)
                if pauseActivityUpdates {
                    StatusChip(label: "Paused", tone: .warning, density: .compact)
                }
            }

            if filteredRows.isEmpty {
                EmptyStateCard(message: "No activity matches the current filter.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: StopmoUI.Spacing.xxs) {
                        ForEach(Array(visibleRows.enumerated()), id: \.offset) { _, row in
                            activityConsoleRow(row)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 160, maxHeight: 280)
            }
        }
    }

    private var watchLogConsole: some View {
        let visibleTail = Array((state.watchServiceState?.logTail ?? []).suffix(watchLogDisplayLimit))

        return VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            if visibleTail.isEmpty {
                EmptyStateCard(message: "No watch log tail available yet.")
            } else {
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
                .frame(minHeight: 160, maxHeight: 280)
            }
        }
    }

    private var diagnosticsConsole: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            SummaryFactStrip(
                facts: [
                    SummaryFact(id: "events", label: "Events", value: "\(sourceActivityRows.count)", tone: .neutral),
                    SummaryFact(id: "logs", label: "Log Lines", value: "\(min(watchLogDisplayLimit, state.watchServiceState?.logTail.count ?? 0))", tone: .neutral),
                    SummaryFact(id: "samples", label: "Queue Samples", value: "\(state.queueDepthTrend.count)", tone: .neutral),
                    SummaryFact(id: "warnings", label: "Warnings", value: "\(state.logsDiagnostics?.warnings.count ?? 0)", tone: (state.logsDiagnostics?.warnings.isEmpty == false) ? .warning : .neutral),
                ],
                minItemWidth: 94,
                compact: true
            )

            if let warnings = state.logsDiagnostics?.warnings, !warnings.isEmpty {
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                    ForEach(warnings.prefix(6)) { warning in
                        HStack(spacing: StopmoUI.Spacing.sm) {
                            StatusChip(label: warning.severity, tone: warningTone(warning.severity), density: .compact)
                            StatusChip(label: warning.code, tone: .neutral, density: .compact)
                            Text(warning.message)
                                .font(.caption)
                                .lineLimit(1)
                                .foregroundStyle(AppVisualTokens.textSecondary)
                            Spacer(minLength: 0)
                        }
                    }
                }
            } else {
                EmptyStateCard(message: "No recent diagnostic warnings.")
            }
        }
    }

    private var sourceActivityRows: [CaptureActivityRow] {
        let source = pauseActivityUpdates ? frozenEvents : state.liveEvents
        return Array(source.prefix(maxActivitySourceLines)).map(CaptureMonitorFormatting.parseActivityLine(_:))
    }

    private var filteredActivityRows: [CaptureActivityRow] {
        CaptureMonitorFormatting.filterActivityRows(
            sourceActivityRows,
            filter: activityFilter,
            searchTerm: debouncedActivitySearchText
        )
    }

    private func activityConsoleRow(_ row: CaptureActivityRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: StopmoUI.Spacing.sm) {
            Text(row.timestamp ?? "--:--:--")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(AppVisualTokens.textSecondary)
                .frame(width: 62, alignment: .leading)

            Image(systemName: activitySymbol(for: row.severity))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(activityColor(for: row.severity))
                .frame(width: 12, alignment: .leading)

            Text(row.message)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .help(row.rawLine)
    }

    private var captureAlert: (title: String, message: String, tone: StatusTone)? {
        if let launchError = state.watchServiceState?.launchError, !launchError.isEmpty {
            return ("Watch Launch Failed", launchError, .danger)
        }
        if state.watchServiceState?.startBlocked == true,
           let blockers = state.watchServiceState?.preflight?.blockers,
           !blockers.isEmpty
        {
            return ("Watch Start Blocked", blockers.joined(separator: ", "), .warning)
        }
        if let message = state.monitoringLastFailureMessage, !message.isEmpty, state.monitoringConsecutiveFailures > 0 {
            return ("Monitoring Needs Attention", message, .warning)
        }
        return nil
    }

    private var shouldShowAlert: Bool {
        captureAlert != nil
    }

    private var consoleSummary: String {
        switch consoleTab {
        case .activity:
            return "\(sourceActivityRows.count) recent events"
        case .watchLog:
            return "\(min(watchLogDisplayLimit, state.watchServiceState?.logTail.count ?? 0)) log lines"
        case .diagnostics:
            return "Warnings \(state.logsDiagnostics?.warnings.count ?? 0) • Samples \(state.queueDepthTrend.count)"
        }
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

    private var waitingCaptureFacts: [SummaryFact] {
        [
            SummaryFact(id: "watcher", label: "Watcher", value: (state.watchServiceState?.running ?? false) ? "Running" : "Stopped", tone: (state.watchServiceState?.running ?? false) ? .success : .warning),
            SummaryFact(id: "queue", label: "Queue", value: "\(state.queueSnapshot?.total ?? 0)", tone: .neutral),
            SummaryFact(id: "polling", label: "Polling", value: state.monitoringStatusLabel, tone: monitoringTone),
        ]
    }

    private var watchServiceFacts: [SummaryFact] {
        let watch = state.watchServiceState
        let metrics = CaptureMonitorFormatting.watchSummaryMetrics(
            queueCounts: state.queueSnapshot?.counts ?? [:],
            isRunning: watch?.running ?? false,
            inflightFrames: watch?.inflightFrames ?? 0,
            completedFrames: watch?.completedFrames ?? 0,
            monitoringStatusLabel: state.monitoringStatusLabel,
            monitoringTone: monitoringTone
        )
        return metrics.map(summaryFact(from:))
    }

    private func activeShotFacts(for shot: ShotSummaryRow, evaluation: ShotHealthEvaluation) -> [SummaryFact] {
        CaptureMonitorFormatting.activeShotSummaryMetrics(shot: shot, evaluation: evaluation).map(summaryFact(from:))
            + [
                SummaryFact(
                    id: "updated",
                    label: "Updated",
                    value: ShotHealthModel.updatedDisplayLabel(for: shot).replacingOccurrences(of: "Updated ", with: ""),
                    tone: .neutral
                ),
            ]
    }

    private func summaryFact(from metric: CaptureKPIMetric) -> SummaryFact {
        SummaryFact(id: metric.id, label: metric.label, value: metric.value, tone: metric.tone)
    }

    private func captureHeroPreview(for shot: ShotSummaryRow) -> some View {
        ShotThumbnailView(
            shot: shot,
            preferredKind: .latest,
            baseOutputDir: state.config.watch.outputDir,
            width: embedded ? 340 : 460,
            height: embedded ? 191 : 258,
            cornerRadius: 14,
            style: .hero,
            onOpenLightbox: { previewPath in
                previewLightboxItem = ShotLightboxItem(
                    shot: shot,
                    previewKind: .latest,
                    previewPath: previewPath,
                    shotRootPath: shotRootPath(for: shot)
                )
            }
        )
    }

    private func captureHeroMeta(for shot: ShotSummaryRow, evaluation: ShotHealthEvaluation) -> some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.md) {
            Text(shot.shotName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppVisualTokens.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            StatusChip(
                label: evaluation.healthState.rawValue,
                tone: evaluation.healthState.tone
            )

            SummaryFactStrip(
                facts: activeShotFacts(for: shot, evaluation: evaluation),
                minItemWidth: 112
            )
        }
    }

    private var activeShotEvaluation: ShotHealthEvaluation? {
        guard let shot = ShotHealthModel.resolveActiveShot(from: state.shotsSnapshot) else {
            return nil
        }
        return ShotHealthModel.evaluate(shot)
    }

    private var captureNeedsReviewAttention: Bool {
        let queueFailed = state.queueSnapshot?.counts["failed", default: 0] ?? 0
        let evaluations = ShotHealthModel.evaluate(snapshot: state.shotsSnapshot)
        return queueFailed > 0 || evaluations.contains(where: { $0.healthState == .issues || $0.healthState == .inflight })
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

    private func compactETAValueLabel() -> String {
        let label = etaLabel()
        if label.hasPrefix("ETA ") {
            return String(label.dropFirst(4))
        }
        return label
    }

    private func lastFrameAgeLabel(at now: Date) -> String {
        guard let last = state.lastFrameAt else {
            return "--"
        }
        return relativeTimeLabel(from: last, now: now)
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

    private func activitySymbol(for severity: CaptureActivitySeverity) -> String {
        switch severity {
        case .info:
            return "info.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "exclamationmark.octagon.fill"
        case .system:
            return "gearshape.fill"
        }
    }

    private func activityColor(for severity: CaptureActivitySeverity) -> Color {
        switch severity {
        case .info:
            return AppVisualTokens.textSecondary
        case .warning:
            return .orange
        case .error:
            return .red
        case .system:
            return .blue
        }
    }

    private func warningTone(_ severity: String) -> StatusTone {
        let normalized = severity.lowercased()
        if normalized.contains("error") || normalized.contains("critical") {
            return .danger
        }
        if normalized.contains("warn") {
            return .warning
        }
        return .neutral
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
