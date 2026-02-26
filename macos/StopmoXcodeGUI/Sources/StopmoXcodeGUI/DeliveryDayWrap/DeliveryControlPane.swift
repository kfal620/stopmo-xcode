import SwiftUI

struct DeliveryControlPaneView: View {
    let availableHeight: CGFloat
    let runState: DeliveryRunState
    let envelope: ToolOperationEnvelope?

    @Binding var showRunEvents: Bool
    @Binding var showBatchConfig: Bool
    @Binding var showAdvancedDiagnostics: Bool

    @Binding var dpxInputDir: String
    @Binding var dpxOutputDir: String
    @Binding var dpxFramerate: Int
    @Binding var dpxOverwrite: Bool

    let inputReady: Bool
    let isBusy: Bool
    let onChooseDirectoryPath: () -> String?
    let onRunBatch: () -> Void
    let onOpenLatestOutput: () -> Void
    let onCopyLatestOutput: () -> Void
    let onOpenRunHistory: () -> Void
    let onOpenTriageDiagnostics: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.md) {
                runStatusPanel
                runTimelinePanel
                batchConfigPanel
                advancedPanel
            }
        }
        .frame(maxHeight: availableHeight - DeliveryLayoutMetrics.rightPaneScrollMaxHeightCompensation)
    }

    private var runStatusPanel: some View {
        SectionCard(
            "Run Status",
            subtitle: "Live progress and latest output for delivery operations.",
            density: .compact,
            surfaceLevel: .panel,
            chrome: .quiet,
            showSubtitle: false
        ) {
            DeliveryRunStatusPanel(
                runState: runState,
                openLatestOutput: onOpenLatestOutput,
                copyLatestOutput: onCopyLatestOutput
            )
        }
    }

    private var runTimelinePanel: some View {
        SectionCard(
            "Run Timeline",
            subtitle: "Verbose event log for the current/last delivery run.",
            density: .compact,
            surfaceLevel: .panel,
            chrome: .quiet,
            showSubtitle: false
        ) {
            DeliveryRunEventsPanel(
                isExpanded: $showRunEvents,
                events: runState.events,
                maxHeight: DeliveryLayoutMetrics.runEventsHeight
            )
        }
    }

    private var batchConfigPanel: some View {
        SectionCard(
            "DPX -> ProRes Batch",
            subtitle: "Collapsed by default to reduce clutter.",
            density: .compact,
            surfaceLevel: .panel,
            chrome: .quiet,
            showSubtitle: false
        ) {
            BatchConfigDisclosurePanel(
                isExpanded: $showBatchConfig,
                dpxInputDir: $dpxInputDir,
                dpxOutputDir: $dpxOutputDir,
                dpxFramerate: $dpxFramerate,
                dpxOverwrite: $dpxOverwrite,
                inputReady: inputReady,
                isBusy: isBusy,
                chooseDirectoryPath: onChooseDirectoryPath,
                runBatchAction: onRunBatch
            )
        }
    }

    private var advancedPanel: some View {
        SectionCard(
            "Advanced",
            subtitle: "Delivery diagnostics and fast navigation to full workspaces.",
            density: .compact,
            surfaceLevel: .panel,
            chrome: .quiet,
            showSubtitle: false
        ) {
            DisclosureGroup(isExpanded: $showAdvancedDiagnostics) {
                DeliveryAdvancedDiagnosticsPanel(
                    envelope: envelope,
                    runEvents: runState.events,
                    openRunHistory: onOpenRunHistory,
                    openTriageDiagnostics: onOpenTriageDiagnostics
                )
                .padding(.top, StopmoUI.Spacing.xs)
            } label: {
                DisclosureRowLabel(title: "Show Day Wrap Diagnostics", isExpanded: $showAdvancedDiagnostics)
            }
        }
    }
}

private struct DeliveryRunStatusPanel: View {
    let runState: DeliveryRunState
    let openLatestOutput: () -> Void
    let copyLatestOutput: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            HStack(spacing: StopmoUI.Spacing.sm) {
                StatusChip(label: runState.status.rawValue, tone: toneForStatus(runState.status), density: .compact)
                StatusChip(label: runState.kind.rawValue, tone: .neutral, density: .compact)
                StatusChip(label: "\(runState.completed)/\(runState.total)", tone: .neutral, density: .compact)
                if runState.failed > 0 {
                    StatusChip(label: "Failed \(runState.failed)", tone: .danger, density: .compact)
                }
                Spacer(minLength: 0)
            }

            progressHeaderBar

            Text(runState.activeLabel.isEmpty ? "No active delivery" : runState.activeLabel)
                .metadataTextStyle(.secondary)

