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

    @State private var lastBatchOutputs: [String] = []
    @State private var lastBatchProgressLabel: String = ""
    @State private var showNotReadyShots: Bool = false
    @State private var showAdvancedDiagnostics: Bool = false
    @State private var activeShotDeliveries: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.lg) {
                deliveryToolbar
                dayWrapBatchCard
                deliverableShotsCard
                notReadyShotsCard
                advancedDiagnosticsCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(StopmoUI.Spacing.sm)
        }
        .onAppear {
            hydrateDefaultsIfNeeded()
            updateFromEnvelope(state.deliveryOperationEnvelope)
            if state.shotsSnapshot == nil {
                Task { await state.refreshLiveData(silent: true) }
            }
        }
        .onChange(of: state.deliveryOperationRevision) { _, _ in
            updateFromEnvelope(state.deliveryOperationEnvelope)
        }
    }

    private var deliveryToolbar: some View {
        ToolbarStrip(title: "Delivery Toolbar") {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                HStack(spacing: StopmoUI.Spacing.xs) {
                    StatusChip(label: "Ready \(readyShotEvaluations.count)", tone: .success, density: .compact)
                    StatusChip(label: "Not Ready \(notReadyShotEvaluations.count)", tone: notReadyShotEvaluations.isEmpty ? .neutral : .warning, density: .compact)
                    StatusChip(label: dpxInputDirReady ? "Input Ready" : "Input Missing", tone: dpxInputDirReady ? .success : .danger, density: .compact)
                    StatusChip(label: "\(dpxFramerate) fps", tone: .neutral, density: .compact)
                    StatusChip(label: dpxOverwrite ? "Overwrite on" : "Overwrite off", tone: dpxOverwrite ? .warning : .neutral, density: .compact)
                    StatusChip(
                        label: state.config.output.writeProresOnShotComplete ? "Auto Shot-Complete: Enabled" : "Auto Shot-Complete: Disabled",
                        tone: state.config.output.writeProresOnShotComplete ? .warning : .neutral,
                        density: .compact
                    )
                    if !lastBatchProgressLabel.isEmpty {
                        StatusChip(label: lastBatchProgressLabel, tone: .success, density: .compact)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: StopmoUI.Spacing.sm) {
                    Spacer(minLength: 0)
                    Button("Edit Policy") {
                        state.selectedHub = .configure
                        state.selectedConfigurePanel = .projectSettings
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button("Run Day Wrap Batch") {
                        Task { await runBatchDelivery() }
                    }
                    .disabled(state.isBusy || !dpxInputDirReady)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
    }

    private var dayWrapBatchCard: some View {
        SectionCard(
            "DPX -> ProRes",
            subtitle: "Run batch DPX to ProRes for shot/day wrap delivery.",
            density: .compact,
            surfaceLevel: .panel,
            chrome: .quiet,
            showSubtitle: false
        ) {
            KeyValueRow(key: "DPX Source Root", value: state.config.watch.outputDir)

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
                icon: "folder",
                browseHelp: "Choose output directory",
                isDisabled: state.isBusy
            ) {
                if let path = chooseDirectoryPath() {
                    dpxOutputDir = path
                }
            }

            HStack(spacing: StopmoUI.Spacing.sm) {
                Stepper("Framerate: \(dpxFramerate)", value: $dpxFramerate, in: 1 ... 120)
                    .frame(maxWidth: 220)
                Toggle("Overwrite", isOn: $dpxOverwrite)
                    .frame(maxWidth: 140)
                Spacer(minLength: 0)
                if let first = lastBatchOutputs.first {
                    Button("Open Latest Output") {
                        state.openPathInFinder(first)
                    }
                    .disabled(first.isEmpty)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if !lastBatchOutputs.isEmpty {
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                    Text("Latest Outputs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(lastBatchOutputs.prefix(8), id: \.self) { output in
                        HStack(spacing: StopmoUI.Spacing.sm) {
                            Text(output)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("Open") {
                                state.openPathInFinder(output)
                            }
                            Button("Copy") {
                                state.copyTextToPasteboard(output, label: "output path")
                            }
                        }
                    }
                }
            }
        }
    }

    private var deliverableShotsCard: some View {
        SectionCard(
            "Deliverable Shots",
            subtitle: "Ready shots with one-click ProRes delivery.",
            density: .compact,
            surfaceLevel: .panel,
            chrome: .quiet,
            showSubtitle: false
        ) {
            if readyShotEvaluations.isEmpty {
                EmptyStateCard(message: "No shots are ready for delivery yet.")
            } else {
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                    ForEach(readyShotEvaluations) { evaluation in
                        shotDeliverCard(evaluation)
                    }
                }
            }
        }
    }

    private func shotDeliverCard(_ evaluation: ShotHealthEvaluation) -> some View {
        let shot = evaluation.shot
        let isRunning = activeShotDeliveries.contains(shot.shotName)

        return VStack(alignment: .leading, spacing: DenseShotRowStyle.spacing) {
            HStack(spacing: StopmoUI.Spacing.sm) {
                Text(shot.shotName)
                    .font(.subheadline.weight(.semibold))
                StatusChip(label: evaluation.healthState.rawValue, tone: evaluation.healthState.tone, density: .compact)
                StatusChip(label: evaluation.completionLabel, tone: .success, density: .compact)
                Text(ShotHealthModel.updatedDisplayLabel(for: shot))
                    .metadataTextStyle(.tertiary)
                    .help(shot.lastUpdatedAt ?? "No update timestamp")
                Spacer(minLength: 0)
            }

            ProgressView(value: progressRatio(for: shot))
                .tint(Color.green.opacity(0.85))

            HStack(spacing: StopmoUI.Spacing.xs) {
                Button(isRunning ? "Delivering..." : "Deliver ProRes") {
                    Task { await runShotDelivery(shot) }
                }
                .disabled(state.isBusy || isRunning)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

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
        .frame(maxWidth: .infinity, minHeight: DenseShotRowStyle.minHeight, alignment: .topLeading)
        .padding(.horizontal, DenseShotRowStyle.horizontalPadding)
        .padding(.vertical, DenseShotRowStyle.verticalPadding)
        .background {
            SurfaceContainer(level: .card, chrome: .quiet, cornerRadius: DenseShotRowStyle.cornerRadius) {
                Color.clear
            }
        }
    }

    private var notReadyShotsCard: some View {
        SectionCard(
            "Not Ready Shots",
            subtitle: "Collapsed list of shots that cannot be delivered yet.",
            density: .compact,
            surfaceLevel: .panel,
            chrome: .quiet,
            showSubtitle: false
        ) {
            DisclosureGroup(
                isExpanded: $showNotReadyShots
            ) {
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                    if notReadyShotEvaluations.isEmpty {
                        EmptyStateCard(message: "All current shots are ready.")
                    } else {
                        ForEach(notReadyShotEvaluations) { evaluation in
                            HStack(spacing: StopmoUI.Spacing.sm) {
                                Text(evaluation.shot.shotName)
                                    .font(.subheadline.weight(.semibold))
                                StatusChip(label: evaluation.healthState.rawValue, tone: evaluation.healthState.tone, density: .compact)
                                StatusChip(label: evaluation.readinessReason ?? "not ready", tone: .warning, density: .compact)
                                Spacer(minLength: 0)
                                Text(ShotHealthModel.updatedDisplayLabel(for: evaluation.shot))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .help(evaluation.shot.lastUpdatedAt ?? "No update timestamp")
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .padding(.top, StopmoUI.Spacing.xs)
            } label: {
                HStack(spacing: StopmoUI.Spacing.sm) {
                    Text("Show Not Ready (\(notReadyShotEvaluations.count))")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    if !notReadyShotEvaluations.isEmpty {
                        StatusChip(label: "Needs attention", tone: .warning, density: .compact)
                    }
                }
            }
        }
    }

    private var advancedDiagnosticsCard: some View {
        SectionCard(
            "Advanced",
            subtitle: "Detailed run timeline and operation events.",
            density: .compact,
            surfaceLevel: .panel,
            chrome: .quiet,
            showSubtitle: false
        ) {
            DisclosureGroup(isExpanded: $showAdvancedDiagnostics) {
                ToolsView(
                    mode: .deliveryOnly,
                    embedded: true,
                    deliveryPresentation: .diagnosticsOnly
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

    private var notReadyShotEvaluations: [ShotHealthEvaluation] {
        allShotEvaluations.filter { !$0.isDeliverable }
    }

    private var dpxInputDirReady: Bool {
        !dpxInputDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        guard let envelope = await state.runDayWrapBatchDelivery(
            inputDir: dpxInputDir,
            outputDir: emptyToNil(dpxOutputDir),
            framerate: dpxFramerate,
            overwrite: dpxOverwrite
        ) else {
            return
        }
        updateFromEnvelope(envelope)
        await state.refreshLiveData(silent: true)
        await state.refreshHistory()
    }

    private func runShotDelivery(_ shot: ShotSummaryRow) async {
        activeShotDeliveries.insert(shot.shotName)
        defer { activeShotDeliveries.remove(shot.shotName) }

        let outputs = await state.deliverShotsToProres(
            shotInputRoots: [shotRootPath(for: shot)],
            framerate: dpxFramerate,
            overwrite: dpxOverwrite,
            outputDir: emptyToNil(dpxOutputDir)
        )
        if !outputs.isEmpty {
            lastBatchOutputs = outputs
        }
        await state.refreshLiveData(silent: true)
        await state.refreshHistory()
    }

    private func updateFromEnvelope(_ envelope: ToolOperationEnvelope?) {
        guard let envelope else { return }
        lastBatchOutputs = envelope.operation.result?["outputs"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let completed = envelope.operation.result?["count"]?.intValue ?? lastBatchOutputs.count
        let total = envelope.operation.result?["total_sequences"]?.intValue ?? max(completed, lastBatchOutputs.count)
        lastBatchProgressLabel = "Completed \(completed)/\(total)"
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
