import SwiftUI

struct ShotsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.lg) {
            ScreenHeader(
                title: "Shots",
                subtitle: "Shot-level frame progress and assembly status."
            ) {
                HStack(spacing: StopmoUI.Spacing.sm) {
                    if let count = state.shotsSnapshot?.count {
                        StatusChip(label: "Shots \(count)", tone: .neutral)
                    }
                    Button("Refresh") {
                        Task { await state.refreshLiveData() }
                    }
                    .disabled(state.isBusy)
                }
            }

            SectionCard("Shot Summary") {
                if let snapshot = state.shotsSnapshot {
                    ScrollView([.horizontal, .vertical]) {
                        LazyVStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                            headerRow
                            Divider()
                            ForEach(snapshot.shots) { row in
                                shotRow(row)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    EmptyStateCard(message: "No shot summary yet.")
                }
            }
            Spacer()
        }
        .padding(StopmoUI.Spacing.lg)
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
            shotStateCell(shot.state)
            col("\(shot.totalFrames)", width: 120)
            col("\(shot.doneFrames)", width: 80)
            col("\(shot.failedFrames)", width: 80)
            col("\(shot.inflightFrames)", width: 80)
            progressCell(shot.progressRatio)
            assemblyCell(shot.assemblyState)
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

    private func shotStateCell(_ state: String) -> some View {
        HStack {
            StatusChip(label: state, tone: stateTone(state))
                .frame(width: 90, alignment: .leading)
        }
    }

    private func progressCell(_ ratio: Double) -> some View {
        let pct = Int((ratio * 100.0).rounded())
        return HStack {
            StatusChip(label: "\(pct)%", tone: progressTone(ratio))
                .frame(width: 90, alignment: .leading)
        }
    }

    private func assemblyCell(_ assemblyState: String?) -> some View {
        let text = assemblyState ?? "-"
        return HStack {
            StatusChip(label: text, tone: assemblyTone(text))
                .frame(width: 110, alignment: .leading)
        }
    }

    private func stateTone(_ value: String) -> StatusTone {
        let v = value.lowercased()
        if v.contains("failed") {
            return .danger
        }
        if v.contains("done") {
            return .success
        }
        return .warning
    }

    private func progressTone(_ ratio: Double) -> StatusTone {
        if ratio >= 1.0 {
            return .success
        }
        if ratio <= 0.0 {
            return .neutral
        }
        return .warning
    }

    private func assemblyTone(_ value: String) -> StatusTone {
        let v = value.lowercased()
        if v.contains("done") {
            return .success
        }
        if v.contains("pending") || v.contains("dirty") {
            return .warning
        }
        if v == "-" {
            return .neutral
        }
        return .danger
    }
}
