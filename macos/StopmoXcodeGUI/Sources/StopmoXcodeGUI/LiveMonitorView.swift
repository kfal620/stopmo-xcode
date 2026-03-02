import SwiftUI

/// View rendering live monitor view.
struct LiveMonitorView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.hubContentWidth) private var hubContentWidth
    var embedded: Bool = false

    private let initialActivityDisplayLimit: Int = 80
    private let activityDisplayIncrement: Int = 80
    private let watchLogDisplayLimit: Int = 120
    private let maxActivitySourceLines: Int = 260
    private let embeddedActivityConsoleHeight: CGFloat = 248
    private let standardActivityConsoleHeight: CGFloat = 292

    @State private var activityFilter: CaptureActivityFilter = .all
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
    @State private var previewLightboxItem: ShotLightboxItem?

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
        .sheet(item: $previewLightboxItem) { item in
            ShotLightboxView(item: item) { shotRoot in
                state.openPathInFinder(shotRoot)
            }
        }
    }

    @ViewBuilder
    private var monitorWorkspaceLayout: some View {
        if embedded {
            embeddedCaptureWorkspaceLayout
        } else {
            AdaptiveColumns(breakpoint: 760) {
                leftMonitorColumn
            } secondary: {
                rightMonitorColumn
            }
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

    private var embeddedCaptureWorkspaceLayout: some View {
        let spacing = StopmoUI.Spacing.md
        let estimatedInnerPadding = StopmoUI.Spacing.sm * 2
        let availableWidth = max(0, hubContentWidth - estimatedInnerPadding)
        let shouldStack = availableWidth == 0 ? false : availableWidth < 980
        let leftWidth = max(0, (availableWidth - spacing) * 0.66)
        let rightWidth = max(0, availableWidth - spacing - leftWidth)

        return Group {
            if shouldStack {
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.lg) {
                    embeddedLeftMonitorColumn
                        .frame(maxWidth: .infinity, alignment: .leading)
                    embeddedRightMonitorColumn
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(alignment: .top, spacing: spacing) {
                    embeddedLeftMonitorColumn
                        .frame(width: availableWidth > 0 ? leftWidth : nil, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    embeddedRightMonitorColumn
                        .frame(width: availableWidth > 0 ? rightWidth : nil, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var embeddedLeftMonitorColumn: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.lg) {
            if shouldShowRecoveryCard {
                monitoringRecoveryCard
            }
            activeShotFocusCard
            liveKpiCard
            if let logTail = state.watchServiceState?.logTail, !logTail.isEmpty {
                watchLogTailCard(logTail)
            }
            activityCard
        }
    }

    private var embeddedRightMonitorColumn: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.lg) {
            watchServiceCard
            queueTrendCard
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
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.md) {
                    Text(shot.shotName)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(shot.shotName)

                    activeShotHeroIdentity(shot: shot, evaluation: evaluation)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    activeShotPrimaryActions(evaluation: evaluation, shot: shot)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ProgressView(value: activeShotProgress(for: shot))
                        .tint(AppVisualTokens.stageAccent(hub: .capture))

                    ViewThatFits(in: .horizontal) {
                        activeShotMetricChips(shot: shot)
                        ScrollView(.horizontal, showsIndicators: false) {
                            activeShotMetricChips(shot: shot)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
            let inflight = state.watchServiceState?.inflightFrames ?? 0
            let workers = state.config.watch.maxWorkers
            let throughput = state.throughputFramesPerMinute

            TimelineView(.periodic(from: Date(), by: 1)) { context in
                let primaryMetrics = CaptureMonitorFormatting.compactPrimaryKPIs(queueCounts: counts)
                let secondaryMetrics = CaptureMonitorFormatting.compactSecondaryKPIs(
                    throughputFramesPerMinute: throughput,
                    workersInFlight: inflight,
                    maxWorkers: workers,
                    etaLabel: compactETAValueLabel(),
                    lastFrameLabel: lastFrameAgeLabel(at: context.date),
                    hasLastFrame: state.lastFrameAt != nil
                )

                VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                    MetricWrap(minItemWidth: 124, spacing: StopmoUI.Spacing.xs) {
                        ForEach(primaryMetrics) { metric in
                            compactKPIChip(metric: metric)
                        }
                    }
                    MetricWrap(minItemWidth: 156, spacing: StopmoUI.Spacing.xs) {
                        ForEach(secondaryMetrics) { metric in
                            compactKPIChip(metric: metric)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
        SectionCard(
            "Activity Feed",
            subtitle: "Job transitions, warnings/errors, and watch assembly events.",
            density: .compact,
            surfaceLevel: .panel,
            chrome: .quiet,
            showSubtitle: false
        ) {
            DisclosureGroup(isExpanded: $showActivityFeed) {
                let filteredRows = filteredActivityRows
                let visibleCount = min(activityDisplayLimit, filteredRows.count)
                let visibleRows = Array(filteredRows.prefix(visibleCount))

                VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: StopmoUI.Spacing.sm) {
                            activityFilterSegmentedControl
                                .frame(minWidth: 250, maxWidth: 360, alignment: .leading)

                            Toggle("Pause updates", isOn: $pauseActivityUpdates)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .fixedSize()

                            TextField("Search activity", text: $activitySearchText)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
                        }
                        VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                            HStack(spacing: StopmoUI.Spacing.sm) {
                                activityFilterMenuControl
                                Toggle("Pause updates", isOn: $pauseActivityUpdates)
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                            }
                            TextField("Search activity", text: $activitySearchText)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    HStack(spacing: StopmoUI.Spacing.sm) {
                        StatusChip(label: "Showing \(visibleCount)/\(filteredRows.count)", tone: .neutral, density: .compact)
                        if filteredRows.count > visibleCount {
                            Button("Show more") {
                                activityDisplayLimit = min(
                                    filteredRows.count,
                                    activityDisplayLimit + activityDisplayIncrement
                                )
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
                        .frame(
                            minHeight: embedded ? embeddedActivityConsoleHeight : 120,
                            maxHeight: embedded ? embeddedActivityConsoleHeight : standardActivityConsoleHeight
                        )
                    }
                }
                .padding(.top, StopmoUI.Spacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                HStack(spacing: StopmoUI.Spacing.sm) {
                    DisclosureRowLabel(
                        title: "Activity (\(sourceActivityRows.count) recent events)",
                        isExpanded: $showActivityFeed
                    )
                }
            }
        }
    }

    private var activityFilterSegmentedControl: some View {
        Picker("Filter", selection: $activityFilter) {
            ForEach(CaptureActivityFilter.allCases) { filter in
                Text(filter.rawValue).tag(filter)
            }
        }
        .pickerStyle(.segmented)
    }

    private var activityFilterMenuControl: some View {
        Picker("Filter", selection: $activityFilter) {
            ForEach(CaptureActivityFilter.allCases) { filter in
                Text(filter.rawValue).tag(filter)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
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

    private func activeShotHeroIdentity(
        shot: ShotSummaryRow,
        evaluation: ShotHealthEvaluation
    ) -> some View {
        HStack(alignment: .top, spacing: StopmoUI.Spacing.md) {
            ShotThumbnailView(
                shot: shot,
                preferredKind: .latest,
                baseOutputDir: state.config.watch.outputDir,
                width: embedded ? 220 : 192,
                height: embedded ? 124 : 108,
                onOpenLightbox: { previewPath in
                    previewLightboxItem = ShotLightboxItem(
                        shot: shot,
                        previewKind: .latest,
                        previewPath: previewPath,
                        shotRootPath: shotRootPath(for: shot)
                    )
                }
            )

            VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                HStack(spacing: StopmoUI.Spacing.xs) {
                    StatusChip(
                        label: evaluation.healthState.rawValue,
                        tone: evaluation.healthState.tone,
                        density: .compact
                    )
                    StatusChip(
                        label: "Done \(shot.doneFrames)/\(max(shot.totalFrames, 0))",
                        tone: evaluation.isDeliverable ? .success : .warning,
                        density: .compact
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let reason = evaluation.readinessReason, !reason.isEmpty, !evaluation.isDeliverable {
                    Text("Readiness: \(reason)")
                        .metadataTextStyle(.secondary)
                        .foregroundStyle(Color.orange.opacity(0.88))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Text(ShotHealthModel.updatedDisplayLabel(for: shot))
                    .metadataTextStyle(.tertiary)
                    .lineLimit(1)
                    .help(shot.lastUpdatedAt ?? "No update timestamp")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func activeShotPrimaryActions(
        evaluation: ShotHealthEvaluation,
        shot: ShotSummaryRow
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: StopmoUI.Spacing.xs) {
                if captureNeedsTriageAttention {
                    Button("Open Triage") {
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
                if evaluation.isDeliverable {
                    Button("Open Deliver") {
                        state.selectedHub = .deliver
                        state.selectedDeliverPanel = .dayWrap
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .fixedSize()

            VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                if captureNeedsTriageAttention {
                    Button("Open Triage") {
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
                if evaluation.isDeliverable {
                    Button("Open Deliver") {
                        state.selectedHub = .deliver
                        state.selectedDeliverPanel = .dayWrap
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func activeShotMetricChips(shot: ShotSummaryRow) -> some View {
        HStack(spacing: StopmoUI.Spacing.xs) {
            StatusChip(label: "Done \(shot.doneFrames)", tone: .success, density: .compact)
            StatusChip(
                label: "In Flight \(shot.inflightFrames)",
                tone: shot.inflightFrames > 0 ? .warning : .neutral,
                density: .compact
            )
            StatusChip(
                label: "Failed \(shot.failedFrames)",
                tone: shot.failedFrames > 0 ? .danger : .neutral,
                density: .compact
            )
            StatusChip(label: "Frames \(shot.totalFrames)", tone: .neutral, density: .compact)
        }
    }

    private func captureKPITile(metric: CaptureKPIMetric) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metric.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppVisualTokens.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(metric.value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(metric.tone == .neutral ? AppVisualTokens.textPrimary : metric.tone.foreground)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, StopmoUI.Spacing.sm)
        .padding(.vertical, StopmoUI.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: StopmoUI.Radius.chip, style: .continuous)
                .fill(metric.tone.background.opacity(metric.tone == .neutral ? 0.75 : 1.0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: StopmoUI.Radius.chip, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.6)
        )
    }

    private func compactKPIChip(metric: CaptureKPIMetric) -> some View {
        HStack(spacing: 5) {
            Text(metric.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppVisualTokens.textSecondary)
                .lineLimit(1)
            Text(metric.value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(metric.tone == .neutral ? AppVisualTokens.textPrimary : metric.tone.foreground)
                .lineLimit(1)
        }
        .padding(.horizontal, StopmoUI.Spacing.xs)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: StopmoUI.Radius.chip, style: .continuous)
                .fill(metric.tone.background.opacity(metric.tone == .neutral ? 0.7 : 0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: StopmoUI.Radius.chip, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.6)
        )
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
