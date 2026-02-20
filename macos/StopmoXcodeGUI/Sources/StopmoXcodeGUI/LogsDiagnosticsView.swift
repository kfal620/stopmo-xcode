import SwiftUI

struct LogsDiagnosticsView: View {
    @EnvironmentObject private var state: AppState
    @State private var severityFilter: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.lg) {
                ScreenHeader(
                    title: "Logs & Diagnostics",
                    subtitle: "Inspect structured logs, warning signatures, and diagnostics bundles."
                ) {
                    HStack(spacing: StopmoUI.Spacing.sm) {
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
                }

                if let bundlePath = state.lastDiagnosticsBundlePath, !bundlePath.isEmpty {
                    SectionCard("Latest Bundle") {
                        KeyValueRow(key: "Path", value: bundlePath)
                    }
                }

                if let snapshot = state.logsDiagnostics {
                    SectionCard("Warnings") {
                        if snapshot.warnings.isEmpty {
                            EmptyStateCard(message: "No warning signatures found in current log window.")
                        } else {
                            VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                                ForEach(snapshot.warnings) { row in
                                    HStack(alignment: .firstTextBaseline, spacing: StopmoUI.Spacing.xs) {
                                        StatusChip(label: row.severity, tone: severityTone(row.severity))
                                        Text("\(row.code): \(row.message)")
                                            .font(.system(.caption, design: .monospaced))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                    }

                    SectionCard("Queue Counts") {
                        let ordered = ["detected", "decoding", "xform", "dpx_write", "done", "failed"]
                        HStack(spacing: StopmoUI.Spacing.sm) {
                            ForEach(ordered, id: \.self) { key in
                                let count = snapshot.queueCounts[key, default: 0]
                                StatusChip(
                                    label: "\(key): \(count)",
                                    tone: queueTone(for: key, count: count)
                                )
                            }
                        }
                    }

                    SectionCard("Structured Logs") {
                        if snapshot.entries.isEmpty {
                            EmptyStateCard(message: "No log entries.")
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: StopmoUI.Spacing.xxs) {
                                    ForEach(snapshot.entries) { entry in
                                        HStack(alignment: .firstTextBaseline, spacing: StopmoUI.Spacing.xs) {
                                            StatusChip(label: entry.severity, tone: severityTone(entry.severity))
                                            Text("[\(entry.timestamp ?? "-")] \(entry.logger) \(entry.message)")
                                                .font(.system(.caption, design: .monospaced))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }
                            }
                            .frame(minHeight: 180, maxHeight: 360)
                        }
                    }
                } else {
                    EmptyStateCard(message: "No diagnostics loaded yet.")
                }
            }
            .padding(StopmoUI.Spacing.lg)
        }
        .onAppear {
            if state.logsDiagnostics == nil {
                Task { await state.refreshLogsDiagnostics() }
            }
        }
    }

    private func severityTone(_ severity: String) -> StatusTone {
        let normalized = severity.uppercased()
        if normalized == "ERROR" || normalized == "CRITICAL" {
            return .danger
        }
        if normalized == "WARNING" || normalized == "WARN" {
            return .warning
        }
        if normalized == "INFO" {
            return .success
        }
        return .neutral
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
}
