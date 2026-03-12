import SwiftUI

/// Top-level delivery workspace container that switches between day-wrap controls and run history.
struct DeliverHubView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            switch state.selectedDeliverPanel {
            case .dayWrap:
                DeliveryDayWrapView()
            case .runHistory:
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                    ToolbarStrip(title: "Run History") {
                        HStack(spacing: StopmoUI.Spacing.sm) {
                            Button("Back to Deliver") {
                                state.selectedDeliverPanel = .dayWrap
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            Spacer(minLength: 0)
                        }
                    }
                    HistoryView(embedded: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if state.config.watch.outputDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Task { await state.loadConfig() }
            }
        }
    }
}
