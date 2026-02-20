import SwiftUI

struct LiveMonitorView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.lg) {
                ScreenHeader(
                    title: "Live Monitor",
                    subtitle: "Run the watch service and monitor queue status in real time."
                ) {
                    HStack(spacing: StopmoUI.Spacing.sm) {
                        Button("Start Watch") {
                            Task { await state.startWatchService() }
                        }
                        .disabled(state.isBusy || (state.watchServiceState?.running ?? false))

                        Button("Stop Watch") {
                            Task { await state.stopWatchService() }
                        }
                        .disabled(state.isBusy || !(state.watchServiceState?.running ?? false))

                        Button("Refresh") {
                            Task { await state.refreshLiveData() }
                        }
                        .disabled(state.isBusy)
                    }
                }

                SectionCard("Watch Service") {
                    if let watch = state.watchServiceState {
                        KeyValueRow(
                            key: "Running",
                            value: watch.running ? "yes" : "no",
                            tone: watch.running ? .success : .warning
                        )
                        KeyValueRow(
                            key: "PID",
                            value: watch.pid.map(String.init) ?? "-",
                            tone: watch.running ? .neutral : .warning
                        )
                        KeyValueRow(
                            key: "Started",
                            value: watch.startedAtUtc ?? "-",
                            tone: watch.running ? .neutral : .warning
                        )
                        KeyValueRow(key: "Config", value: watch.configPath)
                        if let launchError = watch.launchError, !launchError.isEmpty {
                            KeyValueRow(key: "Launch Error", value: launchError, tone: .danger)
                        }
                        if watch.startBlocked == true {
                            KeyValueRow(key: "Start Blocked", value: "yes", tone: .danger)
                        }
                        if let logPath = watch.logPath {
                            KeyValueRow(key: "Log", value: logPath)
                        }
                        if let crash = watch.crashRecovery {
                            KeyValueRow(key: "Last Startup", value: crash.lastStartupUtc ?? "-")
                            KeyValueRow(key: "Last Shutdown", value: crash.lastShutdownUtc ?? "-")
                            KeyValueRow(
                                key: "Crash Recovery",
                                value: "reset \(crash.lastInflightResetCount) inflight jobs",
                                tone: crash.lastInflightResetCount == 0 ? .success : .warning
                            )
                        }
                        if let preflight = watch.preflight, !preflight.ok {
                            KeyValueRow(
                                key: "Preflight",
                                value: "blocked: \(preflight.blockers.joined(separator: ","))",
                                tone: .danger
                            )
                        }
                        ProgressView(value: watch.progressRatio)
                            .padding(.top, StopmoUI.Spacing.xs)
                        HStack(spacing: StopmoUI.Spacing.xs) {
                            StatusChip(
                                label: "Progress \(Int((watch.progressRatio * 100.0).rounded()))%",
                                tone: watch.running ? .success : .neutral
                            )
                            StatusChip(label: "Done \(watch.completedFrames)", tone: .success)
                            StatusChip(label: "Inflight \(watch.inflightFrames)", tone: .warning)
                            StatusChip(label: "Total \(watch.totalFrames)", tone: .neutral)
                        }
                    } else {
                        EmptyStateCard(message: "No watch state yet. Click Refresh.")
                    }
                }

                if let queue = state.queueSnapshot {
                    SectionCard("Queue Counts") {
                        let ordered = ["detected", "decoding", "xform", "dpx_write", "done", "failed"]
                        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: StopmoUI.Spacing.xs) {
                            GridRow {
                                Text("State").foregroundStyle(.secondary)
                                Text("Count").foregroundStyle(.secondary)
                            }
                            ForEach(ordered, id: \.self) { key in
                                GridRow {
                                    Text(key)
                                    HStack(spacing: StopmoUI.Spacing.xs) {
                                        Text("\(queue.counts[key, default: 0])")
                                        StatusChip(
                                            label: queueLabel(for: key),
                                            tone: queueTone(for: key, count: queue.counts[key, default: 0])
                                        )
                                    }
                                }
                            }
                        }
                    }
                }

                if let logTail = state.watchServiceState?.logTail, !logTail.isEmpty {
                    SectionCard("Watch Log Tail") {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(logTail.indices, id: \.self) { idx in
                                    Text(logTail[idx])
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .frame(minHeight: 120, maxHeight: 220)
                    }
                }

                SectionCard("Activity") {
                    if state.liveEvents.isEmpty {
                        EmptyStateCard(message: "No activity yet.")
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: StopmoUI.Spacing.xxs) {
                                ForEach(state.liveEvents.indices, id: \.self) { idx in
                                    Text(state.liveEvents[idx])
                                        .font(.system(.caption, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .frame(minHeight: 120, maxHeight: 260)
                    }
                }
            }
            .padding(StopmoUI.Spacing.lg)
        }
    }

    private func queueTone(for state: String, count: Int) -> StatusTone {
        if state == "failed", count > 0 {
            return .danger
        }
        if state == "done", count > 0 {
            return .success
        }
        if count > 0 {
            return .warning
        }
        return .neutral
    }

    private func queueLabel(for state: String) -> String {
        switch state {
        case "failed":
            return "Failed"
        case "done":
            return "Complete"
        default:
            return "Active"
        }
    }
}
