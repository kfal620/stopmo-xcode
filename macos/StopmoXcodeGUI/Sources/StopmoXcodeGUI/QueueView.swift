import SwiftUI

struct QueueView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Queue")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("Refresh") {
                    Task { await state.refreshLiveData() }
                }
                .disabled(state.isBusy)
            }

            if let queue = state.queueSnapshot {
                Text("DB: \(queue.dbPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("Total Jobs: \(queue.total)")
                    .font(.subheadline)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        headerRow
                        Divider()
                        ForEach(queue.recent) { job in
                            row(job)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Text("No queue data yet.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
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
            col(job.state, width: 90)
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
}
