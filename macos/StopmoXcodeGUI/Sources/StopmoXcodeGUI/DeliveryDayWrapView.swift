import AppKit
import SwiftUI

private enum DeliveryConsoleTab: String, CaseIterable, Identifiable {
    case timeline = "Run Timeline"
    case diagnostics = "Diagnostics"

    var id: String { rawValue }
}

/// Delivery workspace that coordinates shot selection, batch execution, previews, and diagnostics links.
struct DeliveryDayWrapView: View {
    @EnvironmentObject private var state: AppState

    @AppStorage("tools.dpx.input_dir")
    private var dpxInputDir: String = ""
    @AppStorage("tools.dpx.output_dir")
    private var dpxOutputDir: String = ""
    @AppStorage("tools.dpx.framerate")
    private var dpxFramerate: Int = 24
    @AppStorage("tools.dpx.overwrite")
    private var dpxOverwrite: Bool = true

    @State private var selectedShotNames: Set<String> = []
    @State private var showAdvancedSettings: Bool = false
    @State private var showNotReadyShots: Bool = false
    @State private var showConsole: Bool = false
    @State private var consoleTab: DeliveryConsoleTab = .timeline
    @State private var consolePinnedOpen: Bool = false
    @State private var previewLightboxItem: ShotLightboxItem?

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            deliveryHeaderBar

