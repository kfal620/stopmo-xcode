import AppKit
import SwiftUI

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
    @State private var showBatchConfig: Bool = false
    @State private var showRunEvents: Bool = false
    @State private var showNotReadyShots: Bool = false
    @State private var showAdvancedDiagnostics: Bool = false

    private let runEventsHeight: CGFloat = 220

    var body: some View {
        GeometryReader { proxy in
            let availableHeight = max(420, proxy.size.height - 8)

            deliveryDayWrapWorkspace(availableHeight: availableHeight)
                .onAppear {
                    hydrateDefaultsIfNeeded()
                    syncSelectionFromSnapshot()
                    if state.shotsSnapshot == nil {
                        Task { await state.refreshLiveData(silent: true) }
                    }
                    if dpxInputDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        showBatchConfig = true
                    }
                    if state.deliveryRunState.status == .running {
                        showRunEvents = true
                    }
                }
                .onChange(of: state.shotsSnapshot?.shots.map(\.shotName) ?? []) { _, _ in
                    syncSelectionFromSnapshot()
                }
                .onChange(of: state.deliveryRunState.status) { previous, next in
                    if next == .running {
                        showRunEvents = true
                    } else if previous == .running {
                        showRunEvents = false
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        }
    }

    private func deliveryDayWrapWorkspace(availableHeight: CGFloat) -> some View {
        DeliveryDayWrapWorkspace {
            deliverableShotsPane(availableHeight: availableHeight)
        } secondary: {
            deliveryControlPane(availableHeight: availableHeight)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func deliverableShotsPane(availableHeight: CGFloat) -> some View {
        let shotListMaxHeight = max(240, availableHeight - 220)

        return SectionCard(
            "Deliverable Shots",
            subtitle: "Select completed shots and deliver ProRes in one run.",
            density: .compact,
            surfaceLevel: .panel,
            chrome: .quiet,
            showSubtitle: false
        ) {
            DeliverableShotsPane(
                readyCount: readyShotEvaluations.count,
                selectedCount: selectedReadyShotEvaluations.count,
                notReadyCount: notReadyShotEvaluations.count,
                canRunBulk: canRunSelectedDelivery,
                isBusy: state.isBusy,
                dpxRootReady: watchOutputRootReady,
                selectAllAction: {
                    selectedShotNames = Set(readyShotEvaluations.map { $0.shot.shotName })
                },
                selectNoneAction: {
                    selectedShotNames.removeAll()
                },
                runSelectedAction: {
                    Task { await runSelectedDelivery() }
                }
            ) {
                if readyShotEvaluations.isEmpty {
                    EmptyStateCard(message: "No shots are ready for delivery yet.")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                            ForEach(readyShotEvaluations) { evaluation in
                                deliverableShotRow(evaluation)
                            }
                        }
                        .padding(.horizontal, 2)
                        .padding(.vertical, 2)
                    }
                    .frame(minHeight: 220, maxHeight: shotListMaxHeight)
                }
            }

            notReadyDisclosure
        }
    }

    private func deliverableShotRow(_ evaluation: ShotHealthEvaluation) -> some View {
        let shot = evaluation.shot
        let isSelected = selectedShotNames.contains(shot.shotName)
        let isRunningShot = state.deliveryRunState.status == .running && state.deliveryRunState.activeLabel.localizedCaseInsensitiveContains(shot.shotName)

        return SurfaceContainer(level: .card, chrome: .quiet, cornerRadius: DenseShotRowStyle.cornerRadius) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 6) {
                    Button {
                        toggleShotSelection(shot.shotName)
                    } label: {
                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 14, height: 14)
                            .foregroundStyle(isSelected ? LifecycleHub.deliver.accentColor : AppVisualTokens.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help(isSelected ? "Unselect shot" : "Select shot")

                    Text(shot.shotName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 176, alignment: .leading)
                        .help(shot.shotName)

                    StatusChip(label: evaluation.healthState.rawValue, tone: evaluation.healthState.tone, density: .compact)
                    StatusChip(label: evaluation.completionLabel, tone: .success, density: .compact)
                    Text(ShotHealthModel.updatedDisplayLabel(for: shot))
                        .metadataTextStyle(.tertiary)
                        .help(shot.lastUpdatedAt ?? "No update timestamp")

                    Spacer(minLength: 0)
                }

                ProgressView(value: progressRatio(for: shot))
                    .tint(progressTint(for: evaluation.healthState))

                HStack(spacing: 6) {
                    Button(isRunningShot ? "Delivering..." : "Deliver ProRes") {
                        Task { await runShotDelivery(shot) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(state.isBusy || !watchOutputRootReady || isRunningShot)

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
                    .controlSize(.mini)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
    }

    private var notReadyDisclosure: some View {
        DisclosureGroup(isExpanded: $showNotReadyShots) {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                if notReadyShotEvaluations.isEmpty {
                    EmptyStateCard(message: "All shots are currently deliverable.")
                } else {
                    ForEach(notReadyShotEvaluations) { evaluation in
                        HStack(alignment: .center, spacing: 6) {
                            Text(evaluation.shot.shotName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(width: 176, alignment: .leading)
                                .help(evaluation.shot.shotName)
                            StatusChip(label: evaluation.healthState.rawValue, tone: evaluation.healthState.tone, density: .compact)
                            StatusChip(label: evaluation.readinessReason ?? "not ready", tone: .warning, density: .compact)
                            Spacer(minLength: 0)
                            Text(ShotHealthModel.updatedDisplayLabel(for: evaluation.shot))
                                .metadataTextStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(.top, StopmoUI.Spacing.xs)
        } label: {
            HStack(spacing: StopmoUI.Spacing.sm) {
                Text("Not Ready (\(notReadyShotEvaluations.count))")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                if !notReadyShotEvaluations.isEmpty {
                    StatusChip(label: "Collapsed", tone: .neutral, density: .compact)
                }
            }
        }
        .padding(.top, StopmoUI.Spacing.xs)
    }

    private func deliveryControlPane(availableHeight: CGFloat) -> some View {
        DeliveryControlPane {
            ScrollView {
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.md) {
                    deliveryRunStatusPanel
                    deliveryRunEventsPanel
                    batchConfigDisclosurePanel
                    advancedDiagnosticsPanel
                }
            }
            .frame(maxHeight: availableHeight)
        }
    }

    private var deliveryRunStatusPanel: some View {
        SectionCard(
            "Run Status",
            subtitle: "Live progress and latest output for delivery operations.",
            density: .compact,
            surfaceLevel: .panel,
            chrome: .quiet,
            showSubtitle: false
        ) {
            DeliveryRunStatusPanel(
                runState: state.deliveryRunState,
                openLatestOutput: {
                    if let latest = state.deliveryRunState.latestOutputs.first {
                        state.openPathInFinder(latest)
                    }
                },
                copyLatestOutput: {
                    if let latest = state.deliveryRunState.latestOutputs.first {
                        state.copyTextToPasteboard(latest, label: "output path")
                    }
                }
            )
        }
    }

    private var deliveryRunEventsPanel: some View {
        SectionCard(
            "Run Timeline",
            subtitle: "Verbose event log for the current/last delivery run.",
            density: .compact,
            surfaceLevel: .panel,
            chrome: .quiet,
            showSubtitle: false
        ) {
            DeliveryRunEventsPanel(
                isExpanded: $showRunEvents,
                events: state.deliveryRunState.events,
                maxHeight: runEventsHeight
            )
        }
    }

    private var batchConfigDisclosurePanel: some View {
        SectionCard(
            "DPX -> ProRes Batch",
            subtitle: "Collapsed by default to reduce clutter.",
            density: .compact,
            surfaceLevel: .panel,
            chrome: .quiet,
            showSubtitle: false
        ) {
            BatchConfigDisclosurePanel(
                isExpanded: $showBatchConfig,
                dpxInputDir: $dpxInputDir,
                dpxOutputDir: $dpxOutputDir,
                dpxFramerate: $dpxFramerate,
                dpxOverwrite: $dpxOverwrite,
                inputReady: dpxInputDirReady,
                isBusy: state.isBusy,
                chooseDirectoryPath: chooseDirectoryPath,
                runBatchAction: {
                    Task { await runBatchDelivery() }
                }
            )
        }
    }

    private var advancedDiagnosticsPanel: some View {
        SectionCard(
            "Advanced",
            subtitle: "Delivery diagnostics and fast navigation to full workspaces.",
            density: .compact,
            surfaceLevel: .panel,
            chrome: .quiet,
            showSubtitle: false
        ) {
            DisclosureGroup(isExpanded: $showAdvancedDiagnostics) {
                DeliveryAdvancedDiagnosticsPanel(
                    envelope: state.deliveryOperationEnvelope,
                    runEvents: state.deliveryRunState.events,
                    openRunHistory: {
                        state.selectedDeliverPanel = .runHistory
                    },
                    openTriageDiagnostics: {
                        state.selectedHub = .triage
                        state.selectedTriagePanel = .diagnostics
                    }
                )
                .padding(.top, StopmoUI.Spacing.xs)
            } label: {
                DisclosureToggleLabel(
                    title: "Show Day Wrap Diagnostics",
                    isExpanded: $showAdvancedDiagnostics
                )
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

    private var canRunSelectedDelivery: Bool {
        !state.isBusy && watchOutputRootReady && !selectedReadyShotEvaluations.isEmpty
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
            showBatchConfig = true
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
                suggestedAction: "Set watch/output paths in Configure > Project Settings, then retry delivery."
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
                suggestedAction: "Set watch/output paths in Configure > Project Settings, then retry delivery."
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

    private func shotRootPath(for shot: ShotSummaryRow) -> String {
        let base = state.config.watch.outputDir.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            return shot.shotName
        }
        return (base as NSString).appendingPathComponent(shot.shotName)
    }

    private func progressRatio(for shot: ShotSummaryRow) -> Double {
        guard shot.totalFrames > 0 else {
            return 0
        }
        return min(1.0, max(0.0, Double(shot.doneFrames) / Double(shot.totalFrames)))
    }

    private func progressTint(for state: ShotHealthState) -> Color {
        switch state {
        case .clean:
            return Color.green.opacity(0.7)
        case .issues:
            return Color.red.opacity(0.85)
        case .inflight:
            return Color.orange.opacity(0.8)
        case .queued:
            return Color.white.opacity(0.35)
        }
    }

    private func chooseDirectoryPath() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose Folder"
        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }
        return url.path
    }

    private func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct DeliveryDayWrapWorkspace<Primary: View, Secondary: View>: View {
    @ViewBuilder let primary: Primary
    @ViewBuilder let secondary: Secondary

    init(@ViewBuilder primary: () -> Primary, @ViewBuilder secondary: () -> Secondary) {
        self.primary = primary()
        self.secondary = secondary()
    }

    var body: some View {
        AdaptiveColumns(breakpoint: 1060, spacing: StopmoUI.Spacing.md) {
            primary
        } secondary: {
            secondary
        }
    }
}

private struct DeliverableShotsPane<Rows: View>: View {
    let readyCount: Int
    let selectedCount: Int
    let notReadyCount: Int
    let canRunBulk: Bool
    let isBusy: Bool
    let dpxRootReady: Bool
    let selectAllAction: () -> Void
    let selectNoneAction: () -> Void
    let runSelectedAction: () -> Void
    @ViewBuilder let rows: Rows

    init(
        readyCount: Int,
        selectedCount: Int,
        notReadyCount: Int,
        canRunBulk: Bool,
        isBusy: Bool,
        dpxRootReady: Bool,
        selectAllAction: @escaping () -> Void,
        selectNoneAction: @escaping () -> Void,
        runSelectedAction: @escaping () -> Void,
        @ViewBuilder rows: () -> Rows
    ) {
        self.readyCount = readyCount
        self.selectedCount = selectedCount
        self.notReadyCount = notReadyCount
        self.canRunBulk = canRunBulk
        self.isBusy = isBusy
        self.dpxRootReady = dpxRootReady
        self.selectAllAction = selectAllAction
        self.selectNoneAction = selectNoneAction
        self.runSelectedAction = runSelectedAction
        self.rows = rows()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
            HStack(spacing: StopmoUI.Spacing.xs) {
                StatusChip(label: "Ready \(readyCount)", tone: .success, density: .compact)
                StatusChip(label: "Selected \(selectedCount)", tone: selectedCount > 0 ? .warning : .neutral, density: .compact)
                StatusChip(label: "Not Ready \(notReadyCount)", tone: notReadyCount > 0 ? .warning : .neutral, density: .compact)
                StatusChip(label: dpxRootReady ? "Root Ready" : "Root Missing", tone: dpxRootReady ? .success : .danger, density: .compact)
                Spacer(minLength: 0)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    Button("Select All Ready", action: selectAllAction)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isBusy || readyCount == 0)
                    Button("Select None", action: selectNoneAction)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isBusy || selectedCount == 0)
                    Spacer(minLength: 0)
                    Button("Deliver Selected", action: runSelectedAction)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!canRunBulk)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Button("Select All Ready", action: selectAllAction)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(isBusy || readyCount == 0)
                        Button("Select None", action: selectNoneAction)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(isBusy || selectedCount == 0)
                    }
                    Button("Deliver Selected", action: runSelectedAction)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!canRunBulk)
                }
            }

            rows
        }
    }
}

private struct DeliveryControlPane<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            content
        }
    }
}

