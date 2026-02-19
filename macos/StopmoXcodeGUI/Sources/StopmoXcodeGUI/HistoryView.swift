import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("History")
                        .font(.title2)
                        .bold()
                    Spacer()
                    Button("Refresh") {
                        Task { await state.refreshHistory() }
                    }
                    .disabled(state.isBusy)
                }

                if let snapshot = state.historySummary {
                    Text("Runs: \(snapshot.count)")
                        .font(.subheadline)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            headerRow
                            Divider()
                            ForEach(snapshot.runs) { run in
                                row(run)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    Text("No history loaded yet.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .onAppear {
            if state.historySummary == nil {
                Task { await state.refreshHistory() }
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            col("Run", width: 90)
            col("Start", width: 220)
            col("End", width: 220)
            col("Jobs", width: 70)
            col("Failed", width: 70)
            col("Shots", width: 200)
            col("Pipeline Hashes", width: 220)
            col("Tool Versions", width: 160)
        }
        .font(.caption.bold())
    }

    private func row(_ run: HistoryRunRecord) -> some View {
        HStack(spacing: 10) {
            col(run.runId, width: 90)
            col(run.startUtc, width: 220)
            col(run.endUtc, width: 220)
            col("\(run.totalJobs)", width: 70)
            col("\(run.failedJobs)", width: 70)
            col(run.shots.joined(separator: ", "), width: 200)
            col(run.pipelineHashes.joined(separator: ", "), width: 220)
            col(run.toolVersions.joined(separator: ", "), width: 160)
        }
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
    }

    private func col(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width, alignment: .leading)
    }
}
