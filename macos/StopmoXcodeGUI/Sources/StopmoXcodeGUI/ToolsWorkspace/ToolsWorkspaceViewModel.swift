import Foundation

@MainActor
final class ToolsWorkspaceViewModel: ObservableObject {
    @Published var selectedTab: ToolsTab
    @Published var latestEvents: [OperationEventRecord] = []
    @Published var toolTimeline: [ToolTimelineItem] = []
    @Published var isRunningTool: Bool = false
    @Published var activeTool: ToolKind?
    @Published var lastToolStatus: ToolRunStatus = .idle
    @Published var lastToolCompletedLabel: String = "-"
    @Published var eventFilter: ToolEventFilter = .all
    @Published var eventSearch: String = ""

    @Published var transcodeResultPath: String = ""
    @Published var matrixConfidence: String = ""
    @Published var matrixSummary: [String] = []
    @Published var matrixResultPayload: [String: JSONValue] = [:]
    @Published var dpxProgressText: String = ""
    @Published var dpxOutputs: [String] = []

    private var lastAppliedSharedDeliveryOperationId: String?
    private let runner: ToolsRunnerService

    init(defaultTab: ToolsTab, runner: ToolsRunnerService = ToolsRunnerService()) {
        selectedTab = defaultTab
        self.runner = runner
    }

    var filteredEvents: [OperationEventRecord] {
        ToolsTimelineReducer.filteredEvents(
            from: latestEvents,
            filter: eventFilter,
            search: eventSearch
        )
    }

