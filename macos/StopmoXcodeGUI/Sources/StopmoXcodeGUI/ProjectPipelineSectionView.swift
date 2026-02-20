import SwiftUI

struct ProjectPipelineSectionView: View {
    @Binding var pipeline: StopmoConfigDocument.Pipeline
    let isBusy: Bool
    let onResetIdentity: () -> Void
    let onPasteMatrix: () -> Void
    let onCopyMatrix: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            matrixEditor

            fieldRow("Exposure Offset Stops") {
                numberField("Exposure offset", value: $pipeline.exposureOffsetStops)
            }
            toggleRow("Auto Exposure From ISO", isOn: $pipeline.autoExposureFromIso)
            toggleRow("Auto Exposure From Shutter", isOn: $pipeline.autoExposureFromShutter)
            fieldRow("Target Shutter Seconds") {
                textField("Optional shutter seconds", text: targetShutterBinding)
            }
            toggleRow("Auto Exposure From Aperture", isOn: $pipeline.autoExposureFromAperture)
            fieldRow("Target Aperture F") {
                textField("Optional aperture", text: targetApertureBinding)
            }
            fieldRow("Contrast") {
                numberField("Contrast", value: $pipeline.contrast)
            }
            fieldRow("Contrast Pivot Linear") {
                numberField("Contrast pivot linear", value: $pipeline.contrastPivotLinear)
            }
            toggleRow("Lock WB From First Frame", isOn: $pipeline.lockWbFromFirstFrame)
            fieldRow("Target EI") {
                integerField("Target EI", value: $pipeline.targetEi)
            }
            toggleRow("Apply Match LUT", isOn: $pipeline.applyMatchLut)
            fieldRow("Match LUT Path") {
                textField("Optional match LUT path", text: matchLutPathBinding)
            }
            toggleRow("Use OCIO", isOn: $pipeline.useOcio)
            fieldRow("OCIO Config Path") {
                textField("Optional OCIO config path", text: ocioConfigPathBinding)
            }
            fieldRow("OCIO Input Space") {
                textField("OCIO input space", text: $pipeline.ocioInputSpace)
            }
            fieldRow("OCIO Reference Space") {
                textField("OCIO reference space", text: $pipeline.ocioReferenceSpace)
            }
            fieldRow("OCIO Output Space") {
                textField("OCIO output space", text: $pipeline.ocioOutputSpace)
            }
        }
    }

    private var matrixEditor: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            HStack {
                Text("Camera To Reference Matrix")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset Identity") {
                    onResetIdentity()
                }
                .disabled(isBusy)
                Button("Paste 3x3") {
                    onPasteMatrix()
                }
                .disabled(isBusy)
                Button("Copy 3x3") {
                    onCopyMatrix()
                }
                .disabled(isBusy)
            }
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
    }

    private var targetShutterBinding: Binding<String> {
        optionalDoubleBinding(
            get: { pipeline.targetShutterS },
            set: { pipeline.targetShutterS = $0 }
        )
    }

    private var targetApertureBinding: Binding<String> {
        optionalDoubleBinding(
            get: { pipeline.targetApertureF },
            set: { pipeline.targetApertureF = $0 }
        )
    }

    private var matchLutPathBinding: Binding<String> {
        optionalStringBinding(
            get: { pipeline.matchLutPath },
            set: { pipeline.matchLutPath = $0 }
        )
    }

    private var ocioConfigPathBinding: Binding<String> {
        optionalStringBinding(
            get: { pipeline.ocioConfigPath },
            set: { pipeline.ocioConfigPath = $0 }
        )
    }

    private func matrixBinding(row: Int, col: Int) -> Binding<Double> {
        Binding<Double>(
            get: {
                guard row < pipeline.cameraToReferenceMatrix.count,
                      col < pipeline.cameraToReferenceMatrix[row].count else {
                    return 0.0
                }
                return pipeline.cameraToReferenceMatrix[row][col]
            },
            set: { newValue in
                guard row < pipeline.cameraToReferenceMatrix.count,
                      col < pipeline.cameraToReferenceMatrix[row].count else {
                    return
                }
                pipeline.cameraToReferenceMatrix[row][col] = newValue
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
