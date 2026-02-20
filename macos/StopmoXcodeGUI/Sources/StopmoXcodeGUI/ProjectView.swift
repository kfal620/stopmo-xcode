import SwiftUI
import AppKit

private enum ProjectEditorSection: String, CaseIterable, Identifiable {
    case watch = "Watch"
    case pipeline = "Pipeline"
    case output = "Output"
    case logging = "Logging"
    case presets = "Presets"

    var id: String { rawValue }
}

struct ProjectView: View {
    @EnvironmentObject private var state: AppState

    @State private var selectedEditorSection: ProjectEditorSection = .watch
    @State private var baselineConfig: StopmoConfigDocument = .empty
    @State private var baselineInitialized: Bool = false

    @State private var presets: [String: StopmoConfigDocument] = [:]
    @State private var selectedPresetName: String = ""
    @State private var presetNameInput: String = ""

    private static let presetsDefaultsKey = "stopmo_project_presets_v1"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.lg) {
                ScreenHeader(
                    title: "Project",
                    subtitle: "Watch, pipeline, output, logging, and reusable presets."
                ) {
                    HStack(spacing: StopmoUI.Spacing.sm) {
                        StatusChip(
                            label: hasUnsavedChanges ? "Unsaved Changes" : "Saved",
                            tone: hasUnsavedChanges ? .warning : .success
                        )

                        Button("Reload") {
                            Task { await reloadFromDisk() }
                        }
                        .disabled(state.isBusy)

                        Button("Save") {
                            Task { await saveToDisk() }
                        }
                        .keyboardShortcut("s", modifiers: [.command])
                        .disabled(state.isBusy || !hasUnsavedChanges)

                        Button("Discard") {
                            discardLocalChanges()
                        }
                        .disabled(state.isBusy || !hasUnsavedChanges)
                    }
                }

                if hasUnsavedChanges {
                    SectionCard("Unsaved Changes") {
                        Text("Project config has local edits that are not yet written to disk.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HStack(spacing: StopmoUI.Spacing.sm) {
                            Button("Save Changes") {
                                Task { await saveToDisk() }
                            }
                            .disabled(state.isBusy)
                            Button("Discard Changes") {
                                discardLocalChanges()
                            }
                            .disabled(state.isBusy)
                        }
                    }
                }

                Picker("Project Section", selection: $selectedEditorSection) {
                    ForEach(ProjectEditorSection.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)

                validationStrip

                selectedSectionContent
            }
            .padding(StopmoUI.Spacing.lg)
        }
        .onAppear {
            if !baselineInitialized {
                captureBaselineFromCurrentConfig()
            }
            loadPresets()
        }
        .onChange(of: state.statusMessage) { _, status in
            if status == "Loaded config" || status == "Saved config" {
                captureBaselineFromCurrentConfig()
            }
        }
    }

    private var selectedSectionContent: some View {
        Group {
            switch selectedEditorSection {
            case .watch:
                watchSection
            case .pipeline:
                pipelineSection
            case .output:
                outputSection
            case .logging:
                loggingSection
            case .presets:
                presetsSection
            }
        }
    }

    private var validationStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: StopmoUI.Spacing.sm) {
                ForEach(ProjectEditorSection.allCases) { section in
                    let status = validationStatus(for: section)
                    StatusChip(
                        label: "\(section.rawValue): \(status.label)",
                        tone: status.tone
                    )
                }
            }
        }
    }

    private var watchSection: some View {
        let status = validationStatus(for: .watch)
        return SectionCard("Watch Configuration", subtitle: "Source/work/output paths and watch behavior. \(status.label)") {
            fieldRow("Source Directory") {
                textField("Source directory", text: $state.config.watch.sourceDir)
            }
            fieldRow("Working Directory") {
                textField("Working directory", text: $state.config.watch.workingDir)
            }
            fieldRow("Output Directory") {
                textField("Output directory", text: $state.config.watch.outputDir)
            }
            fieldRow("Database Path") {
                textField("DB path", text: $state.config.watch.dbPath)
            }
            fieldRow("Include Extensions") {
                textField("Comma separated extensions", text: includeExtensionsBinding)
            }
            fieldRow("Stable Seconds") {
                numberField("Stable seconds", value: $state.config.watch.stableSeconds)
            }
            fieldRow("Poll Interval Seconds") {
                numberField("Poll interval seconds", value: $state.config.watch.pollIntervalSeconds)
            }
            fieldRow("Scan Interval Seconds") {
                numberField("Scan interval seconds", value: $state.config.watch.scanIntervalSeconds)
            }
            fieldRow("Max Workers") {
                integerField("Max workers", value: $state.config.watch.maxWorkers)
            }
            fieldRow("Shot Complete Seconds") {
                numberField("Shot complete seconds", value: $state.config.watch.shotCompleteSeconds)
            }
            fieldRow("Shot Regex") {
                textField(
                    "Optional shot regex",
                    text: optionalStringBinding(
                        get: { state.config.watch.shotRegex },
                        set: { state.config.watch.shotRegex = $0 }
                    )
                )
            }
        }
    }

    private var pipelineSection: some View {
        let status = validationStatus(for: .pipeline)
        return SectionCard("Pipeline Configuration", subtitle: "Color transforms, exposure policy, and OCIO settings. \(status.label)") {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                HStack {
                    Text("Camera To Reference Matrix")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset Identity") {
                        resetMatrixIdentity()
                    }
                    .disabled(state.isBusy)
                    Button("Paste 3x3") {
                        pasteMatrixFromClipboard()
                    }
                    .disabled(state.isBusy)
                    Button("Copy 3x3") {
                        copyMatrixToClipboard()
                    }
                    .disabled(state.isBusy)
                }
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: StopmoUI.Spacing.xs) {
                        ForEach(0..<3, id: \.self) { col in
                            TextField(
                                "m\(row)\(col)",
                                value: matrixBinding(row: row, col: col),
                                format: .number.precision(.fractionLength(8))
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                        }
                    }
                }
            }

            fieldRow("Exposure Offset Stops") {
                numberField("Exposure offset", value: $state.config.pipeline.exposureOffsetStops)
            }
            toggleRow("Auto Exposure From ISO", isOn: $state.config.pipeline.autoExposureFromIso)
            toggleRow("Auto Exposure From Shutter", isOn: $state.config.pipeline.autoExposureFromShutter)
            fieldRow("Target Shutter Seconds") {
                textField(
                    "Optional shutter seconds",
                    text: optionalDoubleBinding(
                        get: { state.config.pipeline.targetShutterS },
                        set: { state.config.pipeline.targetShutterS = $0 }
                    )
                )
            }
            toggleRow("Auto Exposure From Aperture", isOn: $state.config.pipeline.autoExposureFromAperture)
            fieldRow("Target Aperture F") {
                textField(
                    "Optional aperture",
                    text: optionalDoubleBinding(
                        get: { state.config.pipeline.targetApertureF },
                        set: { state.config.pipeline.targetApertureF = $0 }
                    )
                )
            }
            fieldRow("Contrast") {
                numberField("Contrast", value: $state.config.pipeline.contrast)
            }
            fieldRow("Contrast Pivot Linear") {
                numberField("Contrast pivot linear", value: $state.config.pipeline.contrastPivotLinear)
            }
            toggleRow("Lock WB From First Frame", isOn: $state.config.pipeline.lockWbFromFirstFrame)
            fieldRow("Target EI") {
                integerField("Target EI", value: $state.config.pipeline.targetEi)
            }
            toggleRow("Apply Match LUT", isOn: $state.config.pipeline.applyMatchLut)
            fieldRow("Match LUT Path") {
                textField(
                    "Optional match LUT path",
                    text: optionalStringBinding(
                        get: { state.config.pipeline.matchLutPath },
                        set: { state.config.pipeline.matchLutPath = $0 }
                    )
                )
            }
            toggleRow("Use OCIO", isOn: $state.config.pipeline.useOcio)
            fieldRow("OCIO Config Path") {
                textField(
                    "Optional OCIO config path",
                    text: optionalStringBinding(
                        get: { state.config.pipeline.ocioConfigPath },
                        set: { state.config.pipeline.ocioConfigPath = $0 }
                    )
                )
            }
            fieldRow("OCIO Input Space") {
                textField("OCIO input space", text: $state.config.pipeline.ocioInputSpace)
            }
            fieldRow("OCIO Reference Space") {
                textField("OCIO reference space", text: $state.config.pipeline.ocioReferenceSpace)
            }
            fieldRow("OCIO Output Space") {
                textField("OCIO output space", text: $state.config.pipeline.ocioOutputSpace)
            }
        }
    }

    private var outputSection: some View {
        let status = validationStatus(for: .output)
        return SectionCard("Output Configuration", subtitle: "Frame outputs, truth frame behavior, and review defaults. \(status.label)") {
            toggleRow("Emit Per Frame JSON", isOn: $state.config.output.emitPerFrameJson)
            toggleRow("Emit Truth Frame Pack", isOn: $state.config.output.emitTruthFramePack)
            fieldRow("Truth Frame Index") {
                integerField("Truth frame index", value: $state.config.output.truthFrameIndex)
            }
            toggleRow("Write Debug TIFF", isOn: $state.config.output.writeDebugTiff)
            toggleRow("Write ProRes On Shot Complete", isOn: $state.config.output.writeProresOnShotComplete)
            fieldRow("Framerate") {
                integerField("Framerate", value: $state.config.output.framerate)
            }
            fieldRow("Show LUT Rec709 Path") {
                textField(
                    "Optional show LUT path",
                    text: optionalStringBinding(
                        get: { state.config.output.showLutRec709Path },
                        set: { state.config.output.showLutRec709Path = $0 }
                    )
                )
            }
        }
    }

    private var loggingSection: some View {
        let status = validationStatus(for: .logging)
        return SectionCard("Logging Configuration", subtitle: status.label) {
            fieldRow("Log Level") {
                textField("Log level", text: $state.config.logLevel)
            }
            fieldRow("Log File") {
                textField(
                    "Optional log file",
                    text: optionalStringBinding(
                        get: { state.config.logFile },
                        set: { state.config.logFile = $0 }
                    )
                )
            }
        }
    }

    private var presetsSection: some View {
        SectionCard("Project Presets", subtitle: "Save and load named config presets locally.") {
            fieldRow("Preset Name") {
                textField("Preset name", text: $presetNameInput)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: StopmoUI.Spacing.sm) {
                    presetsActionButtons
                }
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                    presetsActionButtons
                }
            }

            if presetNames.isEmpty {
                EmptyStateCard(message: "No presets saved yet.")
            } else {
                fieldRow("Saved Presets") {
                    Picker("Saved Presets", selection: $selectedPresetName) {
                        ForEach(presetNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 320, alignment: .leading)
                }
                if let selected = presets[selectedPresetName] {
                    KeyValueRow(key: "Preset Config Path", value: selected.configPath ?? "-")
                    KeyValueRow(key: "Preset Target EI", value: "\(selected.pipeline.targetEi)")
                    KeyValueRow(key: "Preset Framerate", value: "\(selected.output.framerate)")
                }
            }
        }
    }

    private var presetsActionButtons: some View {
        Group {
            Button("Save Current As Preset") {
                saveCurrentAsPreset()
            }
            .disabled(state.isBusy)

            Button("Load Selected Preset") {
                loadSelectedPreset()
            }
            .disabled(state.isBusy || selectedPresetName.isEmpty)

            Button("Delete Selected Preset") {
                deleteSelectedPreset()
            }
            .disabled(state.isBusy || selectedPresetName.isEmpty)
        }
    }

    private var hasUnsavedChanges: Bool {
        guard baselineInitialized else {
            return false
        }
        return !configsEqual(state.config, baselineConfig)
    }

    private var presetNames: [String] {
        presets.keys.sorted()
    }

    private func captureBaselineFromCurrentConfig() {
        baselineConfig = state.config
        baselineInitialized = true
    }

    private func reloadFromDisk() async {
        await state.loadConfig()
        captureBaselineFromCurrentConfig()
    }

    private func saveToDisk() async {
        await state.saveConfig()
        captureBaselineFromCurrentConfig()
    }

    private func discardLocalChanges() {
        guard baselineInitialized else {
            return
        }
        state.config = baselineConfig
        state.statusMessage = "Discarded unsaved project changes"
    }

    private func saveCurrentAsPreset() {
        let trimmed = presetNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state.presentWarning(
                title: "Preset Name Required",
                message: "Enter a preset name before saving.",
                likelyCause: "Preset name field is empty.",
                suggestedAction: "Type a preset name and click Save Current As Preset."
            )
            return
        }
        presets[trimmed] = state.config
        persistPresets()
        selectedPresetName = trimmed
        presetNameInput = trimmed
        state.presentInfo(
            title: "Preset Saved",
            message: trimmed,
            likelyCause: nil,
            suggestedAction: "Use Load Selected Preset to apply it to the project editor."
        )
    }

    private func loadSelectedPreset() {
        guard let preset = presets[selectedPresetName] else {
            state.presentWarning(
                title: "Preset Not Found",
                message: "The selected preset could not be found.",
                likelyCause: "Preset list changed after selection.",
                suggestedAction: "Re-select a preset from the dropdown and try again."
            )
            return
        }
        state.config = preset
        state.statusMessage = "Loaded preset \(selectedPresetName)"
        state.presentInfo(
            title: "Preset Loaded",
            message: selectedPresetName,
            likelyCause: nil,
            suggestedAction: "Review values, then Save to persist them to the project config file."
        )
    }

    private func deleteSelectedPreset() {
        let name = selectedPresetName
        guard !name.isEmpty else {
            return
        }
        presets.removeValue(forKey: name)
        persistPresets()
        selectedPresetName = presetNames.first ?? ""
        if presetNameInput == name {
            presetNameInput = ""
        }
        state.presentInfo(
            title: "Preset Deleted",
            message: name,
            likelyCause: nil,
            suggestedAction: "Save current config as a new preset if you still need a reusable snapshot."
        )
    }

    private func loadPresets() {
        guard let data = UserDefaults.standard.data(forKey: Self.presetsDefaultsKey) else {
            presets = [:]
            selectedPresetName = ""
            return
        }
        do {
            presets = try JSONDecoder().decode([String: StopmoConfigDocument].self, from: data)
            if !presetNames.contains(selectedPresetName) {
                selectedPresetName = presetNames.first ?? ""
            }
        } catch {
            presets = [:]
            selectedPresetName = ""
            state.presentError(title: "Preset Load Failed", message: error.localizedDescription)
        }
    }

    private func persistPresets() {
        do {
            let data = try JSONEncoder().encode(presets)
            UserDefaults.standard.set(data, forKey: Self.presetsDefaultsKey)
        } catch {
            state.presentError(title: "Preset Save Failed", message: error.localizedDescription)
        }
    }

    private func validationStatus(for section: ProjectEditorSection) -> (label: String, tone: StatusTone) {
        if section == .presets {
            return ("N/A", .neutral)
        }
        guard state.configValidation != nil else {
            return ("Not Run", .neutral)
        }
        let counts = validationCounts(for: section)
        if counts.errors > 0 {
            let suffix = counts.errors == 1 ? "" : "s"
            return ("\(counts.errors) error\(suffix)", .danger)
        }
        if counts.warnings > 0 {
            let suffix = counts.warnings == 1 ? "" : "s"
            return ("\(counts.warnings) warning\(suffix)", .warning)
        }
        return ("OK", .success)
    }

    private func validationCounts(for section: ProjectEditorSection) -> (errors: Int, warnings: Int) {
        guard let validation = state.configValidation else {
            return (0, 0)
        }
        let errors = validation.errors.filter { validationSection(forField: $0.field) == section }.count
        let warnings = validation.warnings.filter { validationSection(forField: $0.field) == section }.count
        return (errors, warnings)
    }

    private func validationSection(forField field: String) -> ProjectEditorSection? {
        let normalized = field.lowercased()
        if normalized.hasPrefix("watch") || normalized.contains("watch.") {
            return .watch
        }
        if normalized.hasPrefix("pipeline")
            || normalized.contains("pipeline.")
            || normalized.contains("ocio")
            || normalized.contains("matrix")
            || normalized.contains("exposure")
            || normalized.contains("wb")
            || normalized.contains("lut")
        {
            return .pipeline
        }
        if normalized.hasPrefix("output")
            || normalized.contains("output.")
            || normalized.contains("truth")
            || normalized.contains("framerate")
            || normalized.contains("prores")
        {
            return .output
        }
        if normalized.hasPrefix("log")
            || normalized.contains("log_")
            || normalized.contains("logging")
        {
            return .logging
        }
        return nil
    }

    private func resetMatrixIdentity() {
        state.config.pipeline.cameraToReferenceMatrix = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
        state.statusMessage = "Reset matrix to identity"
    }

    private func copyMatrixToClipboard() {
        let matrix = state.config.pipeline.cameraToReferenceMatrix
        guard matrix.count == 3, matrix.allSatisfy({ $0.count == 3 }) else {
            state.presentWarning(
                title: "Matrix Copy Skipped",
                message: "Current matrix is not a valid 3x3 value grid.",
                likelyCause: "Matrix rows/columns are incomplete.",
                suggestedAction: "Fix matrix values and try Copy 3x3 again."
            )
            return
        }
        let lines = matrix.map { row in row.map { "\($0)" }.joined(separator: " ") }
        let payload = lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
        state.statusMessage = "Copied 3x3 matrix"
    }

    private func pasteMatrixFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            state.presentWarning(
                title: "Paste Matrix Failed",
                message: "Clipboard does not contain text data.",
                likelyCause: "No matrix text is currently copied.",
                suggestedAction: "Copy 9 numeric values (3x3) and try Paste 3x3 again."
            )
            return
        }
        guard let matrix = parseMatrix(text) else {
            state.presentWarning(
                title: "Paste Matrix Failed",
                message: "Could not parse a valid 3x3 numeric matrix from clipboard.",
                likelyCause: "Clipboard text is not in a 3x3 numeric format.",
                suggestedAction: "Provide 9 numbers separated by spaces/newlines (or 3 lines with 3 numbers each)."
            )
            return
        }
        state.config.pipeline.cameraToReferenceMatrix = matrix
        state.statusMessage = "Pasted 3x3 matrix"
    }

    private func parseMatrix(_ text: String) -> [[Double]]? {
        let normalized = text.replacingOccurrences(of: ",", with: " ")
        let tokens = normalized
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
        if tokens.count == 9 {
            let values = tokens.compactMap(Double.init)
            guard values.count == 9 else {
                return nil
            }
            return stride(from: 0, to: 9, by: 3).map { idx in
                [values[idx], values[idx + 1], values[idx + 2]]
            }
        }

        let lines = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.count == 3 else {
            return nil
        }
        var out: [[Double]] = []
        for line in lines {
            let rowValues = line
                .replacingOccurrences(of: ",", with: " ")
                .split(whereSeparator: { $0.isWhitespace })
                .compactMap { Double(String($0)) }
            guard rowValues.count == 3 else {
                return nil
            }
            out.append(rowValues)
        }
        return out
    }

    private func configsEqual(_ lhs: StopmoConfigDocument, _ rhs: StopmoConfigDocument) -> Bool {
        guard let left = configData(lhs), let right = configData(rhs) else {
            return false
        }
        return left == right
    }

    private func configData(_ config: StopmoConfigDocument) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(config)
    }

    private func textField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 680, alignment: .leading)
    }

    private func numberField(_ placeholder: String, value: Binding<Double>) -> some View {
        TextField(placeholder, value: value, format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 180, alignment: .leading)
    }

    private func integerField(_ placeholder: String, value: Binding<Int>) -> some View {
        TextField(placeholder, value: value, format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 180, alignment: .leading)
    }

    private func fieldRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: StopmoUI.Spacing.sm) {
            Text(label)
                .frame(width: StopmoUI.Width.formLabel, alignment: .leading)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: StopmoUI.Spacing.sm) {
            Text(label)
                .frame(width: StopmoUI.Width.formLabel, alignment: .leading)
                .foregroundStyle(.secondary)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .accessibilityLabel(label)
        }
    }

    private var includeExtensionsBinding: Binding<String> {
        Binding<String>(
            get: { state.config.watch.includeExtensions.joined(separator: ", ") },
            set: { newValue in
                state.config.watch.includeExtensions = newValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private func matrixBinding(row: Int, col: Int) -> Binding<Double> {
        Binding<Double>(
            get: {
                guard row < state.config.pipeline.cameraToReferenceMatrix.count,
                      col < state.config.pipeline.cameraToReferenceMatrix[row].count else {
                    return 0.0
                }
                return state.config.pipeline.cameraToReferenceMatrix[row][col]
            },
            set: { newValue in
                guard row < state.config.pipeline.cameraToReferenceMatrix.count,
                      col < state.config.pipeline.cameraToReferenceMatrix[row].count else {
                    return
                }
                state.config.pipeline.cameraToReferenceMatrix[row][col] = newValue
            }
        )
    }

    private func optionalStringBinding(
        get: @escaping () -> String?,
        set: @escaping (String?) -> Void
    ) -> Binding<String> {
        Binding<String>(
            get: { get() ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                set(trimmed.isEmpty ? nil : trimmed)
            }
        )
    }

    private func optionalDoubleBinding(
        get: @escaping () -> Double?,
        set: @escaping (Double?) -> Void
    ) -> Binding<String> {
        Binding<String>(
            get: {
                if let value = get() {
                    return String(value)
                }
                return ""
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    set(nil)
                    return
                }
                if let parsed = Double(trimmed) {
                    set(parsed)
                }
            }
        )
    }
}
