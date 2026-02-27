import SwiftUI

struct ToolsDpxPane: View {
    @Binding var inputDir: String
    @Binding var outputDir: String
    @Binding var framerate: Int
    @Binding var overwrite: Bool
    @Binding var progressText: String
    @Binding var outputs: [String]
    let isRunningTool: Bool
    let preflight: ToolPreflight
    let recentInputs: [String]
    let recentOutputs: [String]
    let chooseInputDirectory: () -> String?
    let chooseOutputDirectory: () -> String?
    let clearRecentInputs: () -> Void
    let clearRecentOutputs: () -> Void
    let pickRecentInput: (String) -> Void
    let pickRecentOutput: (String) -> Void
    let runAction: () -> Void
    let openOutputAction: (String) -> Void
    let copyOutputAction: (String) -> Void

    var body: some View {
        SectionCard("DPX To ProRes", subtitle: "Batch DPX conversion with preflight checks and output actions.") {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                ToolsPreflightSummaryView(preflight: preflight, context: .dpxToProres)

                LabeledPathField(
                    label: "Input Directory",
                    placeholder: "/path/to/dpx_root",
                    text: $inputDir,
                    icon: "folder",
                    browseHelp: "Choose input directory",
                    isDisabled: isRunningTool
                ) {
                    if let path = chooseInputDirectory() {
                        inputDir = path
                    }
                }

                ToolsRecentsMenuRow(
                    title: "Recent Inputs",
                    values: recentInputs,
                    onPick: pickRecentInput,
                    onClear: clearRecentInputs
                )

                LabeledPathField(
                    label: "Output Directory (Optional)",
                    placeholder: "/path/to/prores_output",
                    text: $outputDir,
                    icon: "folder",
                    browseHelp: "Choose output directory",
                    isDisabled: isRunningTool
                ) {
                    if let path = chooseOutputDirectory() {
                        outputDir = path
                    }
                }

                ToolsRecentsMenuRow(
                    title: "Recent Outputs",
                    values: recentOutputs,
                    onPick: pickRecentOutput,
                    onClear: clearRecentOutputs
                )

                HStack(spacing: StopmoUI.Spacing.md) {
                    Stepper("Framerate: \(framerate)", value: $framerate, in: 1 ... 120)
                    Toggle("Overwrite", isOn: $overwrite)
                }

                HStack(spacing: StopmoUI.Spacing.sm) {
                    Button("Run DPX To ProRes", action: runAction)
                        .disabled(isRunningTool || !preflight.ok)

                    if !progressText.isEmpty {
                        StatusChip(label: progressText, tone: .neutral)
                    }
                }

                if !outputs.isEmpty {
                    VStack(alignment: .leading, spacing: StopmoUI.Spacing.xxs) {
                        Text("Outputs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(outputs, id: \.self) { output in
                            HStack(spacing: StopmoUI.Spacing.sm) {
                                Text(output)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Button("Open") {
                                    openOutputAction(output)
                                }
                                Button("Copy") {
                                    copyOutputAction(output)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

}
