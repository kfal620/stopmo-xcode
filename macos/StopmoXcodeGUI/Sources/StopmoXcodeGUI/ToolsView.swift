import SwiftUI

struct ToolsView: View {
    @EnvironmentObject private var state: AppState

    @State private var transcodeInputPath: String = ""
    @State private var transcodeOutputDir: String = ""
    @State private var transcodeResultPath: String = ""

    @State private var matrixInputPath: String = ""
    @State private var matrixCameraMake: String = ""
    @State private var matrixCameraModel: String = ""
    @State private var matrixWriteJsonPath: String = ""
    @State private var matrixConfidence: String = ""
    @State private var matrixSummary: [String] = []

    @State private var dpxInputDir: String = ""
    @State private var dpxOutputDir: String = ""
    @State private var dpxFramerate: Int = 24
    @State private var dpxOverwrite: Bool = true
    @State private var dpxProgressText: String = ""
    @State private var dpxOutputs: [String] = []

    @State private var latestEvents: [OperationEventRecord] = []
    @State private var isRunningTool: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.lg) {
                ScreenHeader(
                    title: "Tools",
                    subtitle: "Run one-off operations and inspect operation activity."
                ) {
                    if isRunningTool {
                        StatusChip(label: "Running", tone: .warning)
                    }
                }

                transcodeSection
                matrixSection
                dpxSection
                eventsSection
            }
            .padding(StopmoUI.Spacing.lg)
        }
    }

    private var transcodeSection: some View {
        SectionCard("Transcode One", subtitle: "Single-frame transcode with optional output override.") {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                toolTextField("Input RAW frame path", text: $transcodeInputPath)
                toolTextField("Output directory override (optional)", text: $transcodeOutputDir)
                HStack(spacing: StopmoUI.Spacing.sm) {
                    Button("Run Transcode One") {
                        Task { await runTranscodeOne() }
                    }
                    .disabled(isRunningTool)
                    if !transcodeResultPath.isEmpty {
                        StatusChip(label: "Output Ready", tone: .success)
                    }
                }
                if !transcodeResultPath.isEmpty {
                    Text(transcodeResultPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var matrixSection: some View {
        SectionCard("Suggest Matrix", subtitle: "Estimate camera-to-reference matrix and apply to project.") {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                toolTextField("Input RAW frame path", text: $matrixInputPath)
                HStack(spacing: StopmoUI.Spacing.sm) {
                    toolTextField("Camera make override (optional)", text: $matrixCameraMake)
                    toolTextField("Camera model override (optional)", text: $matrixCameraModel)
                }
                toolTextField("Write JSON report path (optional)", text: $matrixWriteJsonPath)
                HStack(spacing: StopmoUI.Spacing.sm) {
                    Button("Run Suggest Matrix") {
                        Task { await runSuggestMatrix() }
                    }
                    .disabled(isRunningTool)

                    Button("Apply Matrix To Project") {
                        applySuggestedMatrixToProject()
                    }
                    .disabled(isRunningTool || matrixSummary.isEmpty)

                    if !matrixConfidence.isEmpty {
                        StatusChip(label: "Confidence \(matrixConfidence)", tone: .neutral)
                    }
                }
                if !matrixSummary.isEmpty {
                    VStack(alignment: .leading, spacing: StopmoUI.Spacing.xxs) {
                        ForEach(matrixSummary.indices, id: \.self) { idx in
                            Text(matrixSummary[idx])
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var dpxSection: some View {
        SectionCard("DPX To ProRes", subtitle: "Batch transcode DPX sequences into ProRes outputs.") {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                toolTextField("Input directory", text: $dpxInputDir)
                toolTextField("Output directory (optional)", text: $dpxOutputDir)
                HStack(spacing: StopmoUI.Spacing.md) {
                    Stepper("Framerate: \(dpxFramerate)", value: $dpxFramerate, in: 1 ... 120)
                    Toggle("Overwrite", isOn: $dpxOverwrite)
                }
                HStack(spacing: StopmoUI.Spacing.sm) {
                    Button("Run DPX To ProRes") {
                        Task { await runDpxToProres() }
                    }
                    .disabled(isRunningTool)
                    if !dpxProgressText.isEmpty {
                        StatusChip(label: dpxProgressText, tone: .neutral)
                    }
                }
                if !dpxOutputs.isEmpty {
                    VStack(alignment: .leading, spacing: StopmoUI.Spacing.xxs) {
                        Text("Outputs")
                            .font(.caption.bold())
                        ForEach(dpxOutputs, id: \.self) { output in
                            Text(output)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private var eventsSection: some View {
        SectionCard("Tool Activity", subtitle: "Latest operation events from backend event history.") {
            if latestEvents.isEmpty {
                EmptyStateCard(message: "No tool events yet.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: StopmoUI.Spacing.xxs) {
                        ForEach(latestEvents) { ev in
                            Text("[\(ev.timestampUtc)] \(ev.eventType) \(ev.message ?? "")")
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: 240)
            }
        }
    }

    private func toolTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 760, alignment: .leading)
    }

    private func runTranscodeOne() async {
        let repoRoot = state.repoRoot
        let configPath = state.configPath
        let inputPath = transcodeInputPath
        let outputDir = emptyToNil(transcodeOutputDir)
        await runTool {
            let result = try await Task.detached(priority: .userInitiated) {
                try BridgeClient().transcodeOne(
                    repoRoot: repoRoot,
                    configPath: configPath,
                    inputPath: inputPath,
                    outputDir: outputDir
                )
            }.value
            latestEvents = result.events.reversed()
            if let outputPath = result.operation.result?["output_path"]?.stringValue {
                transcodeResultPath = outputPath
            } else {
                transcodeResultPath = ""
            }
        }
    }

    private func runSuggestMatrix() async {
        let repoRoot = state.repoRoot
        let inputPath = matrixInputPath
        let cameraMake = emptyToNil(matrixCameraMake)
        let cameraModel = emptyToNil(matrixCameraModel)
        let writeJson = emptyToNil(matrixWriteJsonPath)
        await runTool {
            let result = try await Task.detached(priority: .userInitiated) {
                try BridgeClient().suggestMatrix(
                    repoRoot: repoRoot,
                    inputPath: inputPath,
                    cameraMake: cameraMake,
                    cameraModel: cameraModel,
                    writeJson: writeJson
                )
            }.value
            latestEvents = result.events.reversed()
            matrixConfidence = result.operation.result?["confidence"]?.stringValue ?? ""
            matrixSummary = summarizeMatrixResult(result.operation.result)
        }
    }

    private func runDpxToProres() async {
        let repoRoot = state.repoRoot
        let inputDir = dpxInputDir
        let outputDir = emptyToNil(dpxOutputDir)
        let framerate = dpxFramerate
        let overwrite = dpxOverwrite
        await runTool {
            let result = try await Task.detached(priority: .userInitiated) {
                try BridgeClient().dpxToProres(
                    repoRoot: repoRoot,
                    inputDir: inputDir,
                    outputDir: outputDir,
                    framerate: framerate,
                    overwrite: overwrite
                )
            }.value
            latestEvents = result.events.reversed()
            let completed = result.operation.result?["count"]?.intValue ?? 0
            let total = result.operation.result?["total_sequences"]?.intValue ?? completed
            dpxProgressText = "Completed \(completed) / \(total) sequences"
            dpxOutputs = result.operation.result?["outputs"]?.arrayValue?.compactMap { $0.stringValue } ?? []
        }
    }

    private func runTool(_ action: @escaping () async throws -> Void) async {
        isRunningTool = true
        state.clearError()
        state.statusMessage = "Running tool operation"
        do {
            try await action()
            state.statusMessage = "Tool operation completed"
        } catch {
            state.presentError(title: "Tool Operation Failed", message: error.localizedDescription)
        }
        isRunningTool = false
    }

    private func summarizeMatrixResult(_ result: [String: JSONValue]?) -> [String] {
        guard let result else { return [] }
        var rows: [String] = []
        if let make = result["camera_make"]?.stringValue, let model = result["camera_model"]?.stringValue {
            rows.append("Camera: \(make) \(model)")
        }
        if let source = result["source"]?.stringValue {
            rows.append("Source: \(source)")
        }
        if let warnings = result["warnings"]?.arrayValue?.compactMap(\.stringValue), !warnings.isEmpty {
            rows.append("Warnings: \(warnings.joined(separator: "; "))")
        }
        if let assumptions = result["assumptions"]?.arrayValue?.compactMap(\.stringValue), !assumptions.isEmpty {
            rows.append("Assumptions: \(assumptions.joined(separator: "; "))")
        }
        return rows
    }

    private func applySuggestedMatrixToProject() {
        guard let matrix = latestMatrix else { return }
        state.config.pipeline.cameraToReferenceMatrix = matrix
        state.statusMessage = "Applied suggested matrix to project config"
    }

    private var latestMatrix: [[Double]]? {
        guard let matrixValues = latestResult?["camera_to_reference_matrix"]?.arrayValue else {
            return nil
        }
        var out: [[Double]] = []
        for rowValue in matrixValues {
            guard let row = rowValue.arrayValue else { return nil }
            out.append(row.compactMap(\.doubleValue))
        }
        guard out.count == 3, out.allSatisfy({ $0.count == 3 }) else {
            return nil
        }
        return out
    }

    private var latestResult: [String: JSONValue]? {
        if let first = latestEvents.first,
           first.eventType == "operation_succeeded",
           let payload = first.payload {
            return payload
        }
        return nil
    }

    private func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
