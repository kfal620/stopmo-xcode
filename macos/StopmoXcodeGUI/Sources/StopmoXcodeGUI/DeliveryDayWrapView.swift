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

    var body: some View {
        GeometryReader { proxy in
            let availableHeight = max(
                DeliveryLayoutMetrics.minViewportHeight,
                proxy.size.height - DeliveryLayoutMetrics.viewportTopBottomInsetCompensation
            )

            DeliveryDayWrapWorkspace {
                DeliveryShotListPane(
                    readyShotEvaluations: readyShotEvaluations,
                    notReadyShotEvaluations: notReadyShotEvaluations,
                    selectedShotNames: $selectedShotNames,
                    showNotReadyShots: $showNotReadyShots,
                    isBusy: state.isBusy,
                    dpxRootReady: watchOutputRootReady,
                    isRunningDelivery: state.deliveryRunState.status == .running,
                    activeRunLabel: state.deliveryRunState.activeLabel,
                    availableHeight: availableHeight,
                    onSelectAllReady: {
                        selectedShotNames = Set(readyShotEvaluations.map { $0.shot.shotName })
                    },
                    onSelectNone: {
                        selectedShotNames.removeAll()
                    },
                    onRunSelected: {
                        Task { await runSelectedDelivery() }
                    },
                    onToggleSelection: { shotName in
                        toggleShotSelection(shotName)
                    },
                    onRunShot: { shot in
                        Task { await runShotDelivery(shot) }
                    },
                    onOpenShotFolder: { shot in
                        state.openPathInFinder(shotRootPath(for: shot))
                    },
                    onOpenPath: { path in
                        state.openPathInFinder(path)
                    }
                )
            } secondary: {
                DeliveryControlPaneView(
                    availableHeight: availableHeight,
                    runState: state.deliveryRunState,
                    envelope: state.deliveryOperationEnvelope,
                    showRunEvents: $showRunEvents,
                    showBatchConfig: $showBatchConfig,
                    showAdvancedDiagnostics: $showAdvancedDiagnostics,
                    dpxInputDir: $dpxInputDir,
                    dpxOutputDir: $dpxOutputDir,
                    dpxFramerate: $dpxFramerate,
                    dpxOverwrite: $dpxOverwrite,
                    inputReady: dpxInputDirReady,
                    isBusy: state.isBusy,
                    onChooseDirectoryPath: chooseDirectoryPath,
                    onRunBatch: {
                        Task { await runBatchDelivery() }
                    },
                    onOpenLatestOutput: {
                        if let latest = state.deliveryRunState.latestOutputs.first {
                            state.openPathInFinder(latest)
                        }
                    },
                    onCopyLatestOutput: {
                        if let latest = state.deliveryRunState.latestOutputs.first {
                            state.copyTextToPasteboard(latest, label: "output path")
                        }
                    },
                    onOpenRunHistory: {
                        state.selectedDeliverPanel = .runHistory
                    },
                    onOpenTriageDiagnostics: {
                        state.selectedHub = .triage
                        state.selectedTriagePanel = .diagnostics
                    }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            .clipped()
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
