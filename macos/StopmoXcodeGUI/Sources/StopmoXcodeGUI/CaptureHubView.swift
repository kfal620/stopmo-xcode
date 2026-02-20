import SwiftUI

struct CaptureHubView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.md) {
            LifecycleStageHeader(
                hub: .capture,
                title: "Capture",
                subtitle: "Run watch service and monitor ingest throughput in real time."
            ) {
                HStack(spacing: StopmoUI.Spacing.xs) {
                    Button("Open Triage") {
                        state.selectedHub = .triage
                        state.selectedTriagePanel = .shots
                    }
                    Button("Open Deliver") {
                        state.selectedHub = .deliver
                        state.selectedDeliverPanel = .dayWrap
                    }
                }
            }

            HStack(spacing: StopmoUI.Spacing.sm) {
                StatusChip(label: "Panel", tone: .neutral)
                StatusChip(label: "Live Capture", tone: .success)
                Spacer(minLength: 0)
            }

            LiveMonitorView(embedded: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(StopmoUI.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
