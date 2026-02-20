import SwiftUI

struct ProjectLoggingSectionView: View {
    @Binding var logLevel: String
    @Binding var logFile: String?

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            fieldRow("Log Level") {
                textField("Log level", text: $logLevel)
            }
            fieldRow("Log File") {
                textField("Optional log file", text: logFileBinding)
            }
        }
    }

    private var logFileBinding: Binding<String> {
        Binding<String>(
            get: { logFile ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                logFile = trimmed.isEmpty ? nil : trimmed
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

    private func textField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 680, alignment: .leading)
    }
}
