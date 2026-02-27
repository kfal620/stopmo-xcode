import SwiftUI

struct ToolsMatrixPane: View {
    @Binding var inputPath: String
    @Binding var cameraMake: String
    @Binding var cameraModel: String
    @Binding var writeJsonPath: String
    @Binding var confidence: String
    @Binding var summary: [String]
    @Binding var showAdvanced: Bool
    let isRunningTool: Bool
    let preflight: ToolPreflight
    let recentInputs: [String]
    let recentReports: [String]
    let latestMatrix: [[Double]]?
    let chooseInputFile: () -> String?
    let chooseReportPath: () -> String?
    let clearRecentInputs: () -> Void
    let clearRecentReports: () -> Void
    let pickRecentInput: (String) -> Void
    let pickRecentReport: (String) -> Void
    let runAction: () -> Void
    let applyAction: () -> Void
    let copyAction: () -> Void
    let openReportAction: () -> Void

    var body: some View {
        SectionCard("Suggest Matrix", subtitle: "Estimate camera matrix with confidence/warnings and apply to project config.") {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                preflightView(preflight, context: .suggestMatrix)

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
                        HStack(spacing: StopmoUI.Spacing.sm) {
                            TextField("Camera make override (optional)", text: $cameraMake)
                                .textFieldStyle(.roundedBorder)
                            TextField("Camera model override (optional)", text: $cameraModel)
                                .textFieldStyle(.roundedBorder)
                        }
                        .frame(maxWidth: 760)

                        LabeledPathField(
                            label: "JSON Report Path (Optional)",
                            placeholder: "/path/to/matrix_report.json",
                            text: $writeJsonPath,
                            icon: "doc.badge.plus",
                            browseHelp: "Choose JSON report output path",
                            isDisabled: isRunningTool
                        ) {
                            if let path = chooseReportPath() {
                                writeJsonPath = path
                            }
                        }

                        recentMenuRow(
                            title: "Recent Reports",
                            values: recentReports,
                            onPick: pickRecentReport,
                            onClear: clearRecentReports
                        )
                    }
                    .padding(.top, StopmoUI.Spacing.xs)
                } label: {
                    DisclosureRowLabel(
                        title: "Camera Overrides & JSON Report (Advanced)",
                        isExpanded: $showAdvanced
                    )
                }

                HStack(spacing: StopmoUI.Spacing.sm) {
                    Button("Run Suggest Matrix", action: runAction)
                        .disabled(isRunningTool || !preflight.ok)

                    Button("Apply Matrix To Project", action: applyAction)
                        .disabled(isRunningTool || latestMatrix == nil)

                    Button("Copy Matrix", action: copyAction)
                        .disabled(latestMatrix == nil)

                    Button("Open Report", action: openReportAction)
                        .disabled(writeJsonPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if !confidence.isEmpty {
                        StatusChip(label: "Confidence \(confidence)", tone: .neutral)
                    }
                }

                if let matrix = latestMatrix {
                    VStack(alignment: .leading, spacing: StopmoUI.Spacing.xxs) {
                        Text("Suggested Matrix")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(matrix.indices, id: \.self) { idx in
                            Text(matrix[idx].map { String(format: "%.8f", $0) }.joined(separator: "  "))
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }

                if !summary.isEmpty {
                    VStack(alignment: .leading, spacing: StopmoUI.Spacing.xxs) {
                        Text("Result Summary")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(summary.indices, id: \.self) { idx in
                            Text(summary[idx])
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
