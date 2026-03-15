import SwiftUI

/// Destructive shot actions that require explicit confirmation in the Review workspace.
private enum ReviewPendingActionKind {
    case restart
    case deleteDB
    case deleteDBAndOutputs
}

private struct ReviewGeneratedArtifactsSummary {
    var fileCount: Int
    var dirCount: Int

    var hasArtifacts: Bool { fileCount + dirCount > 0 }
}

private struct ReviewPendingAction: Identifiable {
    let id = UUID()
    let kind: ReviewPendingActionKind
    let shot: ShotSummaryRow
    let artifacts: ReviewGeneratedArtifactsSummary
}

private struct ReviewSnapshotSignature: Equatable {
    let shotName: String
    let state: String
    let doneFrames: Int
    let failedFrames: Int
    let inflightFrames: Int
    let lastUpdatedAt: String?
    let outputMovPath: String?
    let reviewMovPath: String?
}

/// Redesigned Review surface with grouped list, selected-shot detail, and sidecar recovery actions.
struct ReviewWorkspaceView: View {
    @EnvironmentObject private var state: AppState

    @State private var searchText: String = ""
    @State private var filter: ReviewScopeFilter = .all
    @State private var selectedShotName: String?
    @State private var visibleSections: [ReviewWorkspaceSection] = []
    @State private var previewLightboxItem: ShotLightboxItem?
    @State private var pendingAction: ReviewPendingAction?

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            workspaceToolbar

