import SwiftUI

struct ToolsTranscodePane: View {
    @Binding var inputPath: String
    @Binding var outputDir: String
    @Binding var resultPath: String
    @Binding var showAdvanced: Bool
    let isRunningTool: Bool
    let preflight: ToolPreflight
    let recentInputs: [String]
    let recentOutputs: [String]
    let chooseInputFile: () -> String?
    let chooseOutputDirectory: () -> String?
    let clearRecentInputs: () -> Void
    let clearRecentOutputs: () -> Void
    let pickRecentInput: (String) -> Void
    let pickRecentOutput: (String) -> Void
    let runAction: () -> Void
    let openResult: () -> Void
    let copyResult: () -> Void
    let pathExists: (String) -> Bool

    var body: some View {
        SectionCard("Transcode One", subtitle: "Single-frame transcode with preflight checks and output actions.") {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                preflightView(preflight, context: .transcodeOne)

                LabeledPathField(
                    label: "Input RAW Frame",
                    placeholder: "/path/to/frame.cr2",
                    text: $inputPath,
                    icon: "folder",
                    browseHelp: "Choose RAW input file",
                    isDisabled: isRunningTool
                ) {
                    if let path = chooseInputFile() {
                        inputPath = path
                    }
                }

                recentMenuRow(
                    title: "Recent Inputs",
                    values: recentInputs,
                    onPick: pickRecentInput,
                    onClear: clearRecentInputs
                )

                DisclosureGroup(isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                        LabeledPathField(
                            label: "Output Override (Optional)",
                            placeholder: "/path/to/output",
                            text: $outputDir,
                            icon: "folder",
                            browseHelp: "Choose output directory override",
                            isDisabled: isRunningTool
                        ) {
                            if let path = chooseOutputDirectory() {
                                outputDir = path
                            }
                        }

                        recentMenuRow(
                            title: "Recent Outputs",
                            values: recentOutputs,
                            onPick: pickRecentOutput,
                            onClear: clearRecentOutputs
                        )
                    }
                    .padding(.top, StopmoUI.Spacing.xs)
                } label: {
                    DisclosureRowLabel(title: "Output Override (Advanced)", isExpanded: $showAdvanced)
                }

                HStack(spacing: StopmoUI.Spacing.sm) {
                    Button("Run Transcode One", action: runAction)
                        .disabled(isRunningTool || !preflight.ok)

                    Button("Open Result", action: openResult)
                        .disabled(resultPath.isEmpty)

                    Button("Copy Result Path", action: copyResult)
                        .disabled(resultPath.isEmpty)

                    if !resultPath.isEmpty {
                        StatusChip(label: "Output Ready", tone: .success)
                    }
                }

                if !resultPath.isEmpty {
                    KeyValueRow(key: "Result", value: resultPath, tone: pathExists(resultPath) ? .success : .neutral)
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
                Button("Clear", action: onClear)
                    .buttonStyle(.borderless)
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
}
