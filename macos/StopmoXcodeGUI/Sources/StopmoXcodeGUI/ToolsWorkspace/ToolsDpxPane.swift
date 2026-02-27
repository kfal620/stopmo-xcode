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
                preflightView(preflight, context: .dpxToProres)

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

                recentMenuRow(
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

                recentMenuRow(
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
