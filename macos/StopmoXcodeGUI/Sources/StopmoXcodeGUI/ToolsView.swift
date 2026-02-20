import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum ToolKind: String, CaseIterable {
    case transcodeOne = "Transcode One"
    case suggestMatrix = "Suggest Matrix"
    case dpxToProres = "DPX To ProRes"
}

private enum ToolRunStatus {
    case idle
    case running
    case succeeded
    case failed

    var label: String {
        switch self {
        case .idle:
            return "Idle"
        case .running:
            return "Running"
        case .succeeded:
            return "Succeeded"
        case .failed:
            return "Failed"
        }
    }

    var tone: StatusTone {
        switch self {
        case .idle:
            return .neutral
        case .running:
            return .warning
        case .succeeded:
            return .success
        case .failed:
            return .danger
        }
    }
}

private enum ToolEventFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case milestones = "Milestones"
    case errors = "Errors"

    var id: String { rawValue }
}

private struct ToolPreflight {
    let blockers: [String]
    let warnings: [String]

    var ok: Bool { blockers.isEmpty }
}

private struct ToolTimelineItem: Identifiable {
    let id = UUID()
    let timestampLabel: String
    let title: String
    let detail: String
    let tone: StatusTone
}

struct ToolsView: View {
    @EnvironmentObject private var state: AppState

    @AppStorage("tools.transcode.input_path")
    private var transcodeInputPath: String = ""
    @AppStorage("tools.transcode.output_dir")
    private var transcodeOutputDir: String = ""
    @State private var transcodeResultPath: String = ""

    @AppStorage("tools.matrix.input_path")
    private var matrixInputPath: String = ""
    @AppStorage("tools.matrix.camera_make")
    private var matrixCameraMake: String = ""
    @AppStorage("tools.matrix.camera_model")
    private var matrixCameraModel: String = ""
    @AppStorage("tools.matrix.write_json_path")
    private var matrixWriteJsonPath: String = ""
    @State private var matrixConfidence: String = ""
    @State private var matrixSummary: [String] = []
    @State private var matrixResultPayload: [String: JSONValue] = [:]

    @AppStorage("tools.dpx.input_dir")
    private var dpxInputDir: String = ""
    @AppStorage("tools.dpx.output_dir")
    private var dpxOutputDir: String = ""
    @AppStorage("tools.dpx.framerate")
    private var dpxFramerate: Int = 24
    @AppStorage("tools.dpx.overwrite")
    private var dpxOverwrite: Bool = true
    @State private var dpxProgressText: String = ""
    @State private var dpxOutputs: [String] = []

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