            ScrollView(.vertical, showsIndicators: true) {
                AdaptiveColumns(breakpoint: 1380, spacing: StopmoUI.Spacing.md) {
                    HStack(alignment: .top, spacing: StopmoUI.Spacing.md) {
                        shotSelectionPane
                            .frame(width: 344, alignment: .topLeading)
                            .frame(maxHeight: .infinity, alignment: .topLeading)

                        runPlanPane
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                } secondary: {
                    inspectorPane
                }
                .padding(.bottom, StopmoUI.Spacing.xs)
            }

            WorkspaceConsoleDock(
                title: consoleTab.rawValue,
                summary: consoleSummary,
                isExpanded: $showConsole
            ) {
                Picker("Console", selection: $consoleTab) {
                    ForEach(DeliveryConsoleTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            } content: {
                consoleContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            hydrateDefaultsIfNeeded()
            syncSelectionFromSnapshot()
            if state.shotsSnapshot == nil {
                Task { await state.refreshLiveData(silent: true) }
            }
            if state.deliveryRunState.status == .running {
                consoleTab = .timeline
                showConsole = true
            }
        }
        .onChange(of: deliverySnapshotSignature) { _, _ in
            syncSelectionFromSnapshot()
        }
        .onChange(of: state.deliveryRunState.status) { previous, next in
            if next == .running {
                consoleTab = .timeline
                showConsole = true
            } else if previous == .running && !consolePinnedOpen {
                showConsole = false
            }
        }
        .sheet(item: $previewLightboxItem) { item in
            ShotLightboxView(item: item) { shotRoot in
                state.openPathInFinder(shotRoot)
            }
        }
    }

    private var deliveryHeaderBar: some View {
        ToolbarStrip(title: "Deliver") {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                SummaryFactStrip(
                    facts: [
                        SummaryFact(id: "ready", label: "Ready", value: "\(readyShotEvaluations.count)", tone: .success),
                        SummaryFact(id: "selected", label: "Selected", value: "\(selectedReadyShotEvaluations.count)", tone: selectedReadyShotEvaluations.isEmpty ? .neutral : .warning),
                        SummaryFact(id: "blocked", label: "Blocked", value: "\(notReadyShotEvaluations.count)", tone: notReadyShotEvaluations.isEmpty ? .neutral : .warning),
                        SummaryFact(id: "root", label: "Output Root", value: watchOutputRootReady ? "Ready" : "Missing", tone: watchOutputRootReady ? .success : .danger),
                    ],
                    minItemWidth: 96,
                    compact: true
                )
            }
        }
    }

    private var shotSelectionPane: some View {
        SectionCard("Deliverable Shots", subtitle: "Select ready shots or run one directly.", density: .compact, surfaceLevel: .panel, chrome: .quiet, showSubtitle: false) {
            if readyShotEvaluations.isEmpty {
                EmptyStateCard(message: "No shots are ready for delivery yet.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                        ForEach(readyShotEvaluations) { evaluation in
                            deliverableShotRow(evaluation)
                        }
                    }
                }
            }

            DisclosureGroup(isExpanded: $showNotReadyShots) {
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                    if notReadyShotEvaluations.isEmpty {
                        EmptyStateCard(message: "All shots are currently deliverable.")
                    } else {
                        ForEach(notReadyShotEvaluations) { evaluation in
                            HStack(spacing: StopmoUI.Spacing.sm) {
                                ShotThumbnailView(
                                    shot: evaluation.shot,
                                    preferredKind: .first,
                                    baseOutputDir: state.config.watch.outputDir,
                                    width: 44,
                                    height: 28,
                                    cornerRadius: 6,
                                    onOpenLightbox: { previewPath in
                                        previewLightboxItem = ShotLightboxItem(
                                            shot: evaluation.shot,
                                            previewKind: .first,
                                            previewPath: previewPath,
                                            shotRootPath: shotRootPath(for: evaluation.shot)
                                        )
                                    }
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(evaluation.shot.shotName)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(evaluation.readinessReason ?? evaluation.issueSummary)
                                        .metadataTextStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 0)
                                StatusChip(label: evaluation.healthState.rawValue, tone: evaluation.healthState.tone, density: .compact)
                            }
                        }
                    }
                }
                .padding(.top, StopmoUI.Spacing.xs)
            } label: {
                DisclosureRowLabel(title: "Blocked Shots (\(notReadyShotEvaluations.count))", isExpanded: $showNotReadyShots)
            }
            .padding(.top, StopmoUI.Spacing.xs)
        }
    }

    private func deliverableShotRow(_ evaluation: ShotHealthEvaluation) -> some View {
        let shot = evaluation.shot
        let isSelected = selectedShotNames.contains(shot.shotName)

        return SurfaceContainer(level: .card, chrome: .quiet, cornerRadius: 12) {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                HStack(alignment: .top, spacing: DenseShotRowStyle.spacing) {
                    Button {
                        toggleShotSelection(shot.shotName)
                    } label: {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isSelected ? LifecycleHub.deliver.accentColor : AppVisualTokens.textSecondary)
                    }
                    .buttonStyle(.plain)

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
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(ShotHealthModel.updatedDisplayLabel(for: shot))
                            .metadataTextStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 0)

                    StatusChip(label: "Ready", tone: .success, density: .compact)
                }

                ProgressView(value: progressRatio(for: shot))
                    .tint(Color.green.opacity(0.7))

                HStack(spacing: StopmoUI.Spacing.sm) {
                    Button("Deliver") {
                        Task { await runShotDelivery(shot) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(state.isBusy || !watchOutputRootReady)

                    Menu("More") {
                        Button("Open Shot Folder") {
                            state.openPathInFinder(shotRootPath(for: shot))
                        }
                        if let output = shot.outputMovPath, !output.isEmpty {
                            Button("Open Output MOV") {
                                state.openPathInFinder(output)
                            }
                        }
                        if let review = shot.reviewMovPath, !review.isEmpty {
                            Button("Open Review MOV") {
                                state.openPathInFinder(review)
                            }
                        }
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, DenseShotRowStyle.horizontalPadding)
            .padding(.vertical, DenseShotRowStyle.verticalPadding)
            .frame(minHeight: DenseShotRowStyle.minHeight, alignment: .topLeading)
        }
    }

    private var runPlanPane: some View {
        SectionCard("Day Wrap Plan", subtitle: "Put the run plan in the center and keep advanced settings tucked away.", density: .compact, surfaceLevel: .raised, chrome: .standard, showSubtitle: false) {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.md) {
                Text("Input \(resolvedInputLabel)  •  Destination \(resolvedOutputLabel)  •  \(dpxFramerate) fps")
                    .metadataTextStyle(.secondary)

                SummaryFactStrip(
                    facts: [
                        SummaryFact(id: "scope", label: "Scope", value: selectedReadyShotEvaluations.isEmpty ? "Day Wrap Batch" : "Selected Shots", tone: .neutral),
                        SummaryFact(id: "count", label: "Shots", value: "\(selectedReadyShotEvaluations.isEmpty ? readyShotEvaluations.count : selectedReadyShotEvaluations.count)", tone: .neutral),
                        SummaryFact(id: "overwrite", label: "Overwrite", value: dpxOverwrite ? "On" : "Off", tone: dpxOverwrite ? .warning : .neutral),
                    ],
                    minItemWidth: 96,
                    compact: true
                )

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: StopmoUI.Spacing.sm) {
                        Button("Select All Ready") {
                            selectedShotNames = Set(readyShotEvaluations.map { $0.shot.shotName })
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Select None") {
                            selectedShotNames.removeAll()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer(minLength: 0)

                        Button("Run Day Wrap") {
                            consolePinnedOpen = false
                            Task { await runBatchDelivery() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(state.isBusy || !dpxInputDirReady)

                        Button("Deliver Selected") {
                            consolePinnedOpen = false
                            Task { await runSelectedDelivery() }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(state.isBusy || !watchOutputRootReady || selectedReadyShotEvaluations.isEmpty)
                    }

                    VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                        Button("Select All Ready") {
                            selectedShotNames = Set(readyShotEvaluations.map { $0.shot.shotName })
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Select None") {
                            selectedShotNames.removeAll()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Run Day Wrap") {
                            consolePinnedOpen = false
                            Task { await runBatchDelivery() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(state.isBusy || !dpxInputDirReady)

                        Button("Deliver Selected") {
                            consolePinnedOpen = false
                            Task { await runSelectedDelivery() }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(state.isBusy || !watchOutputRootReady || selectedReadyShotEvaluations.isEmpty)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                    Text("Run Overview")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppVisualTokens.textSecondary)
                    KeyValueRow(key: "Input Root", value: resolvedInputLabel, layout: .stacked, valueStyle: .path)
                    KeyValueRow(key: "Destination", value: resolvedOutputLabel, layout: .stacked, valueStyle: .path)
                    KeyValueRow(
                        key: "Selection",
                        value: selectedReadyShotEvaluations.isEmpty ? "All ready shots" : "\(selectedReadyShotEvaluations.count) selected shots",
                        layout: .adaptive(availableWidth: 540)
                    )
                }

                DisclosureGroup(isExpanded: $showAdvancedSettings) {
                    VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                        LabeledPathField(
                            label: "Input Directory",
                            placeholder: "/path/to/dpx_root",
                            text: $dpxInputDir,
                            icon: "folder",
                            browseHelp: "Choose input directory",
                            isDisabled: state.isBusy
                        ) {
                            if let path = chooseDirectoryPath() {
                                dpxInputDir = path
                            }
                        }

                        LabeledPathField(
                            label: "Output Directory (Optional)",
                            placeholder: "/path/to/prores_output",
                            text: $dpxOutputDir,
                            icon: "folder.badge.plus",
                            browseHelp: "Choose output directory",
                            isDisabled: state.isBusy
                        ) {
                            if let path = chooseDirectoryPath() {
                                dpxOutputDir = path
                            }
                        }

                        HStack(spacing: StopmoUI.Spacing.sm) {
                            Text("Framerate")
                                .frame(width: StopmoUI.Width.formLabel, alignment: .leading)
                                .foregroundStyle(.secondary)
                            Stepper(value: $dpxFramerate, in: 1...120) {
                                Text("\(dpxFramerate) fps")
                            }
                            .frame(maxWidth: 240, alignment: .leading)
                        }

                        HStack(spacing: StopmoUI.Spacing.sm) {
                            Text("Overwrite Existing")
                                .frame(width: StopmoUI.Width.formLabel, alignment: .leading)
                                .foregroundStyle(.secondary)
                            Toggle("", isOn: $dpxOverwrite)
                                .labelsHidden()
                        }
                    }
                    .padding(.top, StopmoUI.Spacing.xs)
                } label: {
                    DisclosureRowLabel(title: "Advanced Delivery Settings", isExpanded: $showAdvancedSettings)
                }
            }
        }
        .frame(minHeight: 360, alignment: .topLeading)
    }

    private var inspectorPane: some View {
        WorkspaceInspectorPane(title: "Run Summary", subtitle: "Latest output, current status, and shortcuts") {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.md) {
                SummaryFactStrip(
                    facts: [
                        SummaryFact(id: "status", label: "Status", value: state.deliveryRunState.status.rawValue, tone: toneForStatus(state.deliveryRunState.status)),
                        SummaryFact(id: "progress", label: "Progress", value: "\(state.deliveryRunState.completed)/\(state.deliveryRunState.total)", tone: .neutral),
                        SummaryFact(id: "failed", label: "Failed", value: "\(state.deliveryRunState.failed)", tone: state.deliveryRunState.failed > 0 ? .danger : .neutral),
                    ],
                    minItemWidth: 88,
                    compact: true
                )

                ProgressView(value: min(1.0, max(0.0, state.deliveryRunState.progress)))
                    .controlSize(.small)

                Text(state.deliveryRunState.activeLabel.isEmpty ? "No active delivery" : state.deliveryRunState.activeLabel)
                    .metadataTextStyle(.secondary)

                if let latest = state.deliveryRunState.latestOutputs.first {
                    KeyValueRow(key: "Latest Output", value: latest, layout: .stacked, valueStyle: .path)
                    HStack(spacing: StopmoUI.Spacing.sm) {
                        Button("Open Latest Output") {
                            state.openPathInFinder(latest)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Copy Path") {
                            state.copyTextToPasteboard(latest, label: "output path")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                Divider()

                Button("Run History") {
                    state.selectedDeliverPanel = .runHistory
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Open Review Diagnostics") {
                    state.selectedHub = .triage
                    state.selectedTriagePanel = .diagnostics
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(showConsole ? "Hide Console" : "Show Console") {
                    consolePinnedOpen.toggle()
                    showConsole.toggle()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var consoleContent: some View {
        switch consoleTab {
        case .timeline:
            timelineConsole
        case .diagnostics:
            diagnosticsConsole
        }
    }

    @ViewBuilder
    private var timelineConsole: some View {
        if state.deliveryRunState.events.isEmpty {
            EmptyStateCard(message: "No delivery run events yet.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                    ForEach(state.deliveryRunState.events) { event in
                        HStack(alignment: .top, spacing: StopmoUI.Spacing.sm) {
                            StatusChip(label: event.tone.rawValue.uppercased(), tone: toneForEvent(event.tone), density: .compact)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title)
                                    .font(.caption.weight(.semibold))
                                Text(event.detail)
                                    .metadataTextStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Text(deliveryShortTimeLabel(event.timestampUtc))
                                .metadataTextStyle(.tertiary)
                        }
                    }
                }
            }
            .frame(minHeight: 140, maxHeight: 260)
        }
    }

    private var diagnosticsConsole: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            SummaryFactStrip(
                facts: [
                    SummaryFact(id: "events", label: "Events", value: "\(state.deliveryRunState.events.count)", tone: .neutral),
                    SummaryFact(id: "outputs", label: "Outputs", value: "\(state.deliveryRunState.latestOutputs.count)", tone: .neutral),
                    SummaryFact(id: "history", label: "History Runs", value: "\(state.historySummary?.count ?? 0)", tone: .neutral),
                ],
                minItemWidth: 96,
                compact: true
            )

            if let envelope = state.deliveryOperationEnvelope {
                KeyValueRow(key: "Operation ID", value: envelope.operationId, layout: .stacked, valueStyle: .path)
                KeyValueRow(key: "Status", value: envelope.operation.status, layout: .adaptive(availableWidth: 360))
                KeyValueRow(key: "Kind", value: envelope.operation.kind, layout: .adaptive(availableWidth: 360))
            } else {
                EmptyStateCard(message: "No active delivery envelope.")
            }
        }
    }

    private var allShotEvaluations: [ShotHealthEvaluation] {
        ShotHealthModel
            .evaluate(snapshot: state.shotsSnapshot)
            .sorted { lhs, rhs in
                let left = lhs.shot.lastUpdatedAt ?? ""
                let right = rhs.shot.lastUpdatedAt ?? ""
                if left == right {
                    return lhs.shot.shotName.localizedCaseInsensitiveCompare(rhs.shot.shotName) == .orderedAscending
                }
                return left > right
            }
    }

    private var readyShotEvaluations: [ShotHealthEvaluation] {
        allShotEvaluations.filter(\.isDeliverable)
    }

    private var selectedReadyShotEvaluations: [ShotHealthEvaluation] {
        readyShotEvaluations.filter { selectedShotNames.contains($0.shot.shotName) }
    }

    private var notReadyShotEvaluations: [ShotHealthEvaluation] {
        allShotEvaluations.filter { !$0.isDeliverable }
    }

    private var dpxInputDirReady: Bool {
        !dpxInputDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var watchOutputRootReady: Bool {
        !state.config.watch.outputDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var resolvedInputLabel: String {
        let value = dpxInputDir.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "watch output root" : value
    }

    private var resolvedOutputLabel: String {
        let value = dpxOutputDir.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "default output" : value
    }

    private var consoleSummary: String {
        switch consoleTab {
        case .timeline:
            return "\(state.deliveryRunState.events.count) run events"
        case .diagnostics:
            return "Outputs \(state.deliveryRunState.latestOutputs.count)"
        }
    }

    private func syncSelectionFromSnapshot() {
        selectedShotNames = state.pruneDeliverySelection(selectedShotNames, from: state.shotsSnapshot)
    }

    private func toggleShotSelection(_ shotName: String) {
        if selectedShotNames.contains(shotName) {
            selectedShotNames.remove(shotName)
        } else {
            selectedShotNames.insert(shotName)
        }
        syncSelectionFromSnapshot()
    }

    private func hydrateDefaultsIfNeeded() {
        let resolved = ToolsView.resolvedDpxInputDir(
            currentInputDir: dpxInputDir,
            configOutputDir: state.config.watch.outputDir
        )
        if !resolved.isEmpty, resolved != dpxInputDir {
            dpxInputDir = resolved
        }
    }

    private func runBatchDelivery() async {
        guard let _ = await state.runDayWrapBatchDelivery(
            inputDir: dpxInputDir,
            outputDir: emptyToNil(dpxOutputDir),
            framerate: dpxFramerate,
            overwrite: dpxOverwrite
        ) else {
            showAdvancedSettings = true
            return
        }
        await state.refreshLiveData(silent: true)
        await state.refreshHistory()
    }

    private func runSelectedDelivery() async {
        let shots = selectedReadyShotEvaluations.map(\.shot)
        guard !shots.isEmpty else {
            state.presentWarning(
                title: "No Shots Selected",
                message: "Select one or more ready shots before running delivery.",
                likelyCause: "Selection is empty or no shots are currently deliverable.",
                suggestedAction: "Use Select All Ready or check specific shot rows, then run Deliver Selected."
            )
            return
        }

        guard watchOutputRootReady else {
            state.presentWarning(
                title: "Output Root Missing",
                message: "Cannot resolve shot DPX paths because watch.outputDir is empty.",
                likelyCause: "Project output root is not configured.",
                suggestedAction: "Set watch/output paths in Configure, then retry delivery."
            )
            return
        }

        let shotRoots = shots.map(shotRootPath(for:))
        let outputs = await state.deliverShotsToProres(
            shotInputRoots: shotRoots,
            framerate: dpxFramerate,
            overwrite: dpxOverwrite,
            outputDir: emptyToNil(dpxOutputDir)
        )
        if !outputs.isEmpty {
            await state.refreshLiveData(silent: true)
            await state.refreshHistory()
            syncSelectionFromSnapshot()
        }
    }

    private func runShotDelivery(_ shot: ShotSummaryRow) async {
        guard watchOutputRootReady else {
            state.presentWarning(
                title: "Output Root Missing",
                message: "Cannot resolve shot DPX path because watch.outputDir is empty.",
                likelyCause: "Project output root is not configured.",
                suggestedAction: "Set watch/output paths in Configure, then retry delivery."
            )
            return
        }

        let outputs = await state.deliverShotsToProres(
            shotInputRoots: [shotRootPath(for: shot)],
            framerate: dpxFramerate,
            overwrite: dpxOverwrite,
            outputDir: emptyToNil(dpxOutputDir)
        )
        if !outputs.isEmpty {
            await state.refreshLiveData(silent: true)
            await state.refreshHistory()
        }
    }

    private func chooseDirectoryPath() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    private func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func progressRatio(for shot: ShotSummaryRow) -> Double {
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

    private var deliverySnapshotSignature: [String] {
        (state.shotsSnapshot?.shots ?? []).map { shot in
            [
                shot.shotName,
                shot.state,
                "\(shot.doneFrames)",
                "\(shot.failedFrames)",
                "\(shot.inflightFrames)",
                shot.outputMovPath ?? "",
                shot.reviewMovPath ?? "",
            ].joined(separator: "|")
        }
    }

    private func toneForStatus(_ status: DeliveryRunStatus) -> StatusTone {
        switch status {
        case .idle:
            return .neutral
        case .running:
            return .warning
        case .succeeded:
            return .success
        case .partial:
            return .warning
        case .failed:
            return .danger
        }
    }

    private func toneForEvent(_ tone: DeliveryRunEventTone) -> StatusTone {
        switch tone {
        case .neutral:
            return .neutral
        case .success:
            return .success
        case .warning:
            return .warning
        case .danger:
            return .danger
        }
    }
}
