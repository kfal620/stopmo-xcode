import SwiftUI

struct DeliverHubView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.md) {
            LifecycleStageHeader(
                hub: .deliver,
                title: "Deliver",
                subtitle: "Run day-wrap ProRes assembly and review historical runs."
            ) {
                Button("Back to Capture") {
                    state.selectedHub = .capture
                }
            }

            panelPicker

            Group {
                switch state.selectedDeliverPanel {
                case .dayWrap:
                    VStack(alignment: .leading, spacing: StopmoUI.Spacing.md) {
                        deliveryPolicyCard
                        ToolsView(mode: .deliveryOnly, embedded: true)
                    }
                case .runHistory:
                    HistoryView(embedded: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(StopmoUI.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if state.config.watch.outputDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Task { await state.loadConfig() }
            }
        }
    }

    private var panelPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: StopmoUI.Spacing.xs) {
                ForEach(DeliverPanel.allCases) { panel in
                    PanelChipButton(
                        label: panel.rawValue,
                        iconName: panel.iconName,
                        isSelected: state.selectedDeliverPanel == panel,
                        accentColor: LifecycleHub.deliver.accentColor
                    ) {
                        state.selectedDeliverPanel = panel
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var deliveryPolicyCard: some View {
        SectionCard("Assembly Policy", subtitle: "Shot-complete automation remains configurable under Project > Output.") {
            HStack(spacing: StopmoUI.Spacing.sm) {
                StatusChip(
                    label: state.config.output.writeProresOnShotComplete ? "Auto Shot-Complete: Enabled" : "Auto Shot-Complete: Disabled",
                    tone: state.config.output.writeProresOnShotComplete ? .warning : .neutral
                )
                Spacer(minLength: 0)
                Button("Edit in Configure") {
                    state.selectedHub = .configure
                    state.selectedConfigurePanel = .projectSettings
                }
            }
            KeyValueRow(key: "DPX Source Root", value: state.config.watch.outputDir)
        }
    }
}
