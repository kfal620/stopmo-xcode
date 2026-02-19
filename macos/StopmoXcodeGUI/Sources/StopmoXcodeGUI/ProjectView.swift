import SwiftUI

struct ProjectView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Project")
                        .font(.title2)
                        .bold()
                    Spacer()
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

                Form {
                    watchSection
                    pipelineSection
                    outputSection
                    loggingSection
                }
            }
            .padding(20)
        }
    }

    private var watchSection: some View {
        Section("Watch") {
            TextField("Source Dir", text: $state.config.watch.sourceDir)
            TextField("Working Dir", text: $state.config.watch.workingDir)
            TextField("Output Dir", text: $state.config.watch.outputDir)
            TextField("DB Path", text: $state.config.watch.dbPath)
            TextField("Include Extensions (comma separated)", text: includeExtensionsBinding)
            TextField("Stable Seconds", value: $state.config.watch.stableSeconds, format: .number)
            TextField("Poll Interval Seconds", value: $state.config.watch.pollIntervalSeconds, format: .number)
            TextField("Scan Interval Seconds", value: $state.config.watch.scanIntervalSeconds, format: .number)
            TextField("Max Workers", value: $state.config.watch.maxWorkers, format: .number)
            TextField("Shot Complete Seconds", value: $state.config.watch.shotCompleteSeconds, format: .number)
            TextField("Shot Regex (optional)", text: optionalStringBinding(
                get: { state.config.watch.shotRegex },
                set: { state.config.watch.shotRegex = $0 }
            ))
        }
    }

    private var pipelineSection: some View {
        Section("Pipeline") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Camera To Reference Matrix")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(0..<3, id: \.self) { row in
                    HStack {
                        ForEach(0..<3, id: \.self) { col in
                            TextField(
                                "m\(row)\(col)",
                                value: matrixBinding(row: row, col: col),
                                format: .number.precision(.fractionLength(8))
                            )
                            .frame(width: 120)
                        }
                    }
                }
            }
            TextField("Exposure Offset Stops", value: $state.config.pipeline.exposureOffsetStops, format: .number)
            Toggle("Auto Exposure From ISO", isOn: $state.config.pipeline.autoExposureFromIso)
            Toggle("Auto Exposure From Shutter", isOn: $state.config.pipeline.autoExposureFromShutter)
            TextField("Target Shutter Seconds (optional)", text: optionalDoubleBinding(
                get: { state.config.pipeline.targetShutterS },
                set: { state.config.pipeline.targetShutterS = $0 }
            ))
            Toggle("Auto Exposure From Aperture", isOn: $state.config.pipeline.autoExposureFromAperture)
            TextField("Target Aperture F (optional)", text: optionalDoubleBinding(
                get: { state.config.pipeline.targetApertureF },
                set: { state.config.pipeline.targetApertureF = $0 }
            ))
            TextField("Contrast", value: $state.config.pipeline.contrast, format: .number)
            TextField("Contrast Pivot Linear", value: $state.config.pipeline.contrastPivotLinear, format: .number)
            Toggle("Lock WB From First Frame", isOn: $state.config.pipeline.lockWbFromFirstFrame)
            TextField("Target EI", value: $state.config.pipeline.targetEi, format: .number)
            Toggle("Apply Match LUT", isOn: $state.config.pipeline.applyMatchLut)
            TextField("Match LUT Path (optional)", text: optionalStringBinding(
                get: { state.config.pipeline.matchLutPath },
                set: { state.config.pipeline.matchLutPath = $0 }
            ))
            Toggle("Use OCIO", isOn: $state.config.pipeline.useOcio)
            TextField("OCIO Config Path (optional)", text: optionalStringBinding(
                get: { state.config.pipeline.ocioConfigPath },
                set: { state.config.pipeline.ocioConfigPath = $0 }
            ))
            TextField("OCIO Input Space", text: $state.config.pipeline.ocioInputSpace)
            TextField("OCIO Reference Space", text: $state.config.pipeline.ocioReferenceSpace)
            TextField("OCIO Output Space", text: $state.config.pipeline.ocioOutputSpace)
        }
    }

    private var outputSection: some View {
        Section("Output") {
            Toggle("Emit Per Frame JSON", isOn: $state.config.output.emitPerFrameJson)
            Toggle("Emit Truth Frame Pack", isOn: $state.config.output.emitTruthFramePack)
            TextField("Truth Frame Index", value: $state.config.output.truthFrameIndex, format: .number)
            Toggle("Write Debug TIFF", isOn: $state.config.output.writeDebugTiff)
            Toggle("Write ProRes On Shot Complete", isOn: $state.config.output.writeProresOnShotComplete)
            TextField("Framerate", value: $state.config.output.framerate, format: .number)
            TextField("Show LUT Rec709 Path (optional)", text: optionalStringBinding(
                get: { state.config.output.showLutRec709Path },
                set: { state.config.output.showLutRec709Path = $0 }
            ))
        }
    }

    private var loggingSection: some View {
        Section("Logging") {
            TextField("Log Level", text: $state.config.logLevel)
            TextField("Log File (optional)", text: optionalStringBinding(
                get: { state.config.logFile },
                set: { state.config.logFile = $0 }
            ))
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
