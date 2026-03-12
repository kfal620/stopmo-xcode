import SwiftUI

/// Top-level Review workspace that keeps Queue and Diagnostics available as advanced surfaces.
struct TriageHubView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Group {
            switch state.selectedTriagePanel {
            case .shots:
                ReviewWorkspaceView()
            case .queue:
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                    advancedWorkspaceToolbar(title: "Queue Workspace")
                    QueueView(embedded: true)
                }
            case .diagnostics:
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                    advancedWorkspaceToolbar(title: "Diagnostics Workspace")
                    LogsDiagnosticsView(embedded: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func advancedWorkspaceToolbar(title: String) -> some View {
        ToolbarStrip(title: title) {
            HStack(spacing: StopmoUI.Spacing.sm) {
                Button("Back to Review") {
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
                } else {
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
