import SwiftUI

struct ProjectWatchSectionView: View {
    @Binding var watch: StopmoConfigDocument.Watch

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            fieldRow("Source Directory") {
                textField("Source directory", text: $watch.sourceDir)
            }
            fieldRow("Working Directory") {
                textField("Working directory", text: $watch.workingDir)
            }
            fieldRow("Output Directory") {
                textField("Output directory", text: $watch.outputDir)
            }
            fieldRow("Database Path") {
                textField("DB path", text: $watch.dbPath)
            }
            fieldRow("Include Extensions") {
                textField("Comma separated extensions", text: includeExtensionsBinding)
            }
            fieldRow("Stable Seconds") {
                numberField("Stable seconds", value: $watch.stableSeconds)
            }
            fieldRow("Poll Interval Seconds") {
                numberField("Poll interval seconds", value: $watch.pollIntervalSeconds)
            }
            fieldRow("Scan Interval Seconds") {
                numberField("Scan interval seconds", value: $watch.scanIntervalSeconds)
            }
            fieldRow("Max Workers") {
                integerField("Max workers", value: $watch.maxWorkers)
            }
            fieldRow("Shot Complete Seconds") {
                numberField("Shot complete seconds", value: $watch.shotCompleteSeconds)
            }
            fieldRow("Shot Regex") {
                textField("Optional shot regex", text: shotRegexBinding)
            }
        }
    }

    private var includeExtensionsBinding: Binding<String> {
        Binding<String>(
            get: { watch.includeExtensions.joined(separator: ", ") },
            set: { newValue in
                watch.includeExtensions = newValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private var shotRegexBinding: Binding<String> {
        Binding<String>(
            get: { watch.shotRegex ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                watch.shotRegex = trimmed.isEmpty ? nil : trimmed
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
}