            ScrollView(.vertical, showsIndicators: true) {
                AdaptiveColumns(breakpoint: 1360, spacing: StopmoUI.Spacing.md) {
                    reviewPrimaryArea
                } secondary: {
                    inspectorColumn
                }
                .padding(.bottom, StopmoUI.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if state.shotsSnapshot == nil {
                Task { await state.refreshLiveData() }
            }
            refreshDerivedState()
        }
        .onChange(of: snapshotSignature) { _, _ in
            refreshDerivedState()
        }
        .onChange(of: filter) { _, _ in
            refreshDerivedState()
        }
        .onChange(of: searchText) { _, _ in
            refreshDerivedState()
        }
        .sheet(item: $previewLightboxItem) { item in
            ShotLightboxView(item: item) { shotRoot in
                state.openPathInFinder(shotRoot)
            }
        }
        .confirmationDialog(
            pendingActionTitle,
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingAction = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let pendingAction {
                switch pendingAction.kind {
                case .restart:
                    Button("Restart Shot", role: .destructive) {
                        confirmPendingAction()
                    }
                case .deleteDB:
                    Button("Delete From DB", role: .destructive) {
                        confirmPendingAction()
                    }
                case .deleteDBAndOutputs:
                    Button("Delete DB + Outputs", role: .destructive) {
                        confirmPendingAction()
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingAction = nil
            }
        } message: {
            Text(pendingActionMessage)
        }
    }

    private var workspaceToolbar: some View {
        ToolbarStrip(title: "Review") {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                SummaryFactStrip(
                    facts: [
                        SummaryFact(id: "issues", label: "Issues", value: "\(sections.first(where: { $0.kind == .issues })?.evaluations.count ?? 0)", tone: (sections.first(where: { $0.kind == .issues })?.evaluations.isEmpty == false) ? .danger : .neutral),
                        SummaryFact(id: "inflight", label: "Inflight", value: "\(sections.first(where: { $0.kind == .inflight })?.evaluations.count ?? 0)", tone: (sections.first(where: { $0.kind == .inflight })?.evaluations.isEmpty == false) ? .warning : .neutral),
                        SummaryFact(id: "ready", label: "Ready", value: "\(sections.first(where: { $0.kind == .ready })?.evaluations.count ?? 0)", tone: .success),
                        SummaryFact(id: "done", label: "Completed", value: "\(sections.first(where: { $0.kind == .completed })?.evaluations.count ?? 0)", tone: .neutral),
                    ],
                    minItemWidth: 100,
                    compact: true
                )

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: StopmoUI.Spacing.sm) {
                        Picker("Scope", selection: $filter) {
                            ForEach(ReviewScopeFilter.allCases) { scope in
                                Text(scope.rawValue).tag(scope)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 320)

                        TextField("Search shot, state, output path", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 340)

                        Spacer(minLength: 0)

                        Button("Queue") {
                            state.selectedTriagePanel = .queue
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Diagnostics") {
                            state.selectedTriagePanel = .diagnostics
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                        Picker("Scope", selection: $filter) {
                            ForEach(ReviewScopeFilter.allCases) { scope in
                                Text(scope.rawValue).tag(scope)
                            }
                        }
                        .pickerStyle(.segmented)

                        TextField("Search shot, state, output path", text: $searchText)
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: StopmoUI.Spacing.sm) {
                            Button("Queue") {
                                state.selectedTriagePanel = .queue
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Diagnostics") {
                                state.selectedTriagePanel = .diagnostics
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private var reviewPrimaryArea: some View {
        AdaptiveColumns(breakpoint: 1080, spacing: StopmoUI.Spacing.md) {
            shotListPane
        } secondary: {
            selectedShotPane
        }
    }

    private var shotListPane: some View {
        SectionCard("Shot List", subtitle: "Grouped by urgency so the next decision is obvious.", density: .compact, surfaceLevel: .panel, chrome: .quiet, showSubtitle: false) {
            if sections.isEmpty {
                EmptyStateCard(message: "No shots match the current filter.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                                HStack {
                                    Text(section.kind.rawValue)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(AppVisualTokens.textSecondary)
                                    Spacer(minLength: 0)
                                    StatusChip(label: "\(section.evaluations.count)", tone: tone(for: section.kind), density: .compact)
                                }

                                ForEach(section.evaluations) { evaluation in
                                    reviewShotRow(evaluation)
                                }
                            }
                        }
                    }
                }
                .frame(minHeight: 420, alignment: .topLeading)
            }
        }
        .frame(width: 340, alignment: .topLeading)
    }

    private func reviewShotRow(_ evaluation: ShotHealthEvaluation) -> some View {
        let shot = evaluation.shot
        let isSelected = selectedShotName == shot.shotName

        return Button {
            selectedShotName = shot.shotName
        } label: {
            HStack(alignment: .top, spacing: DenseShotRowStyle.spacing) {
                ShotThumbnailView(
                    shot: shot,
                    preferredKind: .first,
                    baseOutputDir: state.config.watch.outputDir,
                    width: 72,
                    height: 44,
                    cornerRadius: 8,
                    onOpenLightbox: { previewPath in
                        previewLightboxItem = ShotLightboxItem(
                            shot: shot,
                            previewKind: .first,
                            previewPath: previewPath,
                            shotRootPath: shotRootPath(for: shot)
                        )
                    }
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(shot.shotName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppVisualTokens.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(evaluation.issueSummary)
                        .metadataTextStyle(.secondary)
                        .lineLimit(1)
                    Text(ShotHealthModel.updatedDisplayLabel(for: shot))
                        .metadataTextStyle(.tertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    StatusChip(label: evaluation.healthState.rawValue, tone: evaluation.healthState.tone, density: .compact)
                }
            }
            .padding(.horizontal, DenseShotRowStyle.horizontalPadding)
            .padding(.vertical, DenseShotRowStyle.verticalPadding)
            .frame(minHeight: DenseShotRowStyle.minHeight, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: DenseShotRowStyle.cornerRadius, style: .continuous)
                    .fill(
                        isSelected
                            ? LifecycleHub.triage.accentColor.opacity(0.12)
                            : Color.clear
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: DenseShotRowStyle.cornerRadius, style: .continuous)
                    .stroke(
                        isSelected ? LifecycleHub.triage.accentColor.opacity(0.24) : Color.clear,
                        lineWidth: 0.8
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var selectedShotPane: some View {
        SectionCard(
            "Selected Shot",
            subtitle: selectedEvaluation?.issueSummary ?? "Select a shot to inspect details, outputs, and recovery actions.",
            density: .compact,
            surfaceLevel: .raised,
            chrome: .standard,
            interactionStyle: .passive,
            showTitle: false,
            showSubtitle: false
        ) {
            if let evaluation = selectedEvaluation {
                selectedShotDetail(evaluation)
            } else {
                EmptyStateCard(message: "Choose a shot from the list to inspect it.")
            }
        }
    }

    private func selectedShotDetail(_ evaluation: ShotHealthEvaluation) -> some View {
        let shot = evaluation.shot

        return VStack(alignment: .leading, spacing: StopmoUI.Spacing.md) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: StopmoUI.Spacing.md) {
                    selectedShotPreview(shot)
                    selectedShotHeroMeta(evaluation)
                        .frame(minWidth: 240, maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: StopmoUI.Spacing.md) {
                    selectedShotPreview(shot)
                    selectedShotHeroMeta(evaluation)
                }
            }

            ProgressView(value: progressRatio(for: shot))
                .tint(progressColor(for: evaluation.healthState))

            Text(evaluation.issueSummary)
                .appTextRole(.support)

            Divider()

            VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                Text("Processing")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppVisualTokens.textSecondary)
                KeyValueRow(key: "Shot", value: shot.shotName, layout: .adaptive(availableWidth: 520))
                KeyValueRow(key: "Frames", value: "\(shot.doneFrames) / \(shot.totalFrames)", layout: .adaptive(availableWidth: 520))
                KeyValueRow(key: "Failed Frames", value: "\(shot.failedFrames)", tone: shot.failedFrames > 0 ? .danger : .neutral, layout: .adaptive(availableWidth: 520))
                KeyValueRow(key: "Inflight Frames", value: "\(shot.inflightFrames)", tone: shot.inflightFrames > 0 ? .warning : .neutral, layout: .adaptive(availableWidth: 520))
                KeyValueRow(key: "Assembly", value: shot.assemblyState ?? "-", tone: assemblyTone(shot.assemblyState ?? "-"), layout: .adaptive(availableWidth: 520))
                if let exposure = shot.exposureOffsetStops {
                    KeyValueRow(key: "Exposure Offset", value: String(format: "%.2f stops", exposure), layout: .adaptive(availableWidth: 520))
                }
                if let wb = shot.wbMultipliers, wb.count == 3 {
                    KeyValueRow(
                        key: "Locked WB",
                        value: wb.map { String(format: "%.4f", $0) }.joined(separator: ", "),
                        layout: .stacked
                    )
                }
            }

            VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                Text("Outputs & Files")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppVisualTokens.textSecondary)
                KeyValueRow(key: "Output MOV", value: shot.outputMovPath ?? "-", layout: .stacked, valueStyle: .path)
                KeyValueRow(key: "Review MOV", value: shot.reviewMovPath ?? "-", layout: .stacked, valueStyle: .path)
                KeyValueRow(key: "Manifest", value: manifestPath(for: shot), layout: .stacked, valueStyle: .path)
                KeyValueRow(key: "DPX", value: dpxPath(for: shot), layout: .stacked, valueStyle: .path)
                KeyValueRow(key: "Frame JSON", value: frameJsonPath(for: shot), layout: .stacked, valueStyle: .path)
                KeyValueRow(key: "Truth Frame", value: truthFramePath(for: shot), layout: .stacked, valueStyle: .path)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: StopmoUI.Spacing.sm) {
                    Button("Open Shot Folder") {
                        state.openPathInFinder(shotRootPath(for: shot))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Menu("Path Actions") {
                        Button("Shot Folder") {
                            state.openPathInFinder(shotRootPath(for: shot))
                        }
                        Button("Copy Shot Folder Path") {
                            state.copyTextToPasteboard(shotRootPath(for: shot), label: "shot folder path")
                        }
                        Button("Manifest") {
                            state.openPathInFinder(manifestPath(for: shot))
                        }
                        Button("Copy Manifest Path") {
                            state.copyTextToPasteboard(manifestPath(for: shot), label: "manifest path")
                        }
                        Button("DPX") {
                            state.openPathInFinder(dpxPath(for: shot))
                        }
                        Button("Copy DPX Path") {
                            state.copyTextToPasteboard(dpxPath(for: shot), label: "dpx path")
                        }
                        Button("Frame JSON") {
                            state.openPathInFinder(frameJsonPath(for: shot))
                        }
                        Button("Copy Frame JSON Path") {
                            state.copyTextToPasteboard(frameJsonPath(for: shot), label: "frame json path")
                        }
                        Button("Truth Frame") {
                            state.openPathInFinder(truthFramePath(for: shot))
                        }
                        Button("Copy Truth Frame Path") {
                            state.copyTextToPasteboard(truthFramePath(for: shot), label: "truth frame path")
                        }
                        Button("Copy Shot Name") {
                            state.copyTextToPasteboard(shot.shotName, label: "shot name")
                        }
                    }
                    .controlSize(.small)

                    Button("Open Queue") {
                        state.selectedTriagePanel = .queue
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Open Diagnostics") {
                        state.selectedTriagePanel = .diagnostics
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                    Button("Open Shot Folder") {
                        state.openPathInFinder(shotRootPath(for: shot))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Menu("Path Actions") {
                        Button("Shot Folder") {
                            state.openPathInFinder(shotRootPath(for: shot))
                        }
                        Button("Copy Shot Folder Path") {
                            state.copyTextToPasteboard(shotRootPath(for: shot), label: "shot folder path")
                        }
                        Button("Manifest") {
                            state.openPathInFinder(manifestPath(for: shot))
                        }
                        Button("Copy Manifest Path") {
                            state.copyTextToPasteboard(manifestPath(for: shot), label: "manifest path")
                        }
                        Button("DPX") {
                            state.openPathInFinder(dpxPath(for: shot))
                        }
                        Button("Copy DPX Path") {
                            state.copyTextToPasteboard(dpxPath(for: shot), label: "dpx path")
                        }
                        Button("Frame JSON") {
                            state.openPathInFinder(frameJsonPath(for: shot))
                        }
                        Button("Copy Frame JSON Path") {
                            state.copyTextToPasteboard(frameJsonPath(for: shot), label: "frame json path")
                        }
                        Button("Truth Frame") {
                            state.openPathInFinder(truthFramePath(for: shot))
                        }
                        Button("Copy Truth Frame Path") {
                            state.copyTextToPasteboard(truthFramePath(for: shot), label: "truth frame path")
                        }
                        Button("Copy Shot Name") {
                            state.copyTextToPasteboard(shot.shotName, label: "shot name")
                        }
                    }
                    .controlSize(.small)

                    Button("Open Queue") {
                        state.selectedTriagePanel = .queue
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Open Diagnostics") {
                        state.selectedTriagePanel = .diagnostics
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var inspectorColumn: some View {
        WorkspaceInspectorPane(title: "Recovery", subtitle: "Keep all destructive actions here, not in every row.") {
            if let evaluation = selectedEvaluation {
                recoveryInspector(for: evaluation)
            } else {
                EmptyStateCard(message: "Select a shot to reveal recovery and output actions.")
            }
        }
    }

    private func recoveryInspector(for evaluation: ShotHealthEvaluation) -> some View {
        let shot = evaluation.shot

        return VStack(alignment: .leading, spacing: StopmoUI.Spacing.md) {
            SummaryFactStrip(
                facts: [
                    SummaryFact(id: "failed", label: "Failed", value: "\(shot.failedFrames)", tone: shot.failedFrames > 0 ? .danger : .neutral),
                    SummaryFact(id: "ready", label: "Deliverable", value: evaluation.isDeliverable ? "Yes" : "No", tone: evaluation.isDeliverable ? .success : .neutral),
                    SummaryFact(id: "queue", label: "Queue Failed", value: "\(state.queueSnapshot?.counts["failed"] ?? 0)", tone: (state.queueSnapshot?.counts["failed"] ?? 0) > 0 ? .danger : .neutral),
                ],
                minItemWidth: 94,
                compact: true
            )

            VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                Button("Retry Failed Frames") {
                    Task { await state.retryFailedJobsForShot(shot.shotName) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(shot.failedFrames == 0 || isShotInflight(shot))

                Button("Restart Shot") {
                    requestRestartShot(shot)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isShotInflight(shot))

                Button("Delete From DB") {
                    requestDeleteShot(shot, deleteOutputs: false)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isShotInflight(shot))

                Button("Delete DB + Outputs") {
                    requestDeleteShot(shot, deleteOutputs: true)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isShotInflight(shot))
            }

            Divider()

            Menu("Open Paths") {
                Button("Shot Folder") {
                    state.openPathInFinder(shotRootPath(for: shot))
                }
                Button("Manifest") {
                    state.openPathInFinder(manifestPath(for: shot))
                }
                Button("DPX") {
                    state.openPathInFinder(dpxPath(for: shot))
                }
                Button("Frame JSON") {
                    state.openPathInFinder(frameJsonPath(for: shot))
                }
                Button("Truth Frame") {
                    state.openPathInFinder(truthFramePath(for: shot))
                }
                if let output = shot.outputMovPath, !output.isEmpty {
                    Button("Output MOV") {
                        state.openPathInFinder(output)
                    }
                }
                if let review = shot.reviewMovPath, !review.isEmpty {
                    Button("Review MOV") {
                        state.openPathInFinder(review)
                    }
                }
            }

            Button("Go To Deliver") {
                state.selectedHub = .deliver
                state.selectedDeliverPanel = .dayWrap
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var sections: [ReviewWorkspaceSection] {
        visibleSections
    }

    private var selectedEvaluation: ShotHealthEvaluation? {
        ReviewWorkspaceReducer.selectedEvaluation(
            sections: sections,
            selectedShotName: selectedShotName
        )
    }

    private func refreshDerivedState() {
        visibleSections = ReviewWorkspaceReducer.groupedSections(
            snapshot: state.shotsSnapshot,
            filter: filter,
            searchText: searchText
        )
        selectedShotName = ReviewWorkspaceReducer.resolvedSelection(
            currentSelection: selectedShotName,
            sections: sections
        )
    }

    private func selectedShotPreview(_ shot: ShotSummaryRow) -> some View {
        ShotThumbnailView(
            shot: shot,
            preferredKind: .latest,
            baseOutputDir: state.config.watch.outputDir,
            width: 320,
            height: 180,
            cornerRadius: 12,
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

    private func selectedShotHeroMeta(_ evaluation: ShotHealthEvaluation) -> some View {
        let shot = evaluation.shot

        return VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            Text(shot.shotName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppVisualTokens.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            StatusChip(label: evaluation.healthState.rawValue, tone: evaluation.healthState.tone)

            SummaryFactStrip(
                facts: [
                    SummaryFact(id: "completion", label: "Completion", value: evaluation.completionLabel, tone: evaluation.isDeliverable ? .success : .neutral),
                    SummaryFact(id: "updated", label: "Updated", value: ShotHealthModel.updatedDisplayLabel(for: shot).replacingOccurrences(of: "Updated ", with: ""), tone: .neutral),
                    SummaryFact(id: "state", label: "State", value: shot.state, tone: .neutral),
                ],
                minItemWidth: 96,
                compact: true
            )
        }
    }

    private func tone(for section: ReviewWorkspaceSectionKind) -> StatusTone {
        switch section {
        case .issues:
            return .danger
        case .inflight:
            return .warning
        case .ready:
            return .success
        case .completed:
            return .neutral
        }
    }

    private func progressRatio(for shot: ShotSummaryRow) -> Double {
        guard shot.totalFrames > 0 else {
            return 0
        }
        return min(1.0, max(0.0, Double(shot.doneFrames) / Double(shot.totalFrames)))
    }

    private func progressColor(for state: ShotHealthState) -> Color {
        switch state {
        case .clean:
            return .green.opacity(0.7)
        case .issues:
            return .red.opacity(0.8)
        case .inflight:
            return .orange.opacity(0.8)
        case .queued:
            return AppVisualTokens.textTertiary.opacity(0.8)
        }
    }

    private func isShotInflight(_ shot: ShotSummaryRow) -> Bool {
        shot.inflightFrames > 0
    }

    private func requestRestartShot(_ shot: ShotSummaryRow) {
        guard !isShotInflight(shot) else {
            return
        }
        let artifacts = generatedArtifactsSummary(for: shot)
        if artifacts.hasArtifacts {
            pendingAction = ReviewPendingAction(kind: .restart, shot: shot, artifacts: artifacts)
            return
        }
        Task { await state.restartShotFromBeginning(shot.shotName, cleanOutput: true, resetLocks: true) }
    }

    private func requestDeleteShot(_ shot: ShotSummaryRow, deleteOutputs: Bool) {
        guard !isShotInflight(shot) else {
            return
        }
        let kind: ReviewPendingActionKind = deleteOutputs ? .deleteDBAndOutputs : .deleteDB
        pendingAction = ReviewPendingAction(kind: kind, shot: shot, artifacts: generatedArtifactsSummary(for: shot))
    }

    private var pendingActionTitle: String {
        guard let pendingAction else {
            return "Confirm Action"
        }
        switch pendingAction.kind {
        case .restart:
            return "Restart \(pendingAction.shot.shotName)?"
        case .deleteDB:
            return "Delete \(pendingAction.shot.shotName) From DB?"
        case .deleteDBAndOutputs:
            return "Delete \(pendingAction.shot.shotName) From DB + Outputs?"
        }
    }

    private var pendingActionMessage: String {
        guard let pendingAction else {
            return ""
        }
        switch pendingAction.kind {
        case .restart:
            if pendingAction.artifacts.hasArtifacts {
                return "This shot has \(pendingAction.artifacts.dirCount) generated folder(s) and \(pendingAction.artifacts.fileCount) generated file(s). Restart will rebuild them from the beginning."
            }
            return "Restart will reset this shot's queue rows and rebuild from the beginning."
        case .deleteDB:
            return "This removes the shot from the queue database only. Generated files remain on disk."
        case .deleteDBAndOutputs:
            return "This removes the shot from the queue database and deletes generated shot output artifacts."
        }
    }

    private func confirmPendingAction() {
        guard let pendingAction else {
            return
        }
        self.pendingAction = nil
        switch pendingAction.kind {
        case .restart:
            Task { await state.restartShotFromBeginning(pendingAction.shot.shotName, cleanOutput: true, resetLocks: true) }
        case .deleteDB:
            Task { await state.deleteShot(pendingAction.shot.shotName, deleteOutputs: false) }
        case .deleteDBAndOutputs:
            Task { await state.deleteShot(pendingAction.shot.shotName, deleteOutputs: true) }
        }
    }

    private func generatedArtifactsSummary(for shot: ShotSummaryRow) -> ReviewGeneratedArtifactsSummary {
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
        return ReviewGeneratedArtifactsSummary(fileCount: generatedFiles.count, dirCount: dirCount)
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

    private var snapshotSignature: [ReviewSnapshotSignature] {
        (state.shotsSnapshot?.shots ?? []).map { shot in
            ReviewSnapshotSignature(
                shotName: shot.shotName,
                state: shot.state,
                doneFrames: shot.doneFrames,
                failedFrames: shot.failedFrames,
                inflightFrames: shot.inflightFrames,
                lastUpdatedAt: shot.lastUpdatedAt,
                outputMovPath: shot.outputMovPath,
                reviewMovPath: shot.reviewMovPath
            )
        }
    }

    private func assemblyTone(_ value: String) -> StatusTone {
        let lowered = value.lowercased()
        if lowered.contains("done") {
            return .success
        }
        if lowered.contains("pending") || lowered.contains("dirty") {
            return .warning
        }
        if lowered == "-" {
            return .neutral
        }
        return .danger
    }
}
