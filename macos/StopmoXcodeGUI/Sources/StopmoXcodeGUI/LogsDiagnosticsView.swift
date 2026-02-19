import SwiftUI

struct LogsDiagnosticsView: View {
    @EnvironmentObject private var state: AppState
    @State private var severityFilter: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Logs & Diagnostics")
                        .font(.title2)
                        .bold()
                    Spacer()
                    TextField("Severity filter (e.g. ERROR,WARNING)", text: $severityFilter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                    Button("Refresh") {
                        Task {
                            await state.refreshLogsDiagnostics(
                                severity: severityFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? nil
                                    : severityFilter
                            )
                        }
                    }
                    .disabled(state.isBusy)
                    Button("Copy Diagnostics Bundle") {
                        Task { await state.copyDiagnosticsBundle() }
                    }
                    .disabled(state.isBusy)
                }

                if let bundlePath = state.lastDiagnosticsBundlePath, !bundlePath.isEmpty {
                    Text("Latest bundle: \(bundlePath)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let snapshot = state.logsDiagnostics {
                    GroupBox("Warnings") {
                        if snapshot.warnings.isEmpty {
                            Text("No warning signatures found in current log window.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(snapshot.warnings) { row in
                                    Text("[\(row.severity)] \(row.code): \(row.message)")
                                        .font(.system(.caption, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }

                    GroupBox("Queue Counts") {
                        let ordered = ["detected", "decoding", "xform", "dpx_write", "done", "failed"]
                        HStack(spacing: 12) {
                            ForEach(ordered, id: \.self) { key in
                                Text("\(key): \(snapshot.queueCounts[key, default: 0])")
                                    .font(.caption)
                            }
                        }
                    }

                    GroupBox("Structured Logs") {
                        if snapshot.entries.isEmpty {
                            Text("No log entries.")
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(snapshot.entries) { entry in
                                        Text("[\(entry.severity)] \(entry.timestamp ?? "-") \(entry.logger) \(entry.message)")
                                            .font(.system(.caption, design: .monospaced))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                            .frame(minHeight: 180, maxHeight: 360)
                        }
                    }
                } else {
                    Text("No diagnostics loaded yet.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .onAppear {
            if state.logsDiagnostics == nil {
                Task { await state.refreshLogsDiagnostics() }
            }
        }
    }
}