private struct DeliveryRunStatusPanel: View {
    let runState: DeliveryRunState
    let openLatestOutput: () -> Void
    let copyLatestOutput: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            HStack(spacing: StopmoUI.Spacing.sm) {
                StatusChip(label: runState.status.rawValue, tone: toneForStatus(runState.status), density: .compact)
                StatusChip(label: runState.kind.rawValue, tone: .neutral, density: .compact)
                StatusChip(label: "\(runState.completed)/\(runState.total)", tone: .neutral, density: .compact)
                if runState.failed > 0 {
                    StatusChip(label: "Failed \(runState.failed)", tone: .danger, density: .compact)
                }
                Spacer(minLength: 0)
            }

            progressHeaderBar

            Text(runState.activeLabel.isEmpty ? "No active delivery" : runState.activeLabel)
                .metadataTextStyle(.secondary)

            HStack(spacing: StopmoUI.Spacing.xs) {
                if let output = runState.latestOutputs.first {
                    Text(output)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(output)
                    Button("Open", action: openLatestOutput)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Copy", action: copyLatestOutput)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else {
                    Text("No output generated yet.")
                        .metadataTextStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var progressHeaderBar: some View {
        if runState.status == .running && runState.total == 0 {
            ProgressView()
                .controlSize(.small)
        } else {
            ProgressView(value: min(1.0, max(0.0, runState.progress)))
                .controlSize(.small)
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
}

private struct DeliveryRunEventsPanel: View {
    @Binding var isExpanded: Bool
    let events: [DeliveryRunEvent]
    let maxHeight: CGFloat

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if events.isEmpty {
                EmptyStateCard(message: "No delivery events yet.")
                    .padding(.top, StopmoUI.Spacing.xs)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                        ForEach(events) { event in
                            HStack(alignment: .top, spacing: StopmoUI.Spacing.sm) {
                                StatusChip(label: event.tone.rawValue, tone: toneForEvent(event), density: .compact)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title)
                                        .font(.caption.weight(.semibold))
                                    Text(event.detail)
                                        .metadataTextStyle(.tertiary)
                                    if let shotName = event.shotName, !shotName.isEmpty {
                                        Text(shotName)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(AppVisualTokens.textSecondary)
                                    }
                                }
                                Spacer(minLength: 0)
                                Text(eventTimeLabel(event.timestampUtc))
                                    .metadataTextStyle(.tertiary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.top, StopmoUI.Spacing.xs)
                }
                .frame(maxHeight: maxHeight)
            }
        } label: {
            HStack(spacing: StopmoUI.Spacing.sm) {
                Text("Show Events (\(events.count))")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                if !events.isEmpty {
                    StatusChip(label: "Verbose", tone: .neutral, density: .compact)
                }
            }
        }
    }

    private func toneForEvent(_ event: DeliveryRunEvent) -> StatusTone {
        switch event.tone {
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

    private func eventTimeLabel(_ timestampUtc: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        let date = formatter.date(from: timestampUtc) ?? fallback.date(from: timestampUtc)
        guard let date else { return timestampUtc }

        let label = DateFormatter()
        label.dateFormat = "HH:mm:ss"
        return label.string(from: date)
    }
}

private struct BatchConfigDisclosurePanel: View {
    @Binding var isExpanded: Bool
    @Binding var dpxInputDir: String
    @Binding var dpxOutputDir: String
    @Binding var dpxFramerate: Int
    @Binding var dpxOverwrite: Bool
    let inputReady: Bool
    let isBusy: Bool
    let chooseDirectoryPath: () -> String?
    let runBatchAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: StopmoUI.Spacing.xs) {
                    StatusChip(label: inputReady ? "Input Ready" : "Input Missing", tone: inputReady ? .success : .danger, density: .compact)
                    StatusChip(label: dpxOutputDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Output: default" : "Output: override", tone: .neutral, density: .compact)
                    StatusChip(label: "\(dpxFramerate) fps", tone: .neutral, density: .compact)
                    StatusChip(label: dpxOverwrite ? "Overwrite on" : "Overwrite off", tone: dpxOverwrite ? .warning : .neutral, density: .compact)
                    Spacer(minLength: 0)
                    Button(isExpanded ? "Collapse" : "Expand") {
                        isExpanded.toggle()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: StopmoUI.Spacing.xs) {
                        StatusChip(label: inputReady ? "Input Ready" : "Input Missing", tone: inputReady ? .success : .danger, density: .compact)
                        StatusChip(label: dpxOutputDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Output: default" : "Output: override", tone: .neutral, density: .compact)
                        StatusChip(label: "\(dpxFramerate) fps", tone: .neutral, density: .compact)
                        StatusChip(label: dpxOverwrite ? "Overwrite on" : "Overwrite off", tone: dpxOverwrite ? .warning : .neutral, density: .compact)
                    }
                    Button(isExpanded ? "Collapse" : "Expand") {
                        isExpanded.toggle()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                    LabeledPathField(
                        label: "Input Directory",
                        placeholder: "/path/to/dpx_root",
                        text: $dpxInputDir,
                        icon: "folder",
                        browseHelp: "Choose input directory",
                        isDisabled: isBusy
                    ) {
                        if let path = chooseDirectoryPath() {
                            dpxInputDir = path
                        }
                    }

                    LabeledPathField(
                        label: "Output Directory (Optional)",
                        placeholder: "/path/to/prores_output",
                        text: $dpxOutputDir,
                        icon: "folder",
                        browseHelp: "Choose output directory",
                        isDisabled: isBusy
                    ) {
                        if let path = chooseDirectoryPath() {
                            dpxOutputDir = path
                        }
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: StopmoUI.Spacing.sm) {
                            Stepper("Framerate: \(dpxFramerate)", value: $dpxFramerate, in: 1 ... 120)
                                .frame(maxWidth: 220)
                            Toggle("Overwrite", isOn: $dpxOverwrite)
                                .frame(maxWidth: 140)
                            Spacer(minLength: 0)
                            Button("Run Day Wrap Batch", action: runBatchAction)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(isBusy || !inputReady)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Stepper("Framerate: \(dpxFramerate)", value: $dpxFramerate, in: 1 ... 120)
                            Toggle("Overwrite", isOn: $dpxOverwrite)
                            Button("Run Day Wrap Batch", action: runBatchAction)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(isBusy || !inputReady)
                        }
                    }
                }
                .padding(.top, StopmoUI.Spacing.xs)
            } label: {
                DisclosureToggleLabel(title: "Batch Paths & Settings", isExpanded: $isExpanded)
            }
        }
    }
}

private struct DeliveryAdvancedDiagnosticsPanel: View {
    let envelope: ToolOperationEnvelope?
    let runEvents: [DeliveryRunEvent]
    let openRunHistory: () -> Void
    let openTriageDiagnostics: () -> Void

