import SwiftUI

struct ConfigureHubView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.md) {
            LifecycleStageHeader(
                hub: .configure,
                title: "Configure",
                subtitle: "Workspace health, project settings, and calibration utilities."
            )

            panelPicker

            Group {
                switch state.selectedConfigurePanel {
                case .workspaceHealth:
                    SetupView(embedded: true)
                case .projectSettings:
                    ProjectView(embedded: true)
                case .calibration:
                    ToolsView(mode: .utilitiesOnly, embedded: true)
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
                ForEach(ConfigurePanel.allCases) { panel in
                    PanelChipButton(
                        label: panel.rawValue,
                        iconName: panel.iconName,
                        isSelected: state.selectedConfigurePanel == panel,
                        accentColor: LifecycleHub.configure.accentColor
                    ) {
                        state.selectedConfigurePanel = panel
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