            HStack(spacing: StopmoUI.Spacing.xs) {
                if let output = runState.latestOutputs.first {
                    Text(output)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(output)
                    Button("Open", action: openLatestOutput)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Copy", action: copyLatestOutput)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else {
                    Text("No output generated yet.")
                        .metadataTextStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var progressHeaderBar: some View {
        if runState.status == .running && runState.total == 0 {
            ProgressView()
                .controlSize(.small)
        } else {
            ProgressView(value: min(1.0, max(0.0, runState.progress)))
                .controlSize(.small)
        }
    }

    private func toneForStatus(_ status: DeliveryRunStatus) -> StatusTone {
        switch status {
        case .idle:
            return .neutral
        case .running:
            return .warning
        case .succeeded:
            return .success
        case .partial:
            return .warning
        case .failed:
            return .danger
        }
    }
}

private struct DeliveryRunEventsPanel: View {
    @Binding var isExpanded: Bool
    let events: [DeliveryRunEvent]
    let maxHeight: CGFloat

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if events.isEmpty {
                EmptyStateCard(message: "No delivery events yet.")
                    .padding(.top, StopmoUI.Spacing.xs)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                        ForEach(events) { event in
                            HStack(alignment: .top, spacing: StopmoUI.Spacing.sm) {
                                DeliveryEventToneBadge(
                                    tone: toneForEvent(event),
                                    symbolName: symbolForEvent(event)
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title)
                                        .font(.caption.weight(.semibold))
                                    Text(event.detail)
                                        .metadataTextStyle(.tertiary)
                                    if let shotName = event.shotName, !shotName.isEmpty {
                                        Text(deliveryTimelineFilename(shotName))
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(AppVisualTokens.textSecondary)
                                    }
                                }
                                Spacer(minLength: 0)
                                Text(deliveryShortTimeLabel(event.timestampUtc))
                                    .metadataTextStyle(.tertiary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.top, StopmoUI.Spacing.xs)
                }
                .frame(maxHeight: maxHeight)
            }
        } label: {
            DisclosureRowLabel(title: "Show Events (\(events.count))", isExpanded: $isExpanded)
        }
    }

    private func toneForEvent(_ event: DeliveryRunEvent) -> StatusTone {
        if event.title == "Selected Delivery Started" {
            return .neutral
        }
        switch event.tone {
        case .neutral:
            return .neutral
        case .success:
            return .success
        case .warning:
            return .warning
        case .danger:
            return .danger
        }
    }

    private func symbolForEvent(_ event: DeliveryRunEvent) -> String {
        switch event.tone {
        case .neutral:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return event.title == "Selected Delivery Started" ? "info.circle.fill" : "exclamationmark.triangle.fill"
        case .danger:
            return "xmark.octagon.fill"
        }
    }
}

private struct DeliveryEventToneBadge: View {
    let tone: StatusTone
    let symbolName: String

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tone.foreground)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tone.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.75)
            )
            .accessibilityHidden(true)
    }
}

private struct BatchConfigDisclosurePanel: View {
    @Binding var isExpanded: Bool
    @Binding var dpxInputDir: String
    @Binding var dpxOutputDir: String
    @Binding var dpxFramerate: Int
    @Binding var dpxOverwrite: Bool
    let inputReady: Bool
    let isBusy: Bool
    let chooseDirectoryPath: () -> String?
    let runBatchAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: StopmoUI.Spacing.xs) {
                    StatusChip(label: inputReady ? "Input Ready" : "Input Missing", tone: inputReady ? .success : .danger, density: .compact)
                    StatusChip(label: dpxOutputDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Output: default" : "Output: override", tone: .neutral, density: .compact)
                    StatusChip(label: "\(dpxFramerate) fps", tone: .neutral, density: .compact)
                    StatusChip(label: dpxOverwrite ? "Overwrite on" : "Overwrite off", tone: dpxOverwrite ? .warning : .neutral, density: .compact)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: StopmoUI.Spacing.xs) {
                        StatusChip(label: inputReady ? "Input Ready" : "Input Missing", tone: inputReady ? .success : .danger, density: .compact)
                        StatusChip(label: dpxOutputDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Output: default" : "Output: override", tone: .neutral, density: .compact)
                        StatusChip(label: "\(dpxFramerate) fps", tone: .neutral, density: .compact)
                        StatusChip(label: dpxOverwrite ? "Overwrite on" : "Overwrite off", tone: dpxOverwrite ? .warning : .neutral, density: .compact)
                    }
                }
            }

            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                    LabeledPathField(
                        label: "Input Directory",
                        placeholder: "/path/to/dpx_root",
                        text: $dpxInputDir,
                        icon: "folder",
                        browseHelp: "Choose input directory",
                        isDisabled: isBusy
                    ) {
                        if let path = chooseDirectoryPath() {
                            dpxInputDir = path
                        }
                    }

                    LabeledPathField(
                        label: "Output Directory (Optional)",
                        placeholder: "/path/to/prores_output",
                        text: $dpxOutputDir,
                        icon: "folder",
                        browseHelp: "Choose output directory",
                        isDisabled: isBusy
                    ) {
                        if let path = chooseDirectoryPath() {
                            dpxOutputDir = path
                        }
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: StopmoUI.Spacing.sm) {
                            Stepper("Framerate: \(dpxFramerate)", value: $dpxFramerate, in: 1 ... 120)
                                .frame(maxWidth: 220)
                            Toggle("Overwrite", isOn: $dpxOverwrite)
                                .frame(maxWidth: 140)
                            Spacer(minLength: 0)
                            Button("Run Day Wrap Batch", action: runBatchAction)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(isBusy || !inputReady)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Stepper("Framerate: \(dpxFramerate)", value: $dpxFramerate, in: 1 ... 120)
                            Toggle("Overwrite", isOn: $dpxOverwrite)
                            Button("Run Day Wrap Batch", action: runBatchAction)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(isBusy || !inputReady)
                        }
                    }
                }
                .padding(.top, StopmoUI.Spacing.xs)
            } label: {
                DisclosureRowLabel(title: "Batch Paths & Settings", isExpanded: $isExpanded)
            }
        }
    }
}

