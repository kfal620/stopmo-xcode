import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// View rendering tools view.
struct ToolsView: View {
    @EnvironmentObject private var state: AppState

    let mode: ToolsMode
    let embedded: Bool
    let deliveryPresentation: DeliveryPresentation

    private let workspaceContext: ToolsWorkspaceContext

    @StateObject private var viewModel: ToolsWorkspaceViewModel

    @AppStorage("tools.transcode.input_path")
    private var transcodeInputPath: String = ""
    @AppStorage("tools.transcode.output_dir")
    private var transcodeOutputDir: String = ""

    @AppStorage("tools.matrix.input_path")
    private var matrixInputPath: String = ""
    @AppStorage("tools.matrix.camera_make")
    private var matrixCameraMake: String = ""
    @AppStorage("tools.matrix.camera_model")
    private var matrixCameraModel: String = ""
    @AppStorage("tools.matrix.write_json_path")
    private var matrixWriteJsonPath: String = ""

    @AppStorage("tools.dpx.input_dir")
    private var dpxInputDir: String = ""
    @AppStorage("tools.dpx.output_dir")
    private var dpxOutputDir: String = ""
    @AppStorage("tools.dpx.framerate")
    private var dpxFramerate: Int = 24
    @AppStorage("tools.dpx.overwrite")
    private var dpxOverwrite: Bool = true

    @AppStorage("tools.recent.transcode.input")
    private var recentTranscodeInputRaw: String = ""
    @AppStorage("tools.recent.transcode.output")
    private var recentTranscodeOutputRaw: String = ""
    @AppStorage("tools.recent.matrix.input")
    private var recentMatrixInputRaw: String = ""
    @AppStorage("tools.recent.matrix.report")
    private var recentMatrixReportRaw: String = ""
    @AppStorage("tools.recent.dpx.input")
    private var recentDpxInputRaw: String = ""
    @AppStorage("tools.recent.dpx.output")
    private var recentDpxOutputRaw: String = ""

    @State private var showTranscodeAdvanced: Bool = false
    @State private var showMatrixAdvanced: Bool = false

