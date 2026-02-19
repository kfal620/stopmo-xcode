import SwiftUI

struct ShotsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Shots")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("Refresh") {
                    Task { await state.refreshLiveData() }
                }
                .disabled(state.isBusy)
            }

            if let snapshot = state.shotsSnapshot {
                Text("Shots: \(snapshot.count)")
                    .font(.subheadline)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        headerRow
                        Divider()
                        ForEach(snapshot.shots) { row in
                            shotRow(row)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Text("No shot summary yet.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            col("Shot", width: 160)
            col("State", width: 90)
            col("Frames", width: 120)
            col("Done", width: 80)
            col("Failed", width: 80)
            col("Inflight", width: 80)
            col("Progress", width: 90)
            col("Assembly", width: 110)
            col("Updated", width: 220)
            col("Output MOV", width: 280)
        }
        .font(.caption.bold())
    }

    private func shotRow(_ shot: ShotSummaryRow) -> some View {
        HStack(spacing: 10) {
            col(shot.shotName, width: 160)
            col(shot.state, width: 90)
            col("\(shot.totalFrames)", width: 120)
            col("\(shot.doneFrames)", width: 80)
            col("\(shot.failedFrames)", width: 80)
            col("\(shot.inflightFrames)", width: 80)
            col("\(Int((shot.progressRatio * 100.0).rounded()))%", width: 90)
            col(shot.assemblyState ?? "-", width: 110)
            col(shot.lastUpdatedAt ?? "-", width: 220)
            col(shot.outputMovPath ?? "-", width: 280)
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