    private let maxRows = 10

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            HStack(spacing: StopmoUI.Spacing.xs) {
                StatusChip(label: "Run Events \(runEvents.count)", tone: .neutral, density: .compact)
                StatusChip(label: "Envelope Events \(envelope?.events.count ?? 0)", tone: .neutral, density: .compact)
                Spacer(minLength: 0)
            }

            if recentRows.isEmpty {
                EmptyStateCard(message: "No diagnostics events available yet.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(recentRows.enumerated()), id: \.offset) { _, row in
                            HStack(alignment: .top, spacing: StopmoUI.Spacing.sm) {
                                StatusChip(label: row.kind, tone: row.tone, density: .compact)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title)
                                        .font(.caption.weight(.semibold))
                                    Text(row.detail)
                                        .metadataTextStyle(.tertiary)
                                }
                                Spacer(minLength: 0)
                                Text(row.time)
                                    .metadataTextStyle(.tertiary)
                            }
                        }
                    }
                }
                .frame(maxHeight: 180)
            }

            HStack(spacing: StopmoUI.Spacing.xs) {
                Button("Open Run History", action: openRunHistory)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Open Triage Diagnostics", action: openTriageDiagnostics)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private var recentRows: [(kind: String, tone: StatusTone, title: String, detail: String, time: String)] {
        let runRows = runEvents.prefix(maxRows).map { event in
            (
                "run",
                toneForRunEvent(event.tone),
                event.title,
                event.detail,
                shortTime(event.timestampUtc)
            )
        }

        let envelopeRows: [(kind: String, tone: StatusTone, title: String, detail: String, time: String)] =
            (envelope?.events ?? []).prefix(maxRows).map { event in
                let title = event.eventType.isEmpty ? "event" : event.eventType
                let detail = event.message?.isEmpty == false ? (event.message ?? "") : "Operation \(event.operationId)"
                return ("op", toneForEnvelopeEvent(title), title, detail, shortTime(event.timestampUtc))
            }

        return Array((runRows + envelopeRows).prefix(maxRows))
    }

    private func toneForRunEvent(_ tone: DeliveryRunEventTone) -> StatusTone {
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

    private func toneForEnvelopeEvent(_ eventType: String) -> StatusTone {
        let lower = eventType.lowercased()
        if lower.contains("fail") || lower.contains("error") {
            return .danger
        }
        if lower.contains("done") || lower.contains("complete") || lower.contains("success") {
            return .success
        }
        if lower.contains("start") || lower.contains("progress") {
            return .warning
        }
        return .neutral
    }

    private func shortTime(_ timestampUtc: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        let date = formatter.date(from: timestampUtc) ?? fallback.date(from: timestampUtc)
        guard let date else { return timestampUtc }

        let output = DateFormatter()
        output.dateFormat = "HH:mm:ss"
        return output.string(from: date)
    }
}
