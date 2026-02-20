import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.lg) {
                ScreenHeader(
                    title: "History",
                    subtitle: "Past run summaries with reproducibility metadata."
                ) {
                    HStack(spacing: StopmoUI.Spacing.sm) {
                        if let count = state.historySummary?.count {
                            StatusChip(label: "Runs \(count)", tone: .neutral)
                        }
                        Button("Refresh") {
                            Task { await state.refreshHistory() }
                        }
                        .disabled(state.isBusy)
                    }
                }

                SectionCard("Run History") {
                    if let snapshot = state.historySummary {
                        ScrollView([.horizontal, .vertical]) {
                            LazyVStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                                headerRow
                                Divider()
                                ForEach(snapshot.runs) { run in
                                    row(run)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        EmptyStateCard(message: "No history loaded yet.")
                    }
                }
            }
            .padding(StopmoUI.Spacing.lg)
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
            jobsCell(run.totalJobs)
            failedCell(run.failedJobs)
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

    private func jobsCell(_ total: Int) -> some View {
        HStack {
            StatusChip(label: "\(total)", tone: total > 0 ? .neutral : .warning)
                .frame(width: 70, alignment: .leading)
        }
    }

    private func failedCell(_ failed: Int) -> some View {
        HStack {
            StatusChip(label: "\(failed)", tone: failed > 0 ? .danger : .success)
                .frame(width: 70, alignment: .leading)
        }
    }
}
