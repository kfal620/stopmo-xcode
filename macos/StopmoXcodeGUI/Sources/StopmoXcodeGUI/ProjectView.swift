import SwiftUI
import AppKit

private enum ProjectEditorSection: String, CaseIterable, Identifiable {
    case watch = "Watch"
    case pipeline = "Pipeline"
    case output = "Output"
    case logging = "Logging"
    case presets = "Presets"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .watch:
            return "dot.radiowaves.left.and.right"
        case .pipeline:
            return "camera.filters"
        case .output:
            return "square.and.arrow.down"
        case .logging:
            return "doc.text.magnifyingglass"
        case .presets:
            return "square.stack.3d.up"
        }
    }

    var subtitle: String {
        switch self {
        case .watch:
            return "Source/work/output paths and watch behavior."
        case .pipeline:
            return "Color transforms, exposure policy, and OCIO settings."
        case .output:
            return "Frame outputs, truth frame behavior, and review defaults."
        case .logging:
            return "Log level and destination file settings."
        case .presets:
            return "Save and load named config presets locally."
        }
    }
}

struct ProjectView: View {
    @EnvironmentObject private var state: AppState

    @StateObject private var editor = ProjectEditorViewModel()
    @State private var selectedEditorSection: ProjectEditorSection = .watch
    @State private var initialLoadRequested: Bool = false

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

                sectionWorkspace
            }
            .padding(StopmoUI.Spacing.lg)
        }
        .onAppear {
            loadPresets()
            if !initialLoadRequested {
                initialLoadRequested = true
                Task { await reloadFromDisk() }
            } else {
                editor.bootstrapIfNeeded(from: state.config)
            }
        }
        .onChange(of: state.statusMessage) { _, status in
            if status == "Loaded config" || status == "Saved config" {
                editor.acceptLoadedConfig(state.config)
            }
        }
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
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

    private var sectionWorkspace: some View {
        SectionCard(selectedSectionTitle, subtitle: selectedEditorSection.subtitle) {
            sectionNavigator
            Divider()
            selectedSectionContent
        }
    }

    private var sectionNavigator: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
            Text("Select the section to edit")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: StopmoUI.Spacing.xs) {
                    ForEach(ProjectEditorSection.allCases) { section in
                        let isSelected = section == selectedEditorSection
                        Button {
                            selectedEditorSection = section
                        } label: {
                            Label(section.rawValue, systemImage: section.iconName)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .foregroundStyle(isSelected ? Color.white : Color.primary)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(
                                            isSelected ? Color.accentColor.opacity(0.9) : Color.primary.opacity(0.08),
                                            lineWidth: isSelected ? 0 : 0.75
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(section.rawValue))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var watchSection: some View {
        ProjectWatchSectionView(watch: $editor.draftConfig.watch)
    }

    private var pipelineSection: some View {
        ProjectPipelineSectionView(
            pipeline: $editor.draftConfig.pipeline,
            isBusy: state.isBusy,
            onResetIdentity: resetMatrixIdentity,
            onPasteMatrix: pasteMatrixFromClipboard,
            onCopyMatrix: copyMatrixToClipboard
        )
    }

    private var outputSection: some View {
        ProjectOutputSectionView(output: $editor.draftConfig.output)
    }

    private var loggingSection: some View {
        ProjectLoggingSectionView(logLevel: $editor.draftConfig.logLevel, logFile: $editor.draftConfig.logFile)
    }

    private var presetsSection: some View {
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

    private var selectedSectionTitle: String {
        switch selectedEditorSection {
        case .watch:
            return "Watch Configuration"
        case .pipeline:
            return "Pipeline Configuration"
        case .output:
            return "Output Configuration"
        case .logging:
            return "Logging Configuration"
        case .presets:
            return "Project Presets"
        }
    }

    private var hasUnsavedChanges: Bool {
        editor.hasUnsavedChanges
    }

    private var presetNames: [String] {
        presets.keys.sorted()
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
