import SwiftUI

struct TriageHubView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            Group {
                switch state.selectedTriagePanel {
                case .shots:
                    TriageShotHealthBoardView()
                case .queue:
                    VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                        triageWorkspaceToolbar(title: "Queue Workspace")
                        QueueView(embedded: true)
                    }
                case .diagnostics:
                    VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                        triageWorkspaceToolbar(title: "Diagnostics Workspace")
                        LogsDiagnosticsView(embedded: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, StopmoUI.Spacing.md)
        .padding(.top, StopmoUI.Spacing.xs)
        .padding(.bottom, StopmoUI.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func triageWorkspaceToolbar(title: String) -> some View {
        ToolbarStrip(title: title) {
            HStack(spacing: StopmoUI.Spacing.sm) {
                Button("Back to Shot Board") {
                    state.selectedTriagePanel = .shots
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                if state.selectedTriagePanel == .queue {
                    Button("Open Diagnostics") {
                        state.selectedTriagePanel = .diagnostics
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if state.selectedTriagePanel == .diagnostics {
                    Button("Open Queue") {
                        state.selectedTriagePanel = .queue
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
