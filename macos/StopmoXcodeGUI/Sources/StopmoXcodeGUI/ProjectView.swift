import SwiftUI

struct ProjectView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.lg) {
                ScreenHeader(
                    title: "Project",
                    subtitle: "Edit watch, pipeline, output, and logging settings."
                ) {
                    HStack(spacing: StopmoUI.Spacing.sm) {
                        Button("Reload") {
                            Task { await state.loadConfig() }
                        }
                        .disabled(state.isBusy)

                        Button("Save") {
                            Task { await state.saveConfig() }
                        }
                        .keyboardShortcut("s", modifiers: [.command])
                        .disabled(state.isBusy)
                    }
                }

                watchSection
                pipelineSection
                outputSection
                loggingSection
            }
            .padding(StopmoUI.Spacing.lg)
        }
    }

    private var watchSection: some View {
        SectionCard("Watch Configuration", subtitle: "Source/work/output paths and watch behavior.") {
            fieldRow("Source Directory") {
                textField("Source directory", text: $state.config.watch.sourceDir)
            }
            fieldRow("Working Directory") {
                textField("Working directory", text: $state.config.watch.workingDir)
            }
            fieldRow("Output Directory") {
                textField("Output directory", text: $state.config.watch.outputDir)
            }
            fieldRow("Database Path") {
                textField("DB path", text: $state.config.watch.dbPath)
            }
            fieldRow("Include Extensions") {
                textField("Comma separated extensions", text: includeExtensionsBinding)
            }
            fieldRow("Stable Seconds") {
                numberField("Stable seconds", value: $state.config.watch.stableSeconds)
            }
            fieldRow("Poll Interval Seconds") {
                numberField("Poll interval seconds", value: $state.config.watch.pollIntervalSeconds)
            }
            fieldRow("Scan Interval Seconds") {
                numberField("Scan interval seconds", value: $state.config.watch.scanIntervalSeconds)
            }
            fieldRow("Max Workers") {
                integerField("Max workers", value: $state.config.watch.maxWorkers)
            }
            fieldRow("Shot Complete Seconds") {
                numberField("Shot complete seconds", value: $state.config.watch.shotCompleteSeconds)
            }
            fieldRow("Shot Regex") {
                textField(
                    "Optional shot regex",
                    text: optionalStringBinding(
                        get: { state.config.watch.shotRegex },
                        set: { state.config.watch.shotRegex = $0 }
                    )
                )
            }
        }
    }

    private var pipelineSection: some View {
        SectionCard("Pipeline Configuration", subtitle: "Color transforms, exposure policy, and OCIO settings.") {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                Text("Camera To Reference Matrix")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: StopmoUI.Spacing.xs) {
                        ForEach(0..<3, id: \.self) { col in
                            TextField(
                                "m\(row)\(col)",
                                value: matrixBinding(row: row, col: col),
                                format: .number.precision(.fractionLength(8))
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                        }
                    }
                }
            }

            fieldRow("Exposure Offset Stops") {
                numberField("Exposure offset", value: $state.config.pipeline.exposureOffsetStops)
            }
            toggleRow("Auto Exposure From ISO", isOn: $state.config.pipeline.autoExposureFromIso)
            toggleRow("Auto Exposure From Shutter", isOn: $state.config.pipeline.autoExposureFromShutter)
            fieldRow("Target Shutter Seconds") {
                textField(
                    "Optional shutter seconds",
                    text: optionalDoubleBinding(
                        get: { state.config.pipeline.targetShutterS },
                        set: { state.config.pipeline.targetShutterS = $0 }
                    )
                )
            }
            toggleRow("Auto Exposure From Aperture", isOn: $state.config.pipeline.autoExposureFromAperture)
            fieldRow("Target Aperture F") {
                textField(
                    "Optional aperture",
                    text: optionalDoubleBinding(
                        get: { state.config.pipeline.targetApertureF },
                        set: { state.config.pipeline.targetApertureF = $0 }
                    )
                )
            }
            fieldRow("Contrast") {
                numberField("Contrast", value: $state.config.pipeline.contrast)
            }
            fieldRow("Contrast Pivot Linear") {
                numberField("Contrast pivot linear", value: $state.config.pipeline.contrastPivotLinear)
            }
            toggleRow("Lock WB From First Frame", isOn: $state.config.pipeline.lockWbFromFirstFrame)
            fieldRow("Target EI") {
                integerField("Target EI", value: $state.config.pipeline.targetEi)
            }
            toggleRow("Apply Match LUT", isOn: $state.config.pipeline.applyMatchLut)
            fieldRow("Match LUT Path") {
                textField(
                    "Optional match LUT path",
                    text: optionalStringBinding(
                        get: { state.config.pipeline.matchLutPath },
                        set: { state.config.pipeline.matchLutPath = $0 }
                    )
                )
            }
            toggleRow("Use OCIO", isOn: $state.config.pipeline.useOcio)
            fieldRow("OCIO Config Path") {
                textField(
                    "Optional OCIO config path",
                    text: optionalStringBinding(
                        get: { state.config.pipeline.ocioConfigPath },
                        set: { state.config.pipeline.ocioConfigPath = $0 }
                    )
                )
            }
            fieldRow("OCIO Input Space") {
                textField("OCIO input space", text: $state.config.pipeline.ocioInputSpace)
            }
            fieldRow("OCIO Reference Space") {
                textField("OCIO reference space", text: $state.config.pipeline.ocioReferenceSpace)
            }
            fieldRow("OCIO Output Space") {
                textField("OCIO output space", text: $state.config.pipeline.ocioOutputSpace)
            }
        }
    }

    private var outputSection: some View {
        SectionCard("Output Configuration", subtitle: "Frame outputs, truth frame behavior, and review defaults.") {
            toggleRow("Emit Per Frame JSON", isOn: $state.config.output.emitPerFrameJson)
            toggleRow("Emit Truth Frame Pack", isOn: $state.config.output.emitTruthFramePack)
            fieldRow("Truth Frame Index") {
                integerField("Truth frame index", value: $state.config.output.truthFrameIndex)
            }
            toggleRow("Write Debug TIFF", isOn: $state.config.output.writeDebugTiff)
            toggleRow("Write ProRes On Shot Complete", isOn: $state.config.output.writeProresOnShotComplete)
            fieldRow("Framerate") {
                integerField("Framerate", value: $state.config.output.framerate)
            }
            fieldRow("Show LUT Rec709 Path") {
                textField(
                    "Optional show LUT path",
                    text: optionalStringBinding(
                        get: { state.config.output.showLutRec709Path },
                        set: { state.config.output.showLutRec709Path = $0 }
                    )
                )
            }
        }
    }

    private var loggingSection: some View {
        SectionCard("Logging Configuration") {
            fieldRow("Log Level") {
                textField("Log level", text: $state.config.logLevel)
            }
            fieldRow("Log File") {
                textField(
                    "Optional log file",
                    text: optionalStringBinding(
                        get: { state.config.logFile },
                        set: { state.config.logFile = $0 }
                    )
                )
            }
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

    private var includeExtensionsBinding: Binding<String> {
        Binding<String>(
            get: { state.config.watch.includeExtensions.joined(separator: ", ") },
            set: { newValue in
                state.config.watch.includeExtensions = newValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private func matrixBinding(row: Int, col: Int) -> Binding<Double> {
        Binding<Double>(
            get: {
                guard row < state.config.pipeline.cameraToReferenceMatrix.count,
                      col < state.config.pipeline.cameraToReferenceMatrix[row].count else {
                    return 0.0
                }
                return state.config.pipeline.cameraToReferenceMatrix[row][col]
            },
            set: { newValue in
                guard row < state.config.pipeline.cameraToReferenceMatrix.count,
                      col < state.config.pipeline.cameraToReferenceMatrix[row].count else {
                    return
                }
                state.config.pipeline.cameraToReferenceMatrix[row][col] = newValue
            }
        )
    }

    private func optionalStringBinding(
        get: @escaping () -> String?,
        set: @escaping (String?) -> Void
    ) -> Binding<String> {
        Binding<String>(
            get: { get() ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                set(trimmed.isEmpty ? nil : trimmed)
            }
        )
    }

    private func optionalDoubleBinding(
        get: @escaping () -> Double?,
        set: @escaping (Double?) -> Void
    ) -> Binding<String> {
        Binding<String>(
            get: {
                if let value = get() {
                    return String(value)
                }
                return ""
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    set(nil)
                    return
                }
                if let parsed = Double(trimmed) {
                    set(parsed)
                }
            }
        )
    }
}
