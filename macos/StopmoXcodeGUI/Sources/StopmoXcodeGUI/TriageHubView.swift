import SwiftUI

struct TriageHubView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.md) {
            LifecycleStageHeader(
                hub: .triage,
                title: "Triage",
                subtitle: "Review shots, recover queue failures, and inspect diagnostics."
            ) {
                Button("Open Deliver (Day Wrap)") {
                    state.selectedHub = .deliver
                    state.selectedDeliverPanel = .dayWrap
                }
            }

            panelPicker

            Group {
                switch state.selectedTriagePanel {
                case .shots:
                    ShotsView(embedded: true)
                case .queue:
                    QueueView(embedded: true)
                case .diagnostics:
                    LogsDiagnosticsView(embedded: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(StopmoUI.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var panelPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: StopmoUI.Spacing.xs) {
                ForEach(TriagePanel.allCases) { panel in
                    PanelChipButton(
                        label: panel.rawValue,
                        iconName: panel.iconName,
                        isSelected: state.selectedTriagePanel == panel,
                        accentColor: LifecycleHub.triage.accentColor
                    ) {
                        state.selectedTriagePanel = panel
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
