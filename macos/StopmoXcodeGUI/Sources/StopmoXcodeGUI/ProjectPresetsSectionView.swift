import SwiftUI

struct ProjectPresetsSectionView: View {
    @Binding var presetNameInput: String
    @Binding var selectedPresetName: String

    let presetNames: [String]
    let selectedPresetConfig: StopmoConfigDocument?
    let isBusy: Bool
    let onSaveCurrentAsPreset: () -> Void
    let onLoadSelectedPreset: () -> Void
    let onDeleteSelectedPreset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            fieldRow("Preset Name") {
                textField("Preset name", text: $presetNameInput)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: StopmoUI.Spacing.sm) {
                    actionButtons
                }
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                    actionButtons
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
                if let selectedPresetConfig {
                    KeyValueRow(key: "Preset Config Path", value: selectedPresetConfig.configPath ?? "-")
                    KeyValueRow(key: "Preset Target EI", value: "\(selectedPresetConfig.pipeline.targetEi)")
                    KeyValueRow(key: "Preset Framerate", value: "\(selectedPresetConfig.output.framerate)")
                }
            }
        }
    }

    private var actionButtons: some View {
        Group {
            Button("Save Current As Preset") {
                onSaveCurrentAsPreset()
            }
            .disabled(isBusy)

            Button("Load Selected Preset") {
                onLoadSelectedPreset()
            }
            .disabled(isBusy || selectedPresetName.isEmpty)

            Button("Delete Selected Preset") {
                onDeleteSelectedPreset()
            }
            .disabled(isBusy || selectedPresetName.isEmpty)
        }
    }

    private func fieldRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: StopmoUI.Spacing.sm) {
            Text(label)
                .frame(width: StopmoUI.Width.formLabel, alignment: .leading)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func textField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 680, alignment: .leading)
    }
}
