import SwiftUI

struct CaptureHubView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            LifecycleStageHeader(
                hub: .capture,
                title: "Capture",
                subtitle: "Run watch service and monitor ingest throughput in real time.",
                style: .compact,
                showSubtitle: false
            )

            ToolbarStrip(title: "Capture Actions") {
                HStack(spacing: StopmoUI.Spacing.sm) {
                    LiveStateChip(
                        isRunning: state.watchServiceState?.running ?? false,
                        runningLabel: "Live",
                        idleLabel: "Idle"
                    )
                    Spacer(minLength: 0)
                    Button("Open Triage") {
                        state.selectedHub = .triage
                        state.selectedTriagePanel = .shots
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Button("Open Deliver") {
                        state.selectedHub = .deliver
                        state.selectedDeliverPanel = .dayWrap
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            LiveMonitorView(embedded: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, StopmoUI.Spacing.md)
        .padding(.top, StopmoUI.Spacing.sm)
        .padding(.bottom, StopmoUI.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