    init(
        mode: ToolsMode = .all,
        embedded: Bool = false,
        deliveryPresentation: DeliveryPresentation = .full
    ) {
        self.mode = mode
        self.embedded = embedded
        self.deliveryPresentation = deliveryPresentation

        let context = ToolsWorkspaceMapper.map(mode: mode, deliveryPresentation: deliveryPresentation)
        workspaceContext = context
        _viewModel = StateObject(wrappedValue: ToolsWorkspaceViewModel(defaultTab: context.defaultTab))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.lg) {
                ToolsWorkspaceHeaderView(
                    title: workspaceContext.headerTitle,
                    subtitle: workspaceContext.headerSubtitle,
                    activeTool: viewModel.activeTool,
                    lastToolStatus: viewModel.lastToolStatus,
                    lastToolCompletedLabel: viewModel.lastToolCompletedLabel,
                    embedded: embedded,
                    showEmbeddedChips: workspaceContext.showEmbeddedHeaderChips
                )

                if workspaceContext.tabs.count > 1 {
                    ToolsWorkspaceTabBarView(tabs: workspaceContext.tabs, selectedTab: $viewModel.selectedTab)
                }

                workspaceContent
            }
            .padding(embedded ? StopmoUI.Spacing.sm : StopmoUI.Spacing.lg)
        }
        .onAppear {
            initializeModeDefaultsIfNeeded()
            ensureSelectedTabIsVisible()
            applySharedDeliveryOperationIfAvailable()
        }
        .onChange(of: state.deliveryOperationRevision) { _, _ in
            applySharedDeliveryOperationIfAvailable()
        }
    }

    @ViewBuilder
    private var workspaceContent: some View {
        switch viewModel.selectedTab {
        case .transcode:
            ToolsTranscodePane(
                inputPath: $transcodeInputPath,
                outputDir: $transcodeOutputDir,
                resultPath: $viewModel.transcodeResultPath,
                showAdvanced: $showTranscodeAdvanced,
                isRunningTool: viewModel.isRunningTool,
                preflight: transcodePreflight,
                recentInputs: ToolsRecentsStore.decode(recentTranscodeInputRaw),
                recentOutputs: ToolsRecentsStore.decode(recentTranscodeOutputRaw),
                chooseInputFile: { chooseFilePath(allowedExtensions: ["cr2", "cr3", "raw", "dng", "nef", "arw"]) },
                chooseOutputDirectory: chooseDirectoryPath,
                clearRecentInputs: { recentTranscodeInputRaw = "" },
                clearRecentOutputs: { recentTranscodeOutputRaw = "" },
                pickRecentInput: { transcodeInputPath = $0 },
                pickRecentOutput: { transcodeOutputDir = $0 },
                runAction: { Task { await runTranscodeOne() } },
                openResult: { state.openPathInFinder(viewModel.transcodeResultPath) },
                copyResult: { state.copyTextToPasteboard(viewModel.transcodeResultPath, label: "result path") },
                pathExists: pathExists
            )

        case .matrix:
            ToolsMatrixPane(
                inputPath: $matrixInputPath,
                cameraMake: $matrixCameraMake,
                cameraModel: $matrixCameraModel,
                writeJsonPath: $matrixWriteJsonPath,
                confidence: $viewModel.matrixConfidence,
                summary: $viewModel.matrixSummary,
                showAdvanced: $showMatrixAdvanced,
                isRunningTool: viewModel.isRunningTool,
                preflight: matrixPreflight,
                recentInputs: ToolsRecentsStore.decode(recentMatrixInputRaw),
                recentReports: ToolsRecentsStore.decode(recentMatrixReportRaw),
                latestMatrix: viewModel.latestMatrix,
                chooseInputFile: { chooseFilePath(allowedExtensions: ["cr2", "cr3", "raw", "dng", "nef", "arw"]) },
                chooseReportPath: { chooseSaveFilePath(defaultName: "matrix_report.json", contentType: .json) },
                clearRecentInputs: { recentMatrixInputRaw = "" },
                clearRecentReports: { recentMatrixReportRaw = "" },
                pickRecentInput: { matrixInputPath = $0 },
                pickRecentReport: { matrixWriteJsonPath = $0 },
                runAction: { Task { await runSuggestMatrix() } },
                applyAction: { viewModel.applySuggestedMatrixToProject(state: state) },
                copyAction: { viewModel.copySuggestedMatrix(state: state) },
                openReportAction: { state.openPathInFinder(matrixWriteJsonPath) }
            )

        case .dpxProres:
            ToolsDpxPane(
                inputDir: $dpxInputDir,
                outputDir: $dpxOutputDir,
                framerate: $dpxFramerate,
                overwrite: $dpxOverwrite,
                progressText: $viewModel.dpxProgressText,
                outputs: $viewModel.dpxOutputs,
                isRunningTool: viewModel.isRunningTool,
                preflight: dpxPreflight,
                recentInputs: ToolsRecentsStore.decode(recentDpxInputRaw),
                recentOutputs: ToolsRecentsStore.decode(recentDpxOutputRaw),
                chooseInputDirectory: chooseDirectoryPath,
                chooseOutputDirectory: chooseDirectoryPath,
                clearRecentInputs: { recentDpxInputRaw = "" },
                clearRecentOutputs: { recentDpxOutputRaw = "" },
                pickRecentInput: { dpxInputDir = $0 },
                pickRecentOutput: { dpxOutputDir = $0 },
                runAction: { Task { await runDpxToProres() } },
                openOutputAction: { state.openPathInFinder($0) },
                copyOutputAction: { state.copyTextToPasteboard($0, label: "output path") }
            )

        case .diagnostics:
            ToolsWorkspaceDiagnosticsPane(
                latestEvents: $viewModel.latestEvents,
                toolTimeline: $viewModel.toolTimeline,
                eventFilter: $viewModel.eventFilter,
                eventSearch: $viewModel.eventSearch,
                filteredEvents: viewModel.filteredEvents,
                clearAction: { viewModel.clearDiagnostics(statusMessage: &state.statusMessage) }
            )
        }
    }

    nonisolated static func visibleToolKinds(for mode: ToolsMode) -> [ToolKind] {
        switch mode {
        case .all:
            return [.transcodeOne, .suggestMatrix, .dpxToProres]
        case .utilitiesOnly:
            return [.transcodeOne, .suggestMatrix]
        case .deliveryOnly:
            return [.dpxToProres]
        }
    }

    nonisolated static func resolvedDpxInputDir(currentInputDir: String, configOutputDir: String) -> String {
        let current = currentInputDir.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty {
            return current
        }
        return configOutputDir.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var transcodePreflight: ToolPreflight {
        ToolsPreflightReducer.transcode(
            inputPath: transcodeInputPath,
            outputDir: transcodeOutputDir,
            pathExists: pathExists
        )
    }

    private var matrixPreflight: ToolPreflight {
        ToolsPreflightReducer.matrix(
            inputPath: matrixInputPath,
            writeJsonPath: matrixWriteJsonPath,
            pathExists: pathExists
        )
    }

    private var dpxPreflight: ToolPreflight {
        ToolsPreflightReducer.dpx(
            inputDir: dpxInputDir,
            outputDir: dpxOutputDir,
            pathExists: pathExists,
            dpxCount: countDpxFiles
        )
    }

    private func runTranscodeOne() async {
        let preflight = transcodePreflight
        guard preflight.ok else {
            state.presentWarning(
                title: "Transcode Preflight Blocked",
                message: preflight.blockers.joined(separator: "; ")
            )
            viewModel.appendTimeline(title: "Preflight", detail: "Transcode blocked", tone: .danger)
            return
        }

        let outputDir = emptyToNil(transcodeOutputDir)
        await viewModel.runTranscodeOne(
            state: state,
            inputPath: transcodeInputPath,
            outputDir: outputDir
        ) { input, output in
            recentTranscodeInputRaw = ToolsRecentsStore.append(input, to: recentTranscodeInputRaw)
            if let output {
                recentTranscodeOutputRaw = ToolsRecentsStore.append(output, to: recentTranscodeOutputRaw)
            }
        }
    }

    private func runSuggestMatrix() async {
        let preflight = matrixPreflight
        guard preflight.ok else {
            state.presentWarning(
                title: "Matrix Preflight Blocked",
                message: preflight.blockers.joined(separator: "; ")
            )
            viewModel.appendTimeline(title: "Preflight", detail: "Suggest Matrix blocked", tone: .danger)
            return
        }

        await viewModel.runSuggestMatrix(
            state: state,
            inputPath: matrixInputPath,
            cameraMake: emptyToNil(matrixCameraMake),
            cameraModel: emptyToNil(matrixCameraModel),
            writeJson: emptyToNil(matrixWriteJsonPath)
        ) { input, report in
            recentMatrixInputRaw = ToolsRecentsStore.append(input, to: recentMatrixInputRaw)
            if let report {
                recentMatrixReportRaw = ToolsRecentsStore.append(report, to: recentMatrixReportRaw)
            }
        }
    }

    private func runDpxToProres() async {
        let preflight = dpxPreflight
        guard preflight.ok else {
            state.presentWarning(
                title: "DPX Preflight Blocked",
                message: preflight.blockers.joined(separator: "; ")
            )
            viewModel.appendTimeline(title: "Preflight", detail: "DPX to ProRes blocked", tone: .danger)
            return
        }

        await viewModel.runDpxToProres(
            state: state,
            inputDir: dpxInputDir,
            outputDir: emptyToNil(dpxOutputDir),
            framerate: dpxFramerate,
            overwrite: dpxOverwrite
        ) { input, output in
            recentDpxInputRaw = ToolsRecentsStore.append(input, to: recentDpxInputRaw)
            if let output {
                recentDpxOutputRaw = ToolsRecentsStore.append(output, to: recentDpxOutputRaw)
            }
        }
    }

    private func ensureSelectedTabIsVisible() {
        guard workspaceContext.tabs.contains(viewModel.selectedTab) else {
            viewModel.selectedTab = workspaceContext.defaultTab
            return
        }
    }

    private func initializeModeDefaultsIfNeeded() {
        guard Self.visibleToolKinds(for: mode).contains(.dpxToProres) else {
            return
        }
        let resolved = Self.resolvedDpxInputDir(
            currentInputDir: dpxInputDir,
            configOutputDir: state.config.watch.outputDir
        )
        if resolved != dpxInputDir, !resolved.isEmpty {
            dpxInputDir = resolved
        }
    }

    private func applySharedDeliveryOperationIfAvailable() {
        viewModel.applySharedDeliveryOperationIfAvailable(
            mode: mode,
            envelope: state.deliveryOperationEnvelope
        )
    }

    private func chooseFilePath(allowedExtensions: [String] = []) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose File"
        if !allowedExtensions.isEmpty {
            panel.allowedContentTypes = allowedExtensions.compactMap { ext in
                let clean = ext.hasPrefix(".") ? String(ext.dropFirst()) : ext
                return UTType(filenameExtension: clean)
            }
        }
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    private func chooseDirectoryPath() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose Folder"
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    private func chooseSaveFilePath(defaultName: String, contentType: UTType) -> String? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    private func countDpxFiles(in directoryPath: String) -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: directoryPath) else {
            return 0
        }
        var count = 0
        for case let item as String in enumerator {
            if item.lowercased().hasSuffix(".dpx") {
                count += 1
                if count >= 5000 {
                    break
                }
            }
        }
        return count
    }

    private func pathExists(_ value: String) -> Bool {
        PathTimestampHelpers.pathExists(value)
    }

    private func emptyToNil(_ value: String) -> String? {
        PathTimestampHelpers.trimmedOrNil(value)
    }
}
