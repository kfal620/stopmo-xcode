import SwiftUI
import AppKit

/// User-facing sections within the unified Configure workspace.
enum ConfigureSection: String, CaseIterable, Identifiable {
    case workspace = "Workspace"
    case recipe = "Recipe"
    case output = "Output"
    case logging = "Logging"
    case presets = "Presets"
    case healthPreflight = "Health & Preflight"
    case calibrationLab = "Calibration Lab"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .workspace:
            return "folder.badge.gearshape"
        case .recipe:
            return "camera.filters"
        case .output:
            return "shippingbox"
        case .logging:
            return "doc.text.magnifyingglass"
        case .presets:
            return "square.stack.3d.up"
        case .healthPreflight:
            return "stethoscope"
        case .calibrationLab:
            return "wand.and.stars"
        }
    }

    var subtitle: String {
        switch self {
        case .workspace:
            return "Workspace access, config path, and watch roots."
        case .recipe:
            return "Deterministic color and exposure policy."
        case .output:
            return "Delivery defaults and review/debug outputs."
        case .logging:
            return "Log routing and verbosity."
        case .presets:
            return "Reusable config snapshots."
        case .healthPreflight:
            return "Runtime health, validation, and watch blockers."
        case .calibrationLab:
            return "Transcode One and Suggest Matrix utilities."
        }
    }

    var isProjectEditingSection: Bool {
        switch self {
        case .workspace, .recipe, .output, .logging, .presets:
            return true
        case .healthPreflight, .calibrationLab:
            return false
        }
    }

    var embedsScrollableWorkspace: Bool {
        self == .healthPreflight || self == .calibrationLab
    }

    static func resolve(
        panel: ConfigurePanel,
        lastProjectSection: ConfigureSection
    ) -> ConfigureSection {
        switch panel {
        case .projectSettings:
            return lastProjectSection
        case .workspaceHealth:
            return .healthPreflight
        case .calibration:
            return .calibrationLab
        }
    }
}

/// Unified setup workspace that merges configuration, health, and calibration into one calm flow.
struct ConfigureWorkspaceView: View {
    @EnvironmentObject private var state: AppState

    @StateObject private var editor = ProjectEditorViewModel()
    @State private var selectedSection: ConfigureSection = .workspace
    @State private var lastProjectSection: ConfigureSection = .workspace
    @State private var initialLoadRequested: Bool = false
    @State private var presets: [String: StopmoConfigDocument] = [:]
    @State private var selectedPresetName: String = ""
    @State private var presetNameInput: String = ""

    private static let presetsDefaultsKey = "stopmo_project_presets_v1"

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            workspaceHeader

            AdaptiveColumns(breakpoint: 1180, spacing: StopmoUI.Spacing.md) {
                primaryWorkspace
            } secondary: {
                inspectorColumn
            }

            footerBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            loadPresets()
            syncSectionFromPanel(state.selectedConfigurePanel)
            if !initialLoadRequested {
                initialLoadRequested = true
                Task { await reloadFromDisk() }
            } else {
                editor.bootstrapIfNeeded(from: state.config)
            }
        }
        .onChange(of: state.selectedConfigurePanel) { _, panel in
            syncSectionFromPanel(panel)
        }
        .onChange(of: selectedSection) { _, next in
            if next.isProjectEditingSection {
                lastProjectSection = next
                state.selectedConfigurePanel = .projectSettings
            } else if next == .healthPreflight {
                state.selectedConfigurePanel = .workspaceHealth
            } else if next == .calibrationLab {
                state.selectedConfigurePanel = .calibration
            }
        }
        .onChange(of: state.statusMessage) { _, status in
            if status == "Loaded config" || status == "Saved config" {
                editor.acceptLoadedConfig(state.config)
            }
        }
    }

    private var workspaceHeader: some View {
        ToolbarStrip(title: LifecycleHub.configure.displayTitle) {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                Text("One setup workspace for machine readiness, deterministic recipe editing, and calibration.")
                    .metadataTextStyle(.secondary)

                SummaryFactStrip(
                    facts: [
                        SummaryFact(id: "workspace", label: "Workspace", value: state.workspaceAccessActive ? "Granted" : "Needs Access", tone: state.workspaceAccessActive ? .success : .warning),
                        SummaryFact(id: "draft", label: "Draft", value: hasUnsavedChanges ? "Unsaved" : "Saved", tone: hasUnsavedChanges ? .warning : .success),
                        SummaryFact(id: "health", label: "Health", value: runtimeSummaryLabel, tone: runtimeSummaryTone),
                        SummaryFact(id: "preflight", label: "Preflight", value: preflightSummaryLabel, tone: preflightSummaryTone),
                    ],
                    minItemWidth: 110,
                    compact: true
                )
            }
        }
    }

    private var primaryWorkspace: some View {
        HStack(alignment: .top, spacing: StopmoUI.Spacing.md) {
            sectionRail
                .frame(width: 210, alignment: .topLeading)

            Group {
                if selectedSection.embedsScrollableWorkspace {
                    selectedSectionContent
                } else {
                    ScrollView {
                        selectedSectionContent
                            .padding(.bottom, StopmoUI.Spacing.sm)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var sectionRail: some View {
        SurfaceContainer(level: .panel, chrome: .quiet, cornerRadius: 14) {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                ForEach(ConfigureSection.allCases) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        HStack(spacing: StopmoUI.Spacing.sm) {
                            Image(systemName: section.iconName)
                                .frame(width: 16, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                Text(section.subtitle)
                                    .metadataTextStyle(.tertiary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .foregroundStyle(
                            selectedSection == section
                                ? sectionAccent(section)
                                : AppVisualTokens.textPrimary
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    selectedSection == section
                                        ? sectionAccent(section).opacity(0.12)
                                        : Color.clear
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch selectedSection {
        case .workspace:
            workspaceSection
        case .recipe:
            recipeSection
        case .output:
            outputSection
        case .logging:
            loggingSection
        case .presets:
            presetsSection
        case .healthPreflight:
            SetupView(embedded: true)
        case .calibrationLab:
            ToolsView(mode: .utilitiesOnly, embedded: true)
        }
    }

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.md) {
            SectionCard("Workspace", subtitle: ConfigureSection.workspace.subtitle) {
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                    LabeledPathField(
                        label: "Workspace Root",
                        placeholder: "Workspace root",
                        text: $state.repoRoot,
                        icon: "folder",
                        browseHelp: "Browse for workspace root",
                        isDisabled: state.isBusy
                    ) {
                        state.chooseRepoRootDirectory()
                    }

                    LabeledPathField(
                        label: "Config Path",
                        placeholder: "Config path",
                        text: $state.configPath,
                        icon: "doc",
                        browseHelp: "Browse for config file",
                        isDisabled: state.isBusy
                    ) {
                        state.chooseConfigFile()
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: StopmoUI.Spacing.sm) {
                            workspaceActions
                        }
                        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                            workspaceActions
                        }
                    }
                }
            }

            SectionCard("Watch Roots", subtitle: "Source, work, output, and queue settings for daily operation.") {
                ProjectWatchSectionView(watch: $editor.draftConfig.watch)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var workspaceActions: some View {
        Group {
            Button("Grant Workspace Access") {
                state.chooseWorkspaceDirectory()
            }
            .disabled(state.isBusy)

            Button("Use Sample Config") {
                state.useSampleConfig()
            }
            .disabled(state.isBusy)

            Button("Create Config From Sample") {
                state.createConfigFromSample()
            }
            .disabled(state.isBusy)

            Button("Open Config In Finder") {
                state.openConfigInFinder()
            }
            .disabled(state.isBusy)
        }
    }

    private var recipeSection: some View {
        SectionCard("Recipe", subtitle: ConfigureSection.recipe.subtitle) {
            ProjectPipelineSectionView(
                pipeline: $editor.draftConfig.pipeline,
                isBusy: state.isBusy,
                onResetIdentity: resetMatrixIdentity,
                onPasteMatrix: pasteMatrixFromClipboard,
                onCopyMatrix: copyMatrixToClipboard
            )
        }
    }

    private var outputSection: some View {
        SectionCard("Output", subtitle: ConfigureSection.output.subtitle) {
            ProjectOutputSectionView(output: $editor.draftConfig.output)
        }
    }

    private var loggingSection: some View {
        SectionCard("Logging", subtitle: ConfigureSection.logging.subtitle) {
            ProjectLoggingSectionView(
                logLevel: $editor.draftConfig.logLevel,
                logFile: $editor.draftConfig.logFile
            )
        }
    }

    private var presetsSection: some View {
        SectionCard("Presets", subtitle: ConfigureSection.presets.subtitle) {
            ProjectPresetsSectionView(
                presetNameInput: $presetNameInput,
                selectedPresetName: $selectedPresetName,
                presetNames: presetNames,
                selectedPresetConfig: presets[selectedPresetName],
                isBusy: state.isBusy,
                onSaveCurrentAsPreset: saveCurrentAsPreset,
                onLoadSelectedPreset: loadSelectedPreset,
                onDeleteSelectedPreset: deleteSelectedPreset
            )
        }
    }

    private var inspectorColumn: some View {
        WorkspaceInspectorPane(title: "Current Recipe", subtitle: "Deterministic interpretation contract") {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.md) {
                SummaryFactStrip(
                    facts: [
                        SummaryFact(id: "ocio", label: "Output Space", value: editor.draftConfig.pipeline.ocioOutputSpace, tone: .neutral),
                        SummaryFact(id: "ei", label: "Target EI", value: "\(editor.draftConfig.pipeline.targetEi)", tone: .neutral),
                        SummaryFact(id: "fps", label: "Framerate", value: "\(editor.draftConfig.output.framerate) fps", tone: .neutral),
                    ],
                    minItemWidth: 108,
                    compact: true
                )

                KeyValueRow(key: "Plate Contract", value: "ARRI LogC3 EI800 + AWG")
                KeyValueRow(
                    key: "White Balance",
                    value: editor.draftConfig.pipeline.lockWbFromFirstFrame ? "Shot-locked from first frame" : "Manual / unlocked",
                    tone: editor.draftConfig.pipeline.lockWbFromFirstFrame ? .success : .warning
                )
                KeyValueRow(
                    key: "Exposure",
                    value: deterministicExposureSummary,
                    tone: .neutral
                )
                KeyValueRow(
                    key: "Display LUT",
                    value: editor.draftConfig.output.showLutRec709Path == nil ? "External only" : "Override path set",
                    tone: .neutral
                )

                Divider()

                KeyValueRow(key: "Config", value: state.configPath)
                KeyValueRow(key: "Workspace", value: state.repoRoot)
                KeyValueRow(key: "Sample Config", value: state.sampleConfigPath, tone: sampleConfigExists ? .success : .warning)
                KeyValueRow(key: "Validation", value: validationInspectorLabel, tone: validationInspectorTone)
                KeyValueRow(key: "Preflight", value: preflightSummaryLabel, tone: preflightSummaryTone)
                KeyValueRow(key: "Runtime", value: runtimeSummaryLabel, tone: runtimeSummaryTone)
            }
        }
    }

    private var footerBar: some View {
        SurfaceContainer(level: .raised, chrome: .quiet, cornerRadius: 14) {
            HStack(spacing: StopmoUI.Spacing.sm) {
                HStack(spacing: StopmoUI.Spacing.xs) {
                    StatusChip(
                        label: hasUnsavedChanges ? "Unsaved Changes" : "Saved",
                        tone: hasUnsavedChanges ? .warning : .success
                    )
                    StatusChip(label: validationInspectorLabel, tone: validationInspectorTone, density: .compact)
                    StatusChip(label: preflightSummaryLabel, tone: preflightSummaryTone, density: .compact)
                }

                Spacer(minLength: 0)

                Button("Discard") {
                    discardLocalChanges()
                }
                .disabled(state.isBusy || !hasUnsavedChanges)

                Button("Reload") {
                    Task { await reloadFromDisk() }
                }
                .disabled(state.isBusy)

                Button("Validate") {
                    Task { await state.validateConfig() }
                }
                .disabled(state.isBusy)

                Button("Run Preflight") {
                    Task { await state.refreshWatchPreflight() }
                }
                .disabled(state.isBusy)

                Button("Save") {
                    Task { await saveToDisk() }
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(state.isBusy || !hasUnsavedChanges)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private var hasUnsavedChanges: Bool {
        editor.hasUnsavedChanges
    }

    private var presetNames: [String] {
        presets.keys.sorted()
    }

    private var runtimeSummaryLabel: String {
        guard let health = state.health else {
            return "Not Checked"
        }
        if health.venvPythonExists == false {
            return "Runtime Missing"
        }
        if health.ffmpegPath == nil {
            return "FFmpeg Missing"
        }
        return "Healthy"
    }

    private var runtimeSummaryTone: StatusTone {
        switch runtimeSummaryLabel {
        case "Healthy":
            return .success
        case "Not Checked":
            return .neutral
        default:
            return .warning
        }
    }

    private var validationInspectorLabel: String {
        guard let validation = state.configValidation else {
            return "Validation Not Run"
        }
        if validation.ok && validation.warnings.isEmpty {
            return "Validation OK"
        }
        if !validation.errors.isEmpty {
            return "\(validation.errors.count) Error(s)"
        }
        return "\(validation.warnings.count) Warning(s)"
    }

    private var validationInspectorTone: StatusTone {
        guard let validation = state.configValidation else {
            return .neutral
        }
        if !validation.errors.isEmpty {
            return .danger
        }
        if !validation.warnings.isEmpty {
            return .warning
        }
        return .success
    }

    private var preflightSummaryLabel: String {
        guard let preflight = state.watchPreflight else {
            return "Preflight Not Run"
        }
        return preflight.ok ? "Preflight Ready" : "Blocked"
    }

    private var preflightSummaryTone: StatusTone {
        guard let preflight = state.watchPreflight else {
            return .neutral
        }
        return preflight.ok ? .success : .danger
    }

    private var sampleConfigExists: Bool {
        FileManager.default.fileExists(atPath: state.sampleConfigPath)
    }

    private var deterministicExposureSummary: String {
        var terms: [String] = [
            String(format: "Base %.2f stops", editor.draftConfig.pipeline.exposureOffsetStops),
        ]
        if editor.draftConfig.pipeline.autoExposureFromIso {
            terms.append("ISO comp")
        }
        if editor.draftConfig.pipeline.autoExposureFromShutter {
            terms.append("shutter comp")
        }
        if editor.draftConfig.pipeline.autoExposureFromAperture {
            terms.append("aperture comp")
        }
        return terms.joined(separator: " + ")
    }

    private func sectionAccent(_ section: ConfigureSection) -> Color {
        switch section {
        case .healthPreflight:
            return LifecycleHub.capture.accentColor
        case .calibrationLab:
            return LifecycleHub.deliver.accentColor
        default:
            return LifecycleHub.configure.accentColor
        }
    }

    private func syncSectionFromPanel(_ panel: ConfigurePanel) {
        let resolved = ConfigureSection.resolve(panel: panel, lastProjectSection: lastProjectSection)
        guard selectedSection != resolved else {
            return
        }
        selectedSection = resolved
    }

    private func reloadFromDisk() async {
        await state.loadConfig()
        if state.errorMessage == nil {
            editor.acceptLoadedConfig(state.config)
        }
    }

    private func saveToDisk() async {
        await state.saveConfig(config: editor.draftConfig)
        if state.errorMessage == nil {
            editor.acceptLoadedConfig(state.config)
        }
    }

    private func discardLocalChanges() {
        guard editor.discardChanges() else {
            return
        }
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
        presets[trimmed] = editor.draftConfig
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
        editor.applyPreset(preset)
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

    private func resetMatrixIdentity() {
        editor.resetMatrixIdentity()
        state.statusMessage = "Reset matrix to identity"
    }

    private func copyMatrixToClipboard() {
        guard let payload = editor.matrixPayloadForCopy() else {
            state.presentWarning(
                title: "Matrix Copy Skipped",
                message: "Current matrix is not a valid 3x3 value grid.",
                likelyCause: "Matrix rows/columns are incomplete.",
                suggestedAction: "Fix matrix values and try Copy 3x3 again."
            )
            return
        }
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
        editor.applyMatrix(matrix)
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
}