private struct DeliveryAdvancedDiagnosticsPanel: View {
    let envelope: ToolOperationEnvelope?
    let runEvents: [DeliveryRunEvent]
    let openRunHistory: () -> Void
    let openTriageDiagnostics: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            HStack(spacing: StopmoUI.Spacing.xs) {
                StatusChip(label: "Run Events \(runEvents.count)", tone: .neutral, density: .compact)
                StatusChip(label: "Envelope Events \(envelope?.events.count ?? 0)", tone: .neutral, density: .compact)
                Spacer(minLength: 0)
            }

            if recentRows.isEmpty {
                EmptyStateCard(message: "No diagnostics events available yet.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(recentRows.enumerated()), id: \.offset) { _, row in
                            HStack(alignment: .top, spacing: StopmoUI.Spacing.sm) {
                                StatusChip(label: row.kind, tone: row.tone, density: .compact)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title)
                                        .font(.caption.weight(.semibold))
                                    Text(row.detail)
                                        .metadataTextStyle(.tertiary)
                                }
                                Spacer(minLength: 0)
                                Text(row.time)
                                    .metadataTextStyle(.tertiary)
                            }
                        }
                    }
                }
                .frame(maxHeight: DeliveryLayoutMetrics.diagnosticsListMaxHeight)
            }

            HStack(spacing: StopmoUI.Spacing.xs) {
                Button("Open Run History", action: openRunHistory)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Open Triage Diagnostics", action: openTriageDiagnostics)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private var recentRows: [(kind: String, tone: StatusTone, title: String, detail: String, time: String)] {
        let runRows = runEvents.prefix(DeliveryLayoutMetrics.diagnosticsMaxRows).map { event in
            (
                "run",
                toneForRunEvent(event.tone),
                event.title,
                event.detail,
                deliveryShortTimeLabel(event.timestampUtc)
            )
        }

        let envelopeRows: [(kind: String, tone: StatusTone, title: String, detail: String, time: String)] =
            (envelope?.events ?? []).prefix(DeliveryLayoutMetrics.diagnosticsMaxRows).map { event in
                let title = event.eventType.isEmpty ? "event" : event.eventType
                let detail = event.message?.isEmpty == false ? (event.message ?? "") : "Operation \(event.operationId)"
                return ("op", toneForEnvelopeEvent(title), title, detail, deliveryShortTimeLabel(event.timestampUtc))
            }

        return Array((runRows + envelopeRows).prefix(DeliveryLayoutMetrics.diagnosticsMaxRows))
    }

    private func toneForRunEvent(_ tone: DeliveryRunEventTone) -> StatusTone {
        switch tone {
        case .neutral:
            return .neutral
        case .success:
            return .success
        case .warning:
            return .warning
        case .danger:
            return .danger
        }
    }

    private func toneForEnvelopeEvent(_ eventType: String) -> StatusTone {
        let lower = eventType.lowercased()
        if lower.contains("fail") || lower.contains("error") {
            return .danger
        }
        if lower.contains("done") || lower.contains("complete") || lower.contains("success") {
            return .success
        }
        if lower.contains("start") || lower.contains("progress") {
            return .warning
        }
        return .neutral
    }
}
