import SwiftUI

struct QueueView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.lg) {
            ScreenHeader(
                title: "Queue",
                subtitle: "Recent queue jobs, attempts, and failure reasons."
            ) {
                HStack(spacing: StopmoUI.Spacing.sm) {
                    if let total = state.queueSnapshot?.total {
                        StatusChip(label: "Jobs \(total)", tone: .neutral)
                    }
                    Button("Refresh") {
                        Task { await state.refreshLiveData() }
                    }
                    .disabled(state.isBusy)
                }
            }

            SectionCard("Queue Snapshot") {
                if let queue = state.queueSnapshot {
                    KeyValueRow(key: "DB", value: queue.dbPath)
                    KeyValueRow(key: "Total Jobs", value: "\(queue.total)")

                    ScrollView([.horizontal, .vertical]) {
                        LazyVStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                            headerRow
                            Divider()
                            ForEach(queue.recent) { job in
                                row(job)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    EmptyStateCard(message: "No queue data yet.")
                }
            }
            Spacer()
        }
        .padding(StopmoUI.Spacing.lg)
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            col("ID", width: 60)
            col("State", width: 90)
            col("Shot", width: 140)
            col("Frame", width: 70)
            col("Attempts", width: 80)
            col("Worker", width: 120)
            col("Source", width: 260)
            col("Updated", width: 200)
            col("Error", width: 260)
        }
        .font(.caption.bold())
    }

    private func row(_ job: QueueJobRecord) -> some View {
        HStack(spacing: 10) {
            col("\(job.id)", width: 60)
            stateCell(job.state)
            col(job.shot, width: 140)
            col("\(job.frame)", width: 70)
            col("\(job.attempts)", width: 80)
            col(job.workerId ?? "-", width: 120)
            col((job.source as NSString).lastPathComponent, width: 260)
            col(job.updatedAt, width: 200)
            col(job.lastError ?? "", width: 260)
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

    private func stateCell(_ state: String) -> some View {
        HStack {
            StatusChip(label: state, tone: stateTone(state))
                .frame(width: 90, alignment: .leading)
        }
    }

    private func stateTone(_ value: String) -> StatusTone {
        let normalized = value.lowercased()
        if normalized.contains("failed") {
            return .danger
        }
        if normalized.contains("done") {
            return .success
        }
        if normalized.contains("detected")
            || normalized.contains("decoding")
            || normalized.contains("xform")
            || normalized.contains("dpx_write")
        {
            return .warning
        }
        return .neutral
    }
}
