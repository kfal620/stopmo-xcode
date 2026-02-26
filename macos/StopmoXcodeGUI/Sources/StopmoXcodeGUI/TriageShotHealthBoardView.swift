import SwiftUI

private enum TriageRecoveryMode: String, CaseIterable, Identifiable {
    case queue = "Queue Recovery"
    case diagnostics = "Diagnostics"

    var id: String { rawValue }
}

private enum TriageShotFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case issues = "Issues"
    case inflight = "Inflight"
    case clean = "Clean"

    var id: String { rawValue }
}

struct TriageShotHealthBoardView: View {
    @EnvironmentObject private var state: AppState

    @State private var searchText: String = ""
    @State private var expandedShotNames: Set<String> = []
    @State private var showRecoveryDrawer: Bool = false
    @State private var recoveryMode: TriageRecoveryMode = .queue
    @State private var shotFilter: TriageShotFilter = .all

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.lg) {
                toolbarStrip
                healthBoardCard
                recoveryDrawerCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(StopmoUI.Spacing.sm)
        }
        .onAppear {
            if state.shotsSnapshot == nil {
                Task { await state.refreshLiveData() }
            }
        }
    }

    private var toolbarStrip: some View {
        ToolbarStrip(title: "Shot Health Toolbar") {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                HStack(alignment: .center, spacing: StopmoUI.Spacing.xs) {
                    Picker("State", selection: $shotFilter) {
                        ForEach(TriageShotFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)
                    TextField("Search shot/state/path", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)
                    Spacer(minLength: 0)
                }
                HStack(spacing: StopmoUI.Spacing.xs) {
                    StatusChip(label: "Clean \(cleanCount)", tone: .success, density: .compact)
                    StatusChip(label: "Issues \(issuesCount)", tone: issuesCount > 0 ? .danger : .neutral, density: .compact)
                    StatusChip(label: "Inflight \(inflightCount)", tone: inflightCount > 0 ? .warning : .neutral, density: .compact)
                    StatusChip(label: "Total \(filteredEvaluations.count)", tone: .neutral, density: .compact)
                }
            }
        }
    }

    private var healthBoardCard: some View {
        SectionCard(
            "Health Board",
            subtitle: "Expand cards for full shot detail and recovery actions.",
            density: .compact,
            surfaceLevel: .panel,
            chrome: .quiet,
            showTitle: false,
            showSubtitle: false
        ) {
            if filteredEvaluations.isEmpty {
                EmptyStateCard(message: "No shots available for current filters.")
            } else {
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                    ForEach(filteredEvaluations) { evaluation in
                        shotCard(evaluation)
                    }
                }
            }
        }
    }

    private func shotCard(_ evaluation: ShotHealthEvaluation) -> some View {
        let shot = evaluation.shot
        let isExpanded = expandedShotNames.contains(shot.shotName)
        let updatedLabel = ShotHealthModel.updatedDisplayLabel(for: shot)

        return VStack(alignment: .leading, spacing: DenseShotRowStyle.spacing) {
            Button {
                toggleExpanded(shot.shotName)
            } label: {
                HStack(spacing: StopmoUI.Spacing.sm) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.secondary)
                    Text(shot.shotName)
                        .font(.subheadline.weight(.semibold))
                    StatusChip(label: evaluation.healthState.rawValue, tone: evaluation.healthState.tone, density: .compact)
                    StatusChip(label: evaluation.completionLabel, tone: evaluation.isDeliverable ? .success : .warning, density: .compact)
                    Text(updatedLabel)
                        .metadataTextStyle(.tertiary)
                        .help(shot.lastUpdatedAt ?? "No update timestamp")
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ProgressView(value: progressRatio(for: shot))
                .tint(progressTone(for: evaluation.healthState))
                .opacity(0.8)

            HStack(spacing: StopmoUI.Spacing.xs) {
                Button("Open Folder") {
                    state.openPathInFinder(shotRootPath(for: shot))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Menu("More") {
                    Button("Open Manifest") {
                        state.openPathInFinder(manifestPath(for: shot))
                    }
                    Button("Open Logs Root") {
                        state.openPathInFinder(state.config.logFile ?? state.repoRoot)
                    }
                    Button("Open DPX") {
                        state.openPathInFinder(dpxPath(for: shot))
                    }
                    Button("Open Frame JSON") {
                        state.openPathInFinder(frameJsonPath(for: shot))
                    }
                    Button("Open Truth Frame") {
                        state.openPathInFinder(truthFramePath(for: shot))
                    }
                    if let output = shot.outputMovPath, !output.isEmpty {
                        Button("Open Output MOV") {
                            state.openPathInFinder(output)
                        }
                    }
                }
                .controlSize(.small)
            }

            if isExpanded {
                SurfaceContainer(level: .card, chrome: .quiet, cornerRadius: 8) {
                    expandedShotContent(shot)
                        .padding(StopmoUI.Spacing.sm)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: DenseShotRowStyle.minHeight, alignment: .topLeading)
        .padding(.horizontal, DenseShotRowStyle.horizontalPadding)
        .padding(.vertical, DenseShotRowStyle.verticalPadding)
        .background {
            SurfaceContainer(level: .card, chrome: .quiet, cornerRadius: DenseShotRowStyle.cornerRadius) {
                Color.clear
            }
        }
    }

    private func expandedShotContent(_ shot: ShotSummaryRow) -> some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
            KeyValueRow(key: "Shot", value: shot.shotName)
            KeyValueRow(key: "State", value: shot.state, tone: ShotHealthModel.healthState(for: shot).tone)
            KeyValueRow(key: "Assembly", value: shot.assemblyState ?? "-", tone: assemblyTone(shot.assemblyState ?? "-"))
            KeyValueRow(
                key: "Frames",
                value: "\(shot.doneFrames) done / \(shot.failedFrames) failed / \(shot.inflightFrames) inflight / \(shot.totalFrames) total"
            )
            KeyValueRow(key: "Last Updated", value: shot.lastUpdatedAt ?? "-")

            if let exposure = shot.exposureOffsetStops {
                KeyValueRow(key: "Effective Exposure Offset", value: String(format: "%.3f stops", exposure))
            } else {
                KeyValueRow(key: "Effective Exposure Offset", value: "-")
            }

            if let wb = shot.wbMultipliers, !wb.isEmpty {
                let wbText = wb.map { String(format: "%.4f", $0) }.joined(separator: ", ")
                KeyValueRow(key: "Locked WB Multipliers", value: wbText)
            } else {
                KeyValueRow(key: "Locked WB Multipliers", value: "-")
            }

            KeyValueRow(
                key: "Output MOV",
                value: shot.outputMovPath ?? "-",
                tone: pathExists(shot.outputMovPath) ? .success : .neutral
            )
            KeyValueRow(
                key: "Review MOV",
                value: shot.reviewMovPath ?? "-",
                tone: pathExists(shot.reviewMovPath) ? .success : .neutral
            )

            HStack(spacing: StopmoUI.Spacing.sm) {
                Button("Open DPX") {
                    state.openPathInFinder(dpxPath(for: shot))
                }
                Button("Open Frame JSON") {
                    state.openPathInFinder(frameJsonPath(for: shot))
                }
                Button("Open Truth Frame") {
                    state.openPathInFinder(truthFramePath(for: shot))
                }
                if let output = shot.outputMovPath, !output.isEmpty {
                    Button("Open Output MOV") {
                        state.openPathInFinder(output)
                    }
                }
            }
            .padding(.top, StopmoUI.Spacing.xs)
        }
    }

    private var recoveryDrawerCard: some View {
        SectionCard(
            "Recovery Drawer",
            subtitle: "Collapsed by default; open only when recovery is needed.",
            density: .compact,
            surfaceLevel: .panel,
            chrome: .quiet,
            showSubtitle: false
        ) {
            DisclosureGroup(isExpanded: $showRecoveryDrawer) {
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.md) {
                    Picker("Recovery Mode", selection: $recoveryMode) {
                        ForEach(TriageRecoveryMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 320)

                    switch recoveryMode {
                    case .queue:
                        queueRecoveryContent
                    case .diagnostics:
                        diagnosticsRecoveryContent
                    }
                }
                .padding(.top, StopmoUI.Spacing.xs)
            } label: {
                HStack(spacing: StopmoUI.Spacing.sm) {
                    Text("Show Recovery Tools")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    StatusChip(label: "Queue + Diagnostics", tone: .neutral, density: .compact)
                }
            }
        }
    }

    private var queueRecoveryContent: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            HStack(spacing: StopmoUI.Spacing.sm) {
                StatusChip(label: "Failed \(failedQueueCount)", tone: failedQueueCount > 0 ? .danger : .neutral, density: .compact)
                StatusChip(label: "Inflight \(inflightQueueCount)", tone: inflightQueueCount > 0 ? .warning : .neutral, density: .compact)
                StatusChip(label: "Total \(state.queueSnapshot?.total ?? 0)", tone: .neutral, density: .compact)
            }

            HStack(spacing: StopmoUI.Spacing.sm) {
                Button("Retry Failed") {
                    Task { await state.retryFailedQueueJobs() }
                }
                .disabled(state.isBusy || failedQueueCount == 0)

                Button("Export Queue Snapshot") {
                    state.exportQueueSnapshot()
                }
                .disabled(state.isBusy || state.queueSnapshot == nil)

                Button("Open Full Queue Workspace") {
                    state.selectedTriagePanel = .queue
                }
            }

            if failedQueueRows.isEmpty {
                EmptyStateCard(message: "No failed queue rows.")
            } else {
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                    ForEach(failedQueueRows.prefix(5)) { row in
                        HStack(spacing: StopmoUI.Spacing.sm) {
                            StatusChip(label: "#\(row.id)", tone: .danger, density: .compact)
                            Text(row.shot)
                                .font(.caption.weight(.semibold))
                            Text("f\(row.frame)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(row.lastError ?? "failed")
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Button("Retry") {
                                Task { await state.retryFailedQueueJobs(jobIds: [row.id]) }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
    }

    private var diagnosticsRecoveryContent: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            HStack(spacing: StopmoUI.Spacing.sm) {
                StatusChip(label: "Warnings \(state.logsDiagnostics?.warnings.count ?? 0)", tone: (state.logsDiagnostics?.warnings.count ?? 0) > 0 ? .warning : .neutral, density: .compact)
                StatusChip(label: "Entries \(state.logsDiagnostics?.entries.count ?? 0)", tone: .neutral, density: .compact)
            }

            HStack(spacing: StopmoUI.Spacing.sm) {
                Button("Refresh Diagnostics") {
                    Task { await state.refreshLogsDiagnostics() }
                }
                .disabled(state.isBusy)

                Button("Create Diagnostics Bundle") {
                    Task { await state.copyDiagnosticsBundle() }
                }
                .disabled(state.isBusy)

                Button("Open Full Diagnostics Workspace") {
                    state.selectedTriagePanel = .diagnostics
                }
            }

            if let bundle = state.lastDiagnosticsBundlePath, !bundle.isEmpty {
                HStack(spacing: StopmoUI.Spacing.sm) {
                    Text(bundle)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Open") {
                        state.openPathInFinder(bundle)
                    }
                    Button("Copy") {
                        state.copyTextToPasteboard(bundle, label: "bundle path")
                    }
                }
            }

            if latestWarnings.isEmpty {
                EmptyStateCard(message: "No recent diagnostic warnings.")
            } else {
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                    ForEach(latestWarnings.prefix(5)) { warning in
                        HStack(spacing: StopmoUI.Spacing.sm) {
                            StatusChip(label: warning.severity, tone: warningTone(warning.severity), density: .compact)
                            StatusChip(label: warning.code, tone: .neutral, density: .compact)
                            Text(warning.message)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var filteredEvaluations: [ShotHealthEvaluation] {
        let stateFilteredRows = allEvaluations.filter(matchesStateFilter)
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return stateFilteredRows }
        return stateFilteredRows.filter { row in
            let haystack = [
                row.shot.shotName,
                row.shot.state,
                row.shot.assemblyState ?? "",
                row.shot.lastUpdatedAt ?? "",
                row.shot.outputMovPath ?? "",
                row.shot.reviewMovPath ?? "",
                row.readinessReason ?? "",
            ]
            .joined(separator: " ")
            .lowercased()
            return haystack.contains(term)
        }
    }

    private var allEvaluations: [ShotHealthEvaluation] {
        ShotHealthModel.evaluate(snapshot: state.shotsSnapshot).sorted { lhs, rhs in
            let left = lhs.shot.lastUpdatedAt ?? ""
            let right = rhs.shot.lastUpdatedAt ?? ""
            if left == right {
                return lhs.shot.shotName.localizedCaseInsensitiveCompare(rhs.shot.shotName) == .orderedAscending
            }
            return left > right
        }
    }

    private func matchesStateFilter(_ evaluation: ShotHealthEvaluation) -> Bool {
        switch shotFilter {
        case .all:
            return true
        case .issues:
            return evaluation.healthState == .issues
        case .inflight:
            return evaluation.healthState == .inflight
        case .clean:
            return evaluation.healthState == .clean
        }
    }

    private var cleanCount: Int {
        filteredEvaluations.filter { $0.healthState == .clean }.count
    }

    private var issuesCount: Int {
        filteredEvaluations.filter { $0.healthState == .issues }.count
    }

    private var inflightCount: Int {
        filteredEvaluations.filter { $0.healthState == .inflight }.count
    }

    private var failedQueueCount: Int {
        state.queueSnapshot?.counts["failed", default: 0] ?? 0
    }

    private var inflightQueueCount: Int {
        let counts = state.queueSnapshot?.counts ?? [:]
        return counts["detected", default: 0]
            + counts["decoding", default: 0]
            + counts["xform", default: 0]
            + counts["dpx_write", default: 0]
    }

    private var failedQueueRows: [QueueJobRecord] {
        (state.queueSnapshot?.recent ?? []).filter { $0.state.lowercased() == "failed" }
    }

    private var latestWarnings: [DiagnosticWarningRecord] {
        state.logsDiagnostics?.warnings ?? []
    }

    private func toggleExpanded(_ shotName: String) {
        if expandedShotNames.contains(shotName) {
            expandedShotNames.remove(shotName)
        } else {
            expandedShotNames.insert(shotName)
        }
    }

    private func progressRatio(for shot: ShotSummaryRow) -> Double {
        guard shot.totalFrames > 0 else {
            return 0
        }
        return min(1.0, max(0.0, Double(shot.doneFrames) / Double(shot.totalFrames)))
    }

    private func progressTone(for healthState: ShotHealthState) -> Color {
        switch healthState {
        case .clean:
            return .green.opacity(0.75)
        case .issues:
            return .red.opacity(0.9)
        case .inflight:
            return .orange.opacity(0.85)
        case .queued:
            return AppVisualTokens.textSecondary.opacity(0.75)
        }
    }

    private func shotRootPath(for shot: ShotSummaryRow) -> String {
        let base = state.config.watch.outputDir.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            return shot.shotName
        }
        return (base as NSString).appendingPathComponent(shot.shotName)
    }

    private func dpxPath(for shot: ShotSummaryRow) -> String {
        (shotRootPath(for: shot) as NSString).appendingPathComponent("dpx")
    }

    private func frameJsonPath(for shot: ShotSummaryRow) -> String {
        (shotRootPath(for: shot) as NSString).appendingPathComponent("frame_json")
    }

    private func truthFramePath(for shot: ShotSummaryRow) -> String {
        (shotRootPath(for: shot) as NSString).appendingPathComponent("truth_frame")
    }

    private func manifestPath(for shot: ShotSummaryRow) -> String {
        (shotRootPath(for: shot) as NSString).appendingPathComponent("manifest.json")
    }

    private func pathExists(_ path: String?) -> Bool {
        guard let path, !path.isEmpty else {
            return false
        }
        return FileManager.default.fileExists(atPath: path)
    }

    private func assemblyTone(_ value: String) -> StatusTone {
        let v = value.lowercased()
        if v.contains("done") {
            return .success
        }
        if v.contains("pending") || v.contains("dirty") {
            return .warning
        }
        if v == "-" {
            return .neutral
        }
        return .danger
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
}