    @State private var latestEvents: [OperationEventRecord] = []
    @State private var toolTimeline: [ToolTimelineItem] = []
    @State private var isRunningTool: Bool = false
    @State private var activeTool: ToolKind?
    @State private var lastToolStatus: ToolRunStatus = .idle
    @State private var lastToolCompletedLabel: String = "-"
    @State private var eventFilter: ToolEventFilter = .all
    @State private var eventSearch: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.lg) {
                ScreenHeader(
                    title: "Tools",
                    subtitle: "Guided one-off workflows with preflight checks, staged progress, and actionable results."
                ) {
                    HStack(spacing: StopmoUI.Spacing.sm) {
                        if let activeTool {
                            StatusChip(label: activeTool.rawValue, tone: .warning)
                        }
                        StatusChip(label: lastToolStatus.label, tone: lastToolStatus.tone)
                        StatusChip(label: "Last Run \(lastToolCompletedLabel)", tone: .neutral)
                    }
                }

                transcodeSection
                matrixSection
                dpxSection
                timelineSection
                eventsSection
            }
            .padding(StopmoUI.Spacing.lg)
        }
    }

    private var transcodeSection: some View {
        let preflight = transcodePreflight
        return SectionCard("Transcode One", subtitle: "Single-frame transcode with preflight checks and output actions.") {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                preflightView(preflight, context: .transcodeOne)

                LabeledPathField(
                    label: "Input RAW Frame",
                    placeholder: "/path/to/frame.cr2",
                    text: $transcodeInputPath,
                    icon: "folder",
                    browseHelp: "Choose RAW input file",
                    isDisabled: isRunningTool
                ) {
                    if let path = chooseFilePath(allowedExtensions: ["cr2", "cr3", "raw", "dng", "nef", "arw"]) {
                        transcodeInputPath = path
                    }
                }

                recentMenuRow(
                    title: "Recent Inputs",
                    values: decodeRecentValues(recentTranscodeInputRaw),
                    onPick: { transcodeInputPath = $0 },
                    onClear: { recentTranscodeInputRaw = "" }
                )

                LabeledPathField(
                    label: "Output Override (Optional)",
                    placeholder: "/path/to/output",
                    text: $transcodeOutputDir,
                    icon: "folder",
                    browseHelp: "Choose output directory override",
                    isDisabled: isRunningTool
                ) {
                    if let path = chooseDirectoryPath() {
                        transcodeOutputDir = path
                    }
                }

                recentMenuRow(
                    title: "Recent Outputs",
                    values: decodeRecentValues(recentTranscodeOutputRaw),
                    onPick: { transcodeOutputDir = $0 },
                    onClear: { recentTranscodeOutputRaw = "" }
                )

                HStack(spacing: StopmoUI.Spacing.sm) {
                    Button("Run Transcode One") {
                        Task { await runTranscodeOne() }
                    }
                    .disabled(isRunningTool || !preflight.ok)

                    Button("Open Result") {
                        state.openPathInFinder(transcodeResultPath)
                    }
                    .disabled(transcodeResultPath.isEmpty)

                    Button("Copy Result Path") {
                        state.copyTextToPasteboard(transcodeResultPath, label: "result path")
                    }
                    .disabled(transcodeResultPath.isEmpty)

                    if !transcodeResultPath.isEmpty {
                        StatusChip(label: "Output Ready", tone: .success)
                    }
                }

                if !transcodeResultPath.isEmpty {
                    KeyValueRow(key: "Result", value: transcodeResultPath, tone: pathExists(transcodeResultPath) ? .success : .neutral)
                }
            }
        }
    }

    private var matrixSection: some View {
        let preflight = matrixPreflight
        return SectionCard("Suggest Matrix", subtitle: "Estimate camera matrix with confidence/warnings and apply to project config.") {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                preflightView(preflight, context: .suggestMatrix)

                LabeledPathField(
                    label: "Input RAW Frame",
                    placeholder: "/path/to/frame.cr2",
                    text: $matrixInputPath,
                    icon: "folder",
                    browseHelp: "Choose RAW input file",
                    isDisabled: isRunningTool
                ) {
                    if let path = chooseFilePath(allowedExtensions: ["cr2", "cr3", "raw", "dng", "nef", "arw"]) {
                        matrixInputPath = path
                    }
                }

                recentMenuRow(
                    title: "Recent Inputs",
                    values: decodeRecentValues(recentMatrixInputRaw),
                    onPick: { matrixInputPath = $0 },
                    onClear: { recentMatrixInputRaw = "" }
                )

                HStack(spacing: StopmoUI.Spacing.sm) {
                    TextField("Camera make override (optional)", text: $matrixCameraMake)
                        .textFieldStyle(.roundedBorder)
                    TextField("Camera model override (optional)", text: $matrixCameraModel)
                        .textFieldStyle(.roundedBorder)
                }
                .frame(maxWidth: 760)

                LabeledPathField(
                    label: "JSON Report Path (Optional)",
                    placeholder: "/path/to/matrix_report.json",
                    text: $matrixWriteJsonPath,
                    icon: "doc.badge.plus",
                    browseHelp: "Choose JSON report output path",
                    isDisabled: isRunningTool
                ) {
                    if let path = chooseSaveFilePath(defaultName: "matrix_report.json", contentType: .json) {
                        matrixWriteJsonPath = path
                    }
                }

                recentMenuRow(
                    title: "Recent Reports",
                    values: decodeRecentValues(recentMatrixReportRaw),
                    onPick: { matrixWriteJsonPath = $0 },
                    onClear: { recentMatrixReportRaw = "" }
                )

                HStack(spacing: StopmoUI.Spacing.sm) {
                    Button("Run Suggest Matrix") {
                        Task { await runSuggestMatrix() }
                    }
                    .disabled(isRunningTool || !preflight.ok)

                    Button("Apply Matrix To Project") {
                        applySuggestedMatrixToProject()
                    }
                    .disabled(isRunningTool || latestMatrix == nil)

                    Button("Copy Matrix") {
                        copySuggestedMatrix()
                    }
                    .disabled(latestMatrix == nil)

                    Button("Open Report") {
                        state.openPathInFinder(matrixWriteJsonPath)
                    }
                    .disabled(matrixWriteJsonPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if !matrixConfidence.isEmpty {
                        StatusChip(label: "Confidence \(matrixConfidence)", tone: .neutral)
                    }
                }

                if let matrix = latestMatrix {
                    VStack(alignment: .leading, spacing: StopmoUI.Spacing.xxs) {
                        Text("Suggested Matrix")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(matrix.indices, id: \.self) { idx in
                            Text(matrix[idx].map { String(format: "%.8f", $0) }.joined(separator: "  "))
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }

                if !matrixSummary.isEmpty {
                    VStack(alignment: .leading, spacing: StopmoUI.Spacing.xxs) {
                        Text("Result Summary")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
        let preflight = dpxPreflight
        return SectionCard("DPX To ProRes", subtitle: "Batch DPX conversion with preflight checks and output actions.") {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                preflightView(preflight, context: .dpxToProres)

                LabeledPathField(
                    label: "Input Directory",
                    placeholder: "/path/to/dpx_root",
                    text: $dpxInputDir,
                    icon: "folder",
                    browseHelp: "Choose input directory",
                    isDisabled: isRunningTool
                ) {
                    if let path = chooseDirectoryPath() {
                        dpxInputDir = path
                    }
                }

                recentMenuRow(
                    title: "Recent Inputs",
                    values: decodeRecentValues(recentDpxInputRaw),
                    onPick: { dpxInputDir = $0 },
                    onClear: { recentDpxInputRaw = "" }
                )

                LabeledPathField(
                    label: "Output Directory (Optional)",
                    placeholder: "/path/to/prores_output",
                    text: $dpxOutputDir,
                    icon: "folder",
                    browseHelp: "Choose output directory",
                    isDisabled: isRunningTool
                ) {
                    if let path = chooseDirectoryPath() {
                        dpxOutputDir = path
                    }
                }

                recentMenuRow(
                    title: "Recent Outputs",
                    values: decodeRecentValues(recentDpxOutputRaw),
                    onPick: { dpxOutputDir = $0 },
                    onClear: { recentDpxOutputRaw = "" }
                )

                HStack(spacing: StopmoUI.Spacing.md) {
                    Stepper("Framerate: \(dpxFramerate)", value: $dpxFramerate, in: 1 ... 120)
                    Toggle("Overwrite", isOn: $dpxOverwrite)
                }

                HStack(spacing: StopmoUI.Spacing.sm) {
                    Button("Run DPX To ProRes") {
                        Task { await runDpxToProres() }
                    }
                    .disabled(isRunningTool || !preflight.ok)

                    if !dpxProgressText.isEmpty {
                        StatusChip(label: dpxProgressText, tone: .neutral)
                    }
                }

                if !dpxOutputs.isEmpty {
                    VStack(alignment: .leading, spacing: StopmoUI.Spacing.xxs) {
                        Text("Outputs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(dpxOutputs, id: \.self) { output in
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
    }

    private var timelineSection: some View {
        SectionCard("Progress Timeline", subtitle: "Staged progress milestones for the latest tool run.") {
            if toolTimeline.isEmpty {
                EmptyStateCard(message: "No timeline yet. Run a tool to capture staged progress.")
            } else {
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                    ForEach(toolTimeline) { item in
                        HStack(alignment: .top, spacing: StopmoUI.Spacing.xs) {
                            StatusChip(label: item.timestampLabel, tone: .neutral)
                            StatusChip(label: item.title, tone: item.tone)
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    private var eventsSection: some View {
        SectionCard("Operation Events", subtitle: "Captured backend events from the latest tool run.") {
            HStack(spacing: StopmoUI.Spacing.sm) {
                Picker("Filter", selection: $eventFilter) {
                    ForEach(ToolEventFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

                TextField("Search events", text: $eventSearch)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)

                Button("Clear") {
                    latestEvents = []
                    toolTimeline = []
                    eventSearch = ""
                    state.statusMessage = "Tool events cleared"
                }
                .disabled(latestEvents.isEmpty && toolTimeline.isEmpty)
            }

            if filteredEvents.isEmpty {
                EmptyStateCard(message: "No operation events match the current filters.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: StopmoUI.Spacing.xxs) {
                        ForEach(filteredEvents) { ev in
                            HStack(alignment: .firstTextBaseline, spacing: StopmoUI.Spacing.xs) {
                                StatusChip(label: ev.eventType, tone: toneForEvent(ev))
                                Text("[\(ev.timestampUtc)] \(ev.message ?? "")")
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: 260)
            }
        }
    }

    private func preflightView(_ preflight: ToolPreflight, context: ToolKind) -> some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.xxs) {
            HStack(spacing: StopmoUI.Spacing.xs) {
                StatusChip(label: preflight.ok ? "Preflight OK" : "Preflight Blocked", tone: preflight.ok ? .success : .danger)
                StatusChip(label: context.rawValue, tone: .neutral)
            }
            if !preflight.blockers.isEmpty {
                ForEach(preflight.blockers, id: \.self) { item in
                    Text("Blocker: \(item)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            if !preflight.warnings.isEmpty {
                ForEach(preflight.warnings, id: \.self) { item in
                    Text("Warning: \(item)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func recentMenuRow(
        title: String,
        values: [String],
        onPick: @escaping (String) -> Void,
        onClear: @escaping () -> Void
    ) -> some View {
        HStack(spacing: StopmoUI.Spacing.sm) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: StopmoUI.Width.formLabel, alignment: .leading)
            if values.isEmpty {
                Text("No recents yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Menu("Use Recent") {
                    ForEach(values, id: \.self) { value in
                        Button(value) {
                            onPick(value)
                        }
                    }
                }
                Button("Clear") {
                    onClear()
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func runTranscodeOne() async {
        let preflight = transcodePreflight
        guard preflight.ok else {
            state.presentWarning(
                title: "Transcode Preflight Blocked",
                message: preflight.blockers.joined(separator: "; ")
            )
            appendTimeline(title: "Preflight", detail: "Transcode blocked", tone: .danger)
            return
        }

        let repoRoot = state.repoRoot
        let configPath = state.configPath
        let inputPath = transcodeInputPath
        let outputDir = emptyToNil(transcodeOutputDir)

        await runTool(kind: .transcodeOne) {
            let result = try await Task.detached(priority: .userInitiated) {
                try BridgeClient().transcodeOne(
                    repoRoot: repoRoot,
                    configPath: configPath,
                    inputPath: inputPath,
                    outputDir: outputDir
                )
            }.value

            ingestToolEnvelope(result)
            transcodeResultPath = result.operation.result?["output_path"]?.stringValue ?? ""
            appendTimeline(
                title: "Result",
                detail: transcodeResultPath.isEmpty ? "Completed without output path payload." : "Output: \(transcodeResultPath)",
                tone: .success
            )

            recentTranscodeInputRaw = updatedRecentRaw(recentTranscodeInputRaw, adding: inputPath)
            if let outputDir {
                recentTranscodeOutputRaw = updatedRecentRaw(recentTranscodeOutputRaw, adding: outputDir)
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
            appendTimeline(title: "Preflight", detail: "Suggest Matrix blocked", tone: .danger)
            return
        }

        let repoRoot = state.repoRoot
        let inputPath = matrixInputPath
        let cameraMake = emptyToNil(matrixCameraMake)
        let cameraModel = emptyToNil(matrixCameraModel)
        let writeJson = emptyToNil(matrixWriteJsonPath)

        await runTool(kind: .suggestMatrix) {
            let result = try await Task.detached(priority: .userInitiated) {
                try BridgeClient().suggestMatrix(
                    repoRoot: repoRoot,
                    inputPath: inputPath,
                    cameraMake: cameraMake,
                    cameraModel: cameraModel,
                    writeJson: writeJson
                )
            }.value

            ingestToolEnvelope(result)
            matrixResultPayload = result.operation.result ?? [:]
            matrixConfidence = stringValue(from: matrixResultPayload["confidence"])
            matrixSummary = summarizeMatrixResult(result.operation.result)
            appendTimeline(
                title: "Result",
                detail: matrixSummary.isEmpty ? "Matrix suggestion completed." : matrixSummary.joined(separator: " | "),
                tone: .success
            )

            recentMatrixInputRaw = updatedRecentRaw(recentMatrixInputRaw, adding: inputPath)
            if let writeJson {
                recentMatrixReportRaw = updatedRecentRaw(recentMatrixReportRaw, adding: writeJson)
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
            appendTimeline(title: "Preflight", detail: "DPX to ProRes blocked", tone: .danger)
            return
        }

        let repoRoot = state.repoRoot
        let inputDir = dpxInputDir
        let outputDir = emptyToNil(dpxOutputDir)
        let framerate = dpxFramerate
        let overwrite = dpxOverwrite

        await runTool(kind: .dpxToProres) {
            let result = try await Task.detached(priority: .userInitiated) {
                try BridgeClient().dpxToProres(
                    repoRoot: repoRoot,
                    inputDir: inputDir,
                    outputDir: outputDir,
                    framerate: framerate,
                    overwrite: overwrite
                )
            }.value

            ingestToolEnvelope(result)
            let completed = result.operation.result?["count"]?.intValue ?? 0
            let total = result.operation.result?["total_sequences"]?.intValue ?? completed
            dpxProgressText = "Completed \(completed) / \(total) sequences"
            dpxOutputs = result.operation.result?["outputs"]?.arrayValue?.compactMap(\.stringValue) ?? []
            appendTimeline(title: "Result", detail: dpxProgressText, tone: .success)

            recentDpxInputRaw = updatedRecentRaw(recentDpxInputRaw, adding: inputDir)
            if let outputDir {
                recentDpxOutputRaw = updatedRecentRaw(recentDpxOutputRaw, adding: outputDir)
            }
        }
    }

    private func runTool(
        kind: ToolKind,
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
        lastToolCompletedLabel = timeNowLabel()
    }

    private func ingestToolEnvelope(_ envelope: ToolOperationEnvelope) {
        latestEvents = envelope.events.reversed()
        appendTimeline(
            title: "Operation",
            detail: "\(envelope.operation.kind) \(envelope.operation.status) (\(Int((envelope.operation.progress * 100.0).rounded()))%)",
            tone: toneForStatus(envelope.operation.status)
        )
        if let tailEvent = envelope.events.last {
            appendTimeline(
                title: tailEvent.eventType,
                detail: tailEvent.message ?? "",
                tone: toneForEvent(tailEvent)
            )
        }
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
        appendTimeline(title: "Config", detail: "Applied suggested matrix to project", tone: .success)
    }

    private func copySuggestedMatrix() {
        guard let matrix = latestMatrix else { return }
        let text = matrix
            .map { row in row.map { String(format: "%.8f", $0) }.joined(separator: ", ") }
            .joined(separator: "\n")
        state.copyTextToPasteboard(text, label: "matrix")
    }

    private var latestMatrix: [[Double]]? {
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

    private var transcodePreflight: ToolPreflight {
        var blockers: [String] = []
        var warnings: [String] = []

        let input = transcodeInputPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.isEmpty {
            blockers.append("Input RAW frame path is required.")
        } else if !pathExists(input) {
            blockers.append("Input RAW frame path does not exist.")
        }

        let output = transcodeOutputDir.trimmingCharacters(in: .whitespacesAndNewlines)
        if !output.isEmpty, !pathExists(output) {
            warnings.append("Output override path does not currently exist and will be created if possible.")
        }

        return ToolPreflight(blockers: blockers, warnings: warnings)
    }

    private var matrixPreflight: ToolPreflight {
        var blockers: [String] = []
        var warnings: [String] = []

        let input = matrixInputPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.isEmpty {
            blockers.append("Input RAW frame path is required.")
        } else if !pathExists(input) {
            blockers.append("Input RAW frame path does not exist.")
        }

        let reportPath = matrixWriteJsonPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !reportPath.isEmpty {
            let parent = (reportPath as NSString).deletingLastPathComponent
            if parent.isEmpty || !pathExists(parent) {
                warnings.append("JSON report parent folder does not exist.")
            }
        }

        return ToolPreflight(blockers: blockers, warnings: warnings)
    }

    private var dpxPreflight: ToolPreflight {
        var blockers: [String] = []
        var warnings: [String] = []

        let inputDir = dpxInputDir.trimmingCharacters(in: .whitespacesAndNewlines)
        if inputDir.isEmpty {
            blockers.append("Input directory is required.")
        } else if !pathExists(inputDir) {
            blockers.append("Input directory does not exist.")
        } else {
            let dpxCount = countDpxFiles(in: inputDir)
            if dpxCount == 0 {
                warnings.append("No .dpx files were found under the input directory.")
            }
        }

        let outputDir = dpxOutputDir.trimmingCharacters(in: .whitespacesAndNewlines)
        if !outputDir.isEmpty, !pathExists(outputDir) {
            warnings.append("Output directory does not exist and will be created if possible.")
        }
        if !inputDir.isEmpty, !outputDir.isEmpty, inputDir == outputDir {
            warnings.append("Input and output directories are the same.")
        }

        return ToolPreflight(blockers: blockers, warnings: warnings)
    }

    private var filteredEvents: [OperationEventRecord] {
        let term = eventSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return latestEvents.filter { ev in
            if !term.isEmpty {
                let haystack = [ev.operationId, ev.timestampUtc, ev.eventType, ev.message ?? ""]
                    .joined(separator: " ")
                    .lowercased()
                if !haystack.contains(term) {
                    return false
                }
            }
            switch eventFilter {
            case .all:
                return true
            case .milestones:
                return ev.eventType.lowercased().contains("start")
                    || ev.eventType.lowercased().contains("succeed")
                    || ev.eventType.lowercased().contains("fail")
                    || ev.eventType.lowercased().contains("complete")
            case .errors:
                let et = ev.eventType.lowercased()
                let msg = (ev.message ?? "").lowercased()
                return et.contains("error") || et.contains("fail") || msg.contains("error") || msg.contains("fail")
            }
        }
    }

    private func toneForStatus(_ status: String) -> StatusTone {
        let s = status.lowercased()
        if s.contains("succeed") || s.contains("done") {
            return .success
        }
        if s.contains("fail") || s.contains("error") {
            return .danger
        }
        if s.contains("running") || s.contains("pending") {
            return .warning
        }
        return .neutral
    }

    private func toneForEvent(_ event: OperationEventRecord) -> StatusTone {
        let eventType = event.eventType.lowercased()
        let message = (event.message ?? "").lowercased()
        if eventType.contains("error") || eventType.contains("fail") || message.contains("error") || message.contains("fail") {
            return .danger
        }
        if eventType.contains("succeed") || eventType.contains("done") || eventType.contains("complete") {
            return .success
        }
        if eventType.contains("start") || eventType.contains("progress") || eventType.contains("stage") {
            return .warning
        }
        return .neutral
    }

    private func appendTimeline(title: String, detail: String, tone: StatusTone) {
        let item = ToolTimelineItem(
            timestampLabel: timeNowLabel(),
            title: title,
            detail: detail,
            tone: tone
        )
        toolTimeline.insert(item, at: 0)
        if toolTimeline.count > 80 {
            toolTimeline = Array(toolTimeline.prefix(80))
        }
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

    private func decodeRecentValues(_ raw: String) -> [String] {
        raw
            .split(separator: "\n")
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func updatedRecentRaw(_ currentRaw: String, adding value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return currentRaw }

        var values = decodeRecentValues(currentRaw)
        values.removeAll { $0 == trimmed }
        values.insert(trimmed, at: 0)
        if values.count > 8 {
            values = Array(values.prefix(8))
        }
        return values.joined(separator: "\n")
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
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        return FileManager.default.fileExists(atPath: trimmed)
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

    private func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func timeNowLabel() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}
