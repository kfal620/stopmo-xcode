import SwiftUI

struct DeliverHubView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            LifecycleStageHeader(
                hub: .deliver,
                title: "Deliver",
                subtitle: "Select ready shots, run ProRes delivery, and monitor run status.",
                style: .compact,
                showSubtitle: false
            ) {
                Button("Back to Capture") {
                    state.selectedHub = .capture
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            panelPicker

            Group {
                switch state.selectedDeliverPanel {
                case .dayWrap:
                    DeliveryDayWrapView()
                case .runHistory:
                    HistoryView(embedded: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, StopmoUI.Spacing.md)
        .padding(.top, StopmoUI.Spacing.sm)
        .padding(.bottom, StopmoUI.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if state.config.watch.outputDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Task { await state.loadConfig() }
            }
        }
    }

    private var panelPicker: some View {
        ToolbarStrip(title: "Deliver Surfaces") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: StopmoUI.Spacing.xxs) {
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
    }
}
