import SwiftUI

struct ProjectOutputSectionView: View {
    @Binding var output: StopmoConfigDocument.Output

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            toggleRow("Emit Per Frame JSON", isOn: $output.emitPerFrameJson)
            toggleRow("Emit Truth Frame Pack", isOn: $output.emitTruthFramePack)
            fieldRow("Truth Frame Index") {
                integerField("Truth frame index", value: $output.truthFrameIndex)
            }
            toggleRow("Write Debug TIFF", isOn: $output.writeDebugTiff)
            toggleRow("Write ProRes On Shot Complete", isOn: $output.writeProresOnShotComplete)
            fieldRow("Framerate") {
                integerField("Framerate", value: $output.framerate)
            }
            fieldRow("Show LUT Rec709 Path") {
                textField("Optional show LUT path", text: showLutPathBinding)
            }
        }
    }

    private var showLutPathBinding: Binding<String> {
        Binding<String>(
            get: { output.showLutRec709Path ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                output.showLutRec709Path = trimmed.isEmpty ? nil : trimmed
            }
        )
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

    private func textField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 680, alignment: .leading)
    }

    private func integerField(_ placeholder: String, value: Binding<Int>) -> some View {
        TextField(placeholder, value: value, format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 180, alignment: .leading)
    }
}
