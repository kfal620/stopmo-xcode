import SwiftUI

/// Enumeration for triage recovery mode.
private enum TriageRecoveryMode: String, CaseIterable, Identifiable {
    case queue = "Queue Recovery"
    case diagnostics = "Diagnostics"

    var id: String { rawValue }
}

/// Enumeration for triage shot filter.
private enum TriageShotFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case issues = "Issues"
    case inflight = "Inflight"
    case clean = "Clean"

    var id: String { rawValue }
}

/// Enumeration for pending shot action confirmations.
private enum TriageShotPendingActionKind {
    case restart
    case deleteDB
    case deleteDBAndOutputs
}

/// Data/view model for generated artifact summary for one shot.
private struct ShotGeneratedArtifactsSummary {
    var fileCount: Int
    var dirCount: Int

    var hasArtifacts: Bool { fileCount + dirCount > 0 }
}

/// Data/view model for shot action requiring user confirmation.
private struct TriageShotPendingAction: Identifiable {
    let id = UUID()
    let kind: TriageShotPendingActionKind
    let shot: ShotSummaryRow
    let artifacts: ShotGeneratedArtifactsSummary
}

/// View rendering triage shot health board view.
struct TriageShotHealthBoardView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.hubContentWidth) private var hubContentWidth

    @State private var searchText: String = ""
    @State private var expandedShotNames: Set<String> = []
    @State private var showRecoveryDrawer: Bool = false
    @State private var recoveryMode: TriageRecoveryMode = .queue
    @State private var shotFilter: TriageShotFilter = .all
    @State private var previewLightboxItem: ShotLightboxItem?
    @State private var pendingShotAction: TriageShotPendingAction?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.lg) {
                toolbarStrip
                triageWorkspaceLayout
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(StopmoUI.Spacing.sm)
        }
        .onAppear {
            if state.shotsSnapshot == nil {
                Task { await state.refreshLiveData() }
            }
        }
        .sheet(item: $previewLightboxItem) { item in
            ShotLightboxView(item: item) { shotRoot in
                state.openPathInFinder(shotRoot)
            }
        }
        .confirmationDialog(
            pendingActionTitle,
            isPresented: Binding(
                get: { pendingShotAction != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingShotAction = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let pendingShotAction {
                switch pendingShotAction.kind {
                case .restart:
                    Button("Restart Shot", role: .destructive) {
                        confirmPendingShotAction()
                    }
                case .deleteDB:
                    Button("Delete From DB", role: .destructive) {
                        confirmPendingShotAction()
                    }
                case .deleteDBAndOutputs:
                    Button("Delete DB + Outputs", role: .destructive) {
                        confirmPendingShotAction()
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingShotAction = nil
            }
        } message: {
            Text(pendingActionMessage)
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

    private var triageWorkspaceLayout: some View {
        Group {
            if hubContentWidth > 0, hubContentWidth < 980 {
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.md) {
                    recoveryDrawerCard
                    shotsPanel
                }
            } else {
                AdaptiveColumns(breakpoint: 980, spacing: StopmoUI.Spacing.md) {
                    shotsPanel
                } secondary: {
                    recoveryDrawerCard
                }
            }
        }
    }

    private var shotsPanel: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            shotsPanelHeader
            healthBoardCard
        }
    }

    private var shotsPanelHeader: some View {
        HStack(spacing: StopmoUI.Spacing.xs) {
            Text("Shots")
                .font(.headline.weight(.semibold))
            Image(systemName: "info.circle")
                .foregroundStyle(AppVisualTokens.textSecondary)
                .help("Shots processed from RAW -> DPX.")
            Spacer(minLength: 0)
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
                    ShotThumbnailView(
                        shot: shot,
                        preferredKind: .first,
                        baseOutputDir: state.config.watch.outputDir,
                        width: 58,
                        height: 34,
                        cornerRadius: 6,
                        onOpenLightbox: { previewPath in
                            previewLightboxItem = ShotLightboxItem(
                                shot: shot,
                                previewKind: .first,
                                previewPath: previewPath,
                                shotRootPath: shotRootPath(for: shot)
                            )
                        }
                    )
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

                Button("Restart Shot") {
                    requestRestartShot(shot)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isShotInflight(shot))
                .help(isShotInflight(shot) ? "Shot has inflight jobs. Wait until idle or stop watch first." : "Reset this shot and rebuild from beginning.")

                Menu("More") {
                    Button("Retry Failed Frames") {
                        Task { await state.retryFailedJobsForShot(shot.shotName) }
                    }
                    .disabled(shot.failedFrames == 0 || isShotInflight(shot))

                    Divider()

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

                    Divider()

                    Button("Delete From DB", role: .destructive) {
                        requestDeleteShot(shot, deleteOutputs: false)
                    }
                    .disabled(isShotInflight(shot))
                    Button("Delete DB + Outputs", role: .destructive) {
                        requestDeleteShot(shot, deleteOutputs: true)
                    }
                    .disabled(isShotInflight(shot))
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
            ShotThumbnailView(
                shot: shot,
                preferredKind: .first,
                baseOutputDir: state.config.watch.outputDir,
                width: 220,
                height: 124,
                onOpenLightbox: { previewPath in
                    previewLightboxItem = ShotLightboxItem(
                        shot: shot,
                        previewKind: .first,
                        previewPath: previewPath,
                        shotRootPath: shotRootPath(for: shot)
                    )
                }
            )

            KeyValueRow(key: "Shot", value: shot.shotName)
            KeyValueRow(key: "State", value: shot.state, tone: ShotHealthModel.healthState(for: shot).tone)
            KeyValueRow(key: "Assembly", value: shot.assemblyState ?? "-", tone: assemblyTone(shot.assemblyState ?? "-"))
            KeyValueRow(
                key: "Frames",
                value: "\(shot.doneFrames) done / \(shot.failedFrames) failed / \(shot.inflightFrames) inflight / \(shot.totalFrames) total"
            )
            KeyValueRow(key: "First Shot", value: displayShotTimestamp(shot.firstShotAt))
            KeyValueRow(key: "Last Shot", value: displayShotTimestamp(shot.lastUpdatedAt))

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
            }
            .padding(.top, StopmoUI.Spacing.xs)
        }
    }

    private var recoveryDrawerCard: some View {
        SectionCard(
            "Recovery",
            subtitle: "Queue retry and diagnostics actions.",
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
                DisclosureRowLabel(title: "Show Recovery Tools", isExpanded: $showRecoveryDrawer) {
                    HStack(spacing: StopmoUI.Spacing.xs) {
                        StatusChip(label: "Failed \(failedQueueCount)", tone: failedQueueCount > 0 ? .danger : .neutral, density: .compact)
                        StatusChip(label: "Inflight \(inflightQueueCount)", tone: inflightQueueCount > 0 ? .warning : .neutral, density: .compact)
                        StatusChip(label: "Warnings \(state.logsDiagnostics?.warnings.count ?? 0)", tone: (state.logsDiagnostics?.warnings.count ?? 0) > 0 ? .warning : .neutral, density: .compact)
                    }
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

    private var pendingActionTitle: String {
        guard let action = pendingShotAction else { return "Confirm Action" }
        switch action.kind {
        case .restart:
            return "Restart \(action.shot.shotName)?"
        case .deleteDB:
            return "Delete \(action.shot.shotName) From DB?"
        case .deleteDBAndOutputs:
            return "Delete \(action.shot.shotName) From DB + Outputs?"
        }
    }

    private var pendingActionMessage: String {
        guard let action = pendingShotAction else { return "" }
        switch action.kind {
        case .restart:
            if action.artifacts.hasArtifacts {
                return "This shot has \(action.artifacts.dirCount) generated folder(s) and \(action.artifacts.fileCount) generated file(s). Restart will overwrite/rebuild these outputs from RAW -> DPX."
            }
            return "Restart will reset this shot's queue rows to detected and rebuild from the beginning."
        case .deleteDB:
            return "This removes the shot from queue database tables only. Generated output files remain on disk."
        case .deleteDBAndOutputs:
            return "This removes the shot from queue database and deletes generated shot output artifacts from the output directory."
        }
    }

    private func confirmPendingShotAction() {
        guard let action = pendingShotAction else { return }
        pendingShotAction = nil
        switch action.kind {
        case .restart:
            Task { await state.restartShotFromBeginning(action.shot.shotName, cleanOutput: true, resetLocks: true) }
        case .deleteDB:
            Task { await state.deleteShot(action.shot.shotName, deleteOutputs: false) }
        case .deleteDBAndOutputs:
            Task { await state.deleteShot(action.shot.shotName, deleteOutputs: true) }
        }
    }

    private func requestRestartShot(_ shot: ShotSummaryRow) {
        guard !isShotInflight(shot) else {
            return
        }
        let artifacts = generatedArtifactsSummary(for: shot)
        if artifacts.hasArtifacts {
            pendingShotAction = TriageShotPendingAction(kind: .restart, shot: shot, artifacts: artifacts)
            return
        }
        Task { await state.restartShotFromBeginning(shot.shotName, cleanOutput: true, resetLocks: true) }
    }

    private func requestDeleteShot(_ shot: ShotSummaryRow, deleteOutputs: Bool) {
        guard !isShotInflight(shot) else {
            return
        }
        let kind: TriageShotPendingActionKind = deleteOutputs ? .deleteDBAndOutputs : .deleteDB
        pendingShotAction = TriageShotPendingAction(
            kind: kind,
            shot: shot,
            artifacts: generatedArtifactsSummary(for: shot)
        )
    }

    private func isShotInflight(_ shot: ShotSummaryRow) -> Bool {
        shot.inflightFrames > 0
    }

    private func generatedArtifactsSummary(for shot: ShotSummaryRow) -> ShotGeneratedArtifactsSummary {
        let fileManager = FileManager.default
        let shotRoot = URL(fileURLWithPath: shotRootPath(for: shot))
        var generatedFiles: Set<String> = []
        var dirCount = 0
        let generatedDirs = ["dpx", "frame_json", "preview", "truth_frame", "debug_linear"]
        for name in generatedDirs {
            let url = shotRoot.appendingPathComponent(name)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                dirCount += 1
                if let enumerator = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) {
                    for case let fileURL as URL in enumerator {
                        if (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                            generatedFiles.insert(fileURL.path)
                        }
                    }
                }
            }
        }

        for fileName in ["manifest.json", "README.txt", "show_lut_rec709.cube"] {
            let path = shotRoot.appendingPathComponent(fileName).path
            if fileManager.fileExists(atPath: path) {
                generatedFiles.insert(path)
            }
        }
        if let output = shot.outputMovPath, fileManager.fileExists(atPath: output) {
            generatedFiles.insert(output)
        }
        if let review = shot.reviewMovPath, fileManager.fileExists(atPath: review) {
            generatedFiles.insert(review)
        }
        if let entries = try? fileManager.contentsOfDirectory(at: shotRoot, includingPropertiesForKeys: [.isRegularFileKey]) {
            for entry in entries where entry.pathExtension.lowercased() == "mov" {
                if (try? entry.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                    generatedFiles.insert(entry.path)
                }
            }
        }
        return ShotGeneratedArtifactsSummary(fileCount: generatedFiles.count, dirCount: dirCount)
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

    private func displayShotTimestamp(_ raw: String?) -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            return "-"
        }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        guard let date = fractional.date(from: raw) ?? plain.date(from: raw) else {
            return raw
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "M/d/yyyy h:mm:ss a"
        return formatter.string(from: date)
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
