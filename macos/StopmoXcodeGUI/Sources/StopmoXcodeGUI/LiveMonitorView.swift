import SwiftUI

struct LiveMonitorView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Live Monitor")
                        .font(.title2)
                        .bold()
                    Spacer()
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

                GroupBox("Watch Service") {
                    if let watch = state.watchServiceState {
                        VStack(alignment: .leading, spacing: 6) {
                            statusLine("Running", watch.running ? "yes" : "no", ok: watch.running)
                            statusLine("PID", watch.pid.map(String.init) ?? "-", ok: watch.running)
                            statusLine("Started", watch.startedAtUtc ?? "-", ok: watch.running)
                            statusLine("Config", watch.configPath, ok: true)
                            if let launchError = watch.launchError, !launchError.isEmpty {
                                statusLine("Launch Error", launchError, ok: false)
                            }
                            if watch.startBlocked == true {
                                statusLine("Start Blocked", "yes", ok: false)
                            }
                            if let logPath = watch.logPath {
                                statusLine("Log", logPath, ok: true)
                            }
                            if let crash = watch.crashRecovery {
                                statusLine("Last Startup", crash.lastStartupUtc ?? "-", ok: true)
                                statusLine("Last Shutdown", crash.lastShutdownUtc ?? "-", ok: true)
                                statusLine(
                                    "Crash Recovery",
                                    "reset \(crash.lastInflightResetCount) inflight jobs",
                                    ok: crash.lastInflightResetCount == 0
                                )
                            }
                            if let preflight = watch.preflight, !preflight.ok {
                                statusLine("Preflight", "blocked: \(preflight.blockers.joined(separator: ","))", ok: false)
                            }
                            ProgressView(value: watch.progressRatio)
                                .padding(.top, 4)
                            Text("Progress \(Int((watch.progressRatio * 100.0).rounded()))% • completed \(watch.completedFrames) / total \(watch.totalFrames)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    } else {
                        Text("No watch state yet. Click Refresh.")
                            .foregroundStyle(.secondary)
                    }
                }

                if let queue = state.queueSnapshot {
                    GroupBox("Queue Counts") {
                        let ordered = ["detected", "decoding", "xform", "dpx_write", "done", "failed"]
                        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                            GridRow {
                                Text("State").foregroundStyle(.secondary)
                                Text("Count").foregroundStyle(.secondary)
                            }
                            ForEach(ordered, id: \.self) { key in
                                GridRow {
                                    Text(key)
                                    Text("\(queue.counts[key, default: 0])")
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                if let logTail = state.watchServiceState?.logTail, !logTail.isEmpty {
                    GroupBox("Watch Log Tail") {
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

                GroupBox("Activity") {
                    if state.liveEvents.isEmpty {
                        Text("No activity yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
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
            .padding(20)
        }
    }

    private func statusLine(_ key: String, _ value: String, ok: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .frame(width: 80, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(ok ? .primary : .secondary)
                .textSelection(.enabled)
        }
    }
}