    var latestMatrix: [[Double]]? {
        guard let matrixValues = matrixResultPayload["camera_to_reference_matrix"]?.arrayValue else {
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

    func clearDiagnostics(statusMessage: inout String) {
        latestEvents = []
        toolTimeline = []
        eventSearch = ""
        statusMessage = "Tool events cleared"
    }

    func appendTimeline(title: String, detail: String, tone: StatusTone) {
        ToolsTimelineReducer.appendTimeline(
            items: &toolTimeline,
            title: title,
            detail: detail,
            tone: tone,
            timestampLabel: PathTimestampHelpers.nowTimeLabel(),
            maxCount: 80
        )
    }

    func ingestToolEnvelope(_ envelope: ToolOperationEnvelope) {
        latestEvents = envelope.events.reversed()
        appendTimeline(
            title: "Operation",
            detail: "\(envelope.operation.kind) \(envelope.operation.status) (\(Int((envelope.operation.progress * 100.0).rounded()))%)",
            tone: ToolsTimelineReducer.toneForOperationStatus(envelope.operation.status)
        )
        if let tailEvent = envelope.events.last {
            appendTimeline(
                title: tailEvent.eventType,
                detail: tailEvent.message ?? "",
                tone: ToolsTimelineReducer.toneForEvent(tailEvent)
            )
        }
    }

    func applySharedDeliveryOperationIfAvailable(
        mode: ToolsMode,
        envelope: ToolOperationEnvelope?
    ) {
        guard mode == .deliveryOnly else {
            return
        }
        guard let envelope else {
            return
        }
        guard envelope.operationId != lastAppliedSharedDeliveryOperationId else {
            return
        }
        ingestToolEnvelope(envelope)
        lastAppliedSharedDeliveryOperationId = envelope.operationId
        activeTool = nil
        isRunningTool = false
        lastToolStatus = ToolsTimelineReducer.runStatus(from: envelope.operation.status)
        lastToolCompletedLabel = PathTimestampHelpers.nowTimeLabel()
        let completed = envelope.operation.result?["count"]?.intValue ?? 0
        let total = envelope.operation.result?["total_sequences"]?.intValue ?? completed
        dpxProgressText = "Completed \(completed) / \(total) sequences"
        dpxOutputs = envelope.operation.result?["outputs"]?.arrayValue?.compactMap(\.stringValue) ?? []
    }

    func runTranscodeOne(
        state: AppState,
        inputPath: String,
        outputDir: String?,
        onRecents: @escaping (String, String?) -> Void
    ) async {
        await runTool(kind: .transcodeOne, state: state) { [self] in
            let result = try await self.runner.runTranscodeOne(
                repoRoot: state.repoRoot,
                configPath: state.configPath,
                inputPath: inputPath,
                outputDir: outputDir
            )
            self.ingestToolEnvelope(result)
            self.transcodeResultPath = result.operation.result?["output_path"]?.stringValue ?? ""
            self.appendTimeline(
                title: "Result",
                detail: self.transcodeResultPath.isEmpty ? "Completed without output path payload." : "Output: \(self.transcodeResultPath)",
                tone: .success
            )
            onRecents(inputPath, outputDir)
        }
    }

    func runSuggestMatrix(
        state: AppState,
        inputPath: String,
        cameraMake: String?,
        cameraModel: String?,
        writeJson: String?,
        onRecents: @escaping (String, String?) -> Void
    ) async {
        await runTool(kind: .suggestMatrix, state: state) { [self] in
            let result = try await self.runner.runSuggestMatrix(
                repoRoot: state.repoRoot,
                inputPath: inputPath,
                cameraMake: cameraMake,
                cameraModel: cameraModel,
                writeJson: writeJson
            )
            self.ingestToolEnvelope(result)
            self.matrixResultPayload = result.operation.result ?? [:]
            self.matrixConfidence = self.stringValue(from: self.matrixResultPayload["confidence"])
            self.matrixSummary = self.summarizeMatrixResult(result.operation.result)
            self.appendTimeline(
                title: "Result",
                detail: self.matrixSummary.isEmpty ? "Matrix suggestion completed." : self.matrixSummary.joined(separator: " | "),
                tone: .success
            )
            onRecents(inputPath, writeJson)
        }
    }

    func runDpxToProres(
        state: AppState,
        inputDir: String,
        outputDir: String?,
        framerate: Int,
        overwrite: Bool,
        onRecents: @escaping (String, String?) -> Void
    ) async {
        await runTool(kind: .dpxToProres, state: state) { [self] in
            let result = try await self.runner.runDpxToProres(
                repoRoot: state.repoRoot,
                inputDir: inputDir,
                outputDir: outputDir,
                framerate: framerate,
                overwrite: overwrite
            )
            self.ingestToolEnvelope(result)
            state.publishDeliveryOperation(result)
            let completed = result.operation.result?["count"]?.intValue ?? 0
            let total = result.operation.result?["total_sequences"]?.intValue ?? completed
            self.dpxProgressText = "Completed \(completed) / \(total) sequences"
            self.dpxOutputs = result.operation.result?["outputs"]?.arrayValue?.compactMap(\.stringValue) ?? []
            self.appendTimeline(title: "Result", detail: self.dpxProgressText, tone: .success)
            onRecents(inputDir, outputDir)
        }
    }

    func applySuggestedMatrixToProject(state: AppState) {
        guard let matrix = latestMatrix else { return }
        state.config.pipeline.cameraToReferenceMatrix = matrix
        state.statusMessage = "Applied suggested matrix to project config"
        appendTimeline(title: "Config", detail: "Applied suggested matrix to project", tone: .success)
    }

    func copySuggestedMatrix(state: AppState) {
        guard let matrix = latestMatrix else { return }
        let text = matrix
            .map { row in row.map { String(format: "%.8f", $0) }.joined(separator: ", ") }
            .joined(separator: "\n")
        state.copyTextToPasteboard(text, label: "matrix")
    }

    private func runTool(
        kind: ToolKind,
        state: AppState,
        _ action: @escaping () async throws -> Void
    ) async {
        isRunningTool = true
        activeTool = kind
        lastToolStatus = .running
        state.clearError()
        state.statusMessage = "Running \(kind.rawValue)"
        appendTimeline(title: "Start", detail: "Started \(kind.rawValue)", tone: .warning)
        do {
            try await action()
            lastToolStatus = .succeeded
            state.statusMessage = "\(kind.rawValue) completed"
            appendTimeline(title: "Complete", detail: "\(kind.rawValue) succeeded", tone: .success)
        } catch {
            lastToolStatus = .failed
            state.presentError(title: "\(kind.rawValue) Failed", message: error.localizedDescription)
            appendTimeline(title: "Failure", detail: error.localizedDescription, tone: .danger)
        }
        isRunningTool = false
        activeTool = nil
        lastToolCompletedLabel = PathTimestampHelpers.nowTimeLabel()
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

    private func stringValue(from value: JSONValue?) -> String {
        guard let value else { return "" }
        if let text = value.stringValue {
            return text
        }
        if let number = value.doubleValue {
            return String(format: "%.4f", number)
        }
        if let flag = value.boolValue {
            return flag ? "true" : "false"
        }
        return ""
    }
}
