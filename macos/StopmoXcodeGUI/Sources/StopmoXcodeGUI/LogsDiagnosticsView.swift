import SwiftUI

private enum LogSeverityFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case errorsAndWarnings = "Error+Warn"
    case errorsOnly = "Errors"
    case warningsOnly = "Warnings"
    case infoOnly = "Info"

    var id: String { rawValue }
}

private enum DiagnosticSeverityFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case errorsOnly = "Errors"
    case warningsOnly = "Warnings"

    var id: String { rawValue }
}

private enum LogsFocusField: Hashable {
    case search
}

private struct DiagnosticHint {
    let likelyCause: String
    let suggestedAction: String
}

struct LogsDiagnosticsView: View {
    @EnvironmentObject private var state: AppState
    var embedded: Bool = false

    @State private var refreshSeverityCSV: String = ""
    @State private var logSeverityFilter: LogSeverityFilter = .all
    @State private var diagnosticSeverityFilter: DiagnosticSeverityFilter = .all
    @State private var loggerFilter: String = ""
    @State private var messageSearch: String = ""
    @State private var warningCodeFilter: String = ""
    @State private var warningsPageSize: Int = 25
    @State private var warningsPageIndex: Int = 0
    @State private var logsPageSize: Int = 100
    @State private var logsPageIndex: Int = 0
    @FocusState private var focusedField: LogsFocusField?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.lg) {
                if !embedded {
                    ScreenHeader(
                        title: "Logs & Diagnostics",
                        subtitle: "Structured log analysis, issue remediation guidance, and diagnostics export."
                    ) {
                        headerActions
                    }
                } else {
                    headerActions
                }

                controlsCard
                diagnosticsBundleCard

                if let snapshot = state.logsDiagnostics {
                    runtimeSummaryCard(snapshot)
                    diagnosticsIssuesCard(snapshot)
                    structuredLogsCard(snapshot)
                } else {
                    EmptyStateCard(message: "No diagnostics loaded yet.")
                }
            }
            .padding(embedded ? StopmoUI.Spacing.md : StopmoUI.Spacing.lg)
        }
        .onAppear {
            if state.logsDiagnostics == nil {
                Task { await state.refreshLogsDiagnostics() }
            }
            focusedField = .search
        }
        .onChange(of: logSeverityFilter) { _, _ in
            logsPageIndex = 0
        }
        .onChange(of: diagnosticSeverityFilter) { _, _ in
            warningsPageIndex = 0
        }
        .onChange(of: loggerFilter) { _, _ in
            logsPageIndex = 0
        }
        .onChange(of: messageSearch) { _, _ in
            logsPageIndex = 0
            warningsPageIndex = 0
        }
        .onChange(of: warningCodeFilter) { _, _ in
            warningsPageIndex = 0
        }
        .onChange(of: state.logsDiagnostics?.entries.count ?? -1) { _, _ in
            logsPageIndex = 0
            warningsPageIndex = 0
        }
        .onChange(of: warningsPageSize) { _, _ in
            warningsPageIndex = 0
        }
        .onChange(of: logsPageSize) { _, _ in
            logsPageIndex = 0
        }
    }

    private var headerActions: some View {
        HStack(spacing: StopmoUI.Spacing.sm) {
            if let count = state.logsDiagnostics?.entries.count {
                StatusChip(label: "Logs \(count)", tone: .neutral)
            }
            if let warnings = state.logsDiagnostics?.warnings.count, warnings > 0 {
                StatusChip(label: "Issues \(warnings)", tone: .warning)
            }
            Button("Refresh") {
                Task { await refreshLogsFromToolbar() }
            }
            .disabled(state.isBusy)
        }
    }

    private var controlsCard: some View {
        SectionCard("Log Filters", subtitle: "Filter by severity, logger field, warning code, and free-text search.") {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: StopmoUI.Spacing.sm) {
                        Picker("Log Severity", selection: $logSeverityFilter) {
                            ForEach(LogSeverityFilter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 360)

                        Picker("Issue Severity", selection: $diagnosticSeverityFilter) {
                            ForEach(DiagnosticSeverityFilter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 280)

                        TextField("Logger filter", text: $loggerFilter)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: StopmoUI.Spacing.sm) {
                        TextField("Search message/timestamp", text: $messageSearch)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 280)
                            .focused($focusedField, equals: .search)
                        TextField("Warning code filter", text: $warningCodeFilter)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                        TextField("Refresh severity (CSV, optional)", text: $refreshSeverityCSV)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 230)

                        Button("Refresh With Server Filter") {
                            Task { await refreshLogsFromToolbar() }
                        }
                        .disabled(state.isBusy)

                        Button("Clear Filters") {
                            logSeverityFilter = .all
                            diagnosticSeverityFilter = .all
                            loggerFilter = ""
                            messageSearch = ""
                            warningCodeFilter = ""
                            refreshSeverityCSV = ""
                            warningsPageIndex = 0
                            logsPageIndex = 0
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var diagnosticsBundleCard: some View {
        SectionCard("Diagnostics Bundle", subtitle: "Generate and share support bundle with structured context.") {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                HStack(spacing: StopmoUI.Spacing.sm) {
                    Button("Create Diagnostics Bundle") {
                        Task { await state.copyDiagnosticsBundle() }
                    }
                    .disabled(state.isBusy)

                    if let bundlePath = state.lastDiagnosticsBundlePath, !bundlePath.isEmpty {
                        Button("Open Bundle") {
                            state.openPathInFinder(bundlePath)
                        }
                        Button("Copy Bundle Path") {
                            state.copyTextToPasteboard(bundlePath, label: "bundle path")
                        }
                    }
                }

                if let bundlePath = state.lastDiagnosticsBundlePath, !bundlePath.isEmpty {
                    KeyValueRow(key: "Latest Bundle", value: bundlePath, tone: .success)
                } else {
                    Text("No bundle generated in this session yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func runtimeSummaryCard(_ snapshot: LogsDiagnosticsSnapshot) -> some View {
        SectionCard("Runtime Summary", subtitle: "Watch status, queue health, and active log sources.") {
            KeyValueRow(
                key: "Watch",
                value: snapshot.watchRunning ? "running (pid \(snapshot.watchPid.map(String.init) ?? "-"))" : "stopped",
                tone: snapshot.watchRunning ? .success : .warning
            )
            KeyValueRow(key: "Config", value: snapshot.configPath)
            KeyValueRow(key: "Log Sources", value: snapshot.logSources.joined(separator: ", "))

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
    }

    private func diagnosticsIssuesCard(_ snapshot: LogsDiagnosticsSnapshot) -> some View {
        let warnings = filteredWarnings(from: snapshot)
        let warningPageCount = max(1, (max(1, warnings.count) + warningsPageSize - 1) / warningsPageSize)
        let warningSafePage = min(max(0, warningsPageIndex), warningPageCount - 1)
        let warningStart = warningSafePage * warningsPageSize
        let warningEnd = min(warnings.count, warningStart + warningsPageSize)
        let pagedWarnings = warningStart < warningEnd ? Array(warnings[warningStart..<warningEnd]) : []

        return SectionCard("Diagnostics Issues", subtitle: "Detected warning/error signatures with remediation guidance.") {
            HStack(spacing: StopmoUI.Spacing.sm) {
                Picker("Issue Page", selection: $warningsPageSize) {
                    Text("15").tag(15)
                    Text("25").tag(25)
                    Text("40").tag(40)
                }
                .pickerStyle(.menu)
                .frame(width: 110)

                Button("Previous") {
                    warningsPageIndex = max(0, warningSafePage - 1)
                }
                .disabled(warningSafePage == 0 || warnings.isEmpty)

                Button("Next") {
                    warningsPageIndex = min(warningPageCount - 1, warningSafePage + 1)
                }
                .disabled(warningSafePage >= warningPageCount - 1 || warnings.isEmpty)

                Spacer()

                StatusChip(label: "Page \(warningSafePage + 1)/\(warningPageCount)", tone: .neutral)
                StatusChip(label: warningsRangeLabel(start: warningStart, count: pagedWarnings.count), tone: .neutral)
            }

            if warnings.isEmpty {
                EmptyStateCard(message: "No diagnostic issues match the current filters.")
            } else {
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                    ForEach(pagedWarnings) { warning in
                        let hint = hintForWarning(warning)
                        VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                            HStack(spacing: StopmoUI.Spacing.xs) {
                                StatusChip(label: warning.severity, tone: severityTone(warning.severity))
                                StatusChip(label: warning.code, tone: .neutral)
                                if let ts = warning.timestamp {
                                    Text(ts)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Copy") {
                                    state.copyTextToPasteboard(diagnosticCopyText(warning, hint: hint), label: "diagnostic issue")
                                }
                                .buttonStyle(.borderless)
                            }
                            Text(warning.message)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Likely cause: \(hint.likelyCause)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Suggested action: \(hint.suggestedAction)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(StopmoUI.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: StopmoUI.Radius.card, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                        )
                    }
                }
            }
        }
    }

    private func structuredLogsCard(_ snapshot: LogsDiagnosticsSnapshot) -> some View {
        SectionCard("Structured Logs", subtitle: "Field-filterable log records (timestamp, severity, logger, message).") {
            let entries = filteredEntries(from: snapshot)
            let logsPageCount = max(1, (max(1, entries.count) + logsPageSize - 1) / logsPageSize)
            let logsSafePage = min(max(0, logsPageIndex), logsPageCount - 1)
            let logsStart = logsSafePage * logsPageSize
            let logsEnd = min(entries.count, logsStart + logsPageSize)
            let pagedEntries = logsStart < logsEnd ? Array(entries[logsStart..<logsEnd]) : []

            HStack(spacing: StopmoUI.Spacing.sm) {
                Picker("Log Page", selection: $logsPageSize) {
                    Text("50").tag(50)
                    Text("100").tag(100)
                    Text("200").tag(200)
                }
                .pickerStyle(.menu)
                .frame(width: 110)

                Button("Previous") {
                    logsPageIndex = max(0, logsSafePage - 1)
                }
                .disabled(logsSafePage == 0 || entries.isEmpty)

                Button("Next") {
                    logsPageIndex = min(logsPageCount - 1, logsSafePage + 1)
                }
                .disabled(logsSafePage >= logsPageCount - 1 || entries.isEmpty)

                Spacer()

                StatusChip(label: "Page \(logsSafePage + 1)/\(logsPageCount)", tone: .neutral)
                StatusChip(label: logsRangeLabel(start: logsStart, count: pagedEntries.count), tone: .neutral)
            }

            if entries.isEmpty {
                EmptyStateCard(message: "No log records match current filters.")
            } else {
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                        logsHeader
                        Divider()
                        ForEach(pagedEntries) { entry in
                            logsRow(entry)
                        }
                    }
                }
                .frame(minHeight: 190, maxHeight: 380)
            }
        }
    }

    private var logsHeader: some View {
        HStack(spacing: 10) {
            logsCol("Timestamp", width: 210)
            logsCol("Severity", width: 90)
            logsCol("Logger", width: 180)
            logsCol("Message", width: 700)
            logsCol("Actions", width: 80)
        }
        .font(.caption.bold())
    }

    private func logsRow(_ entry: LogEntryRecord) -> some View {
        HStack(spacing: 10) {
            logsCol(entry.timestamp ?? "-", width: 210)
            HStack {
                StatusChip(label: entry.severity, tone: severityTone(entry.severity))
                    .frame(width: 90, alignment: .leading)
            }
            logsCol(entry.logger, width: 180)
            logsCol(entry.message, width: 700)
            IconActionButton(
                systemName: "doc.on.doc",
                accessibilityLabel: "Copy log row",
                accessibilityHint: "Copies the raw log line."
            ) {
                state.copyTextToPasteboard(entry.raw, label: "log line")
            }
            .frame(width: 80, alignment: .leading)
        }
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
    }

    private func logsCol(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width, alignment: .leading)
    }

    private func filteredWarnings(from snapshot: LogsDiagnosticsSnapshot) -> [DiagnosticWarningRecord] {
        let codeFilter = warningCodeFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let textFilter = messageSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return snapshot.warnings.filter { warning in
            switch diagnosticSeverityFilter {
            case .all:
                break
            case .errorsOnly:
                if !isErrorSeverity(warning.severity) { return false }
            case .warningsOnly:
                if isErrorSeverity(warning.severity) { return false }
            }

            if !codeFilter.isEmpty, !warning.code.lowercased().contains(codeFilter) {
                return false
            }

            if !textFilter.isEmpty {
                let haystack = [warning.message, warning.logger ?? "", warning.code, warning.timestamp ?? ""]
                    .joined(separator: " ")
                    .lowercased()
                if !haystack.contains(textFilter) {
                    return false
                }
            }
            return true
        }
    }

    private func filteredEntries(from snapshot: LogsDiagnosticsSnapshot) -> [LogEntryRecord] {
        let loggerFilterTrimmed = loggerFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let textFilter = messageSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return snapshot.entries.filter { entry in
            switch logSeverityFilter {
            case .all:
                break
            case .errorsAndWarnings:
                if !(isErrorSeverity(entry.severity) || isWarningSeverity(entry.severity)) {
                    return false
                }
            case .errorsOnly:
                if !isErrorSeverity(entry.severity) { return false }
            case .warningsOnly:
                if !isWarningSeverity(entry.severity) { return false }
            case .infoOnly:
                if !isInfoSeverity(entry.severity) { return false }
            }

            if !loggerFilterTrimmed.isEmpty,
               !entry.logger.lowercased().contains(loggerFilterTrimmed)
            {
                return false
            }

            if !textFilter.isEmpty {
                let haystack = [entry.message, entry.timestamp ?? "", entry.logger, entry.raw]
                    .joined(separator: " ")
                    .lowercased()
                if !haystack.contains(textFilter) {
                    return false
                }
            }
            return true
        }
    }

    private func refreshLogsFromToolbar() async {
        let value = refreshSeverityCSV.trimmingCharacters(in: .whitespacesAndNewlines)
        await state.refreshLogsDiagnostics(severity: value.isEmpty ? nil : value)
        logsPageIndex = 0
        warningsPageIndex = 0
    }

    private func warningsRangeLabel(start: Int, count: Int) -> String {
        guard count > 0 else { return "Rows 0-0" }
        return "Rows \(start + 1)-\(start + count)"
    }

    private func logsRangeLabel(start: Int, count: Int) -> String {
        guard count > 0 else { return "Rows 0-0" }
        return "Rows \(start + 1)-\(start + count)"
    }

    private func hintForWarning(_ warning: DiagnosticWarningRecord) -> DiagnosticHint {
        switch warning.code.lowercased() {
        case "clipping":
            return DiagnosticHint(
                likelyCause: "Scene highlights or exposure offset are pushing values above pre-log headroom.",
                suggestedAction: "Reduce exposure offset, verify capture exposure, and re-run problematic frames."
            )
        case "nan_inf":
            return DiagnosticHint(
                likelyCause: "Non-finite values entered the transform graph (decode or color math issue).",
                suggestedAction: "Inspect source frame integrity and check matrix/OCIO configuration for invalid operations."
            )
        case "wb_drift":
            return DiagnosticHint(
                likelyCause: "Incoming as-shot WB differs from locked shot WB reference.",
                suggestedAction: "Confirm shot boundaries/regex and keep deterministic shot-level WB lock policy."
            )
        case "dependency_error":
            return DiagnosticHint(
                likelyCause: "Required runtime dependency is missing in the active Python environment.",
                suggestedAction: "Run Configure > Workspace & Health checks, install missing packages/binaries, and retry."
            )
        case "decode_failure":
            return DiagnosticHint(
                likelyCause: "Frame decode failed due to unsupported/corrupt media or decoder mismatch.",
                suggestedAction: "Validate frame readability, file extension includes, and decode dependency availability."
            )
        default:
            return DiagnosticHint(
                likelyCause: "A pipeline warning/error condition was recorded in the runtime log stream.",
                suggestedAction: "Filter logs by logger/severity and inspect surrounding events for exact failure context."
            )
        }
    }

    private func diagnosticCopyText(_ warning: DiagnosticWarningRecord, hint: DiagnosticHint) -> String {
        [
            "[\(warning.severity)] \(warning.code)",
            warning.message,
            "Likely cause: \(hint.likelyCause)",
            "Suggested action: \(hint.suggestedAction)",
            "Timestamp: \(warning.timestamp ?? "-")",
            "Logger: \(warning.logger ?? "-")",
        ].joined(separator: "\n")
    }

    private func severityTone(_ severity: String) -> StatusTone {
        if isErrorSeverity(severity) {
            return .danger
        }
        if isWarningSeverity(severity) {
            return .warning
        }
        if isInfoSeverity(severity) {
            return .success
        }
        return .neutral
    }

    private func isErrorSeverity(_ severity: String) -> Bool {
        let normalized = severity.uppercased()
        return normalized == "ERROR" || normalized == "CRITICAL"
    }

    private func isWarningSeverity(_ severity: String) -> Bool {
        let normalized = severity.uppercased()
        return normalized == "WARNING" || normalized == "WARN"
    }

    private func isInfoSeverity(_ severity: String) -> Bool {
        severity.uppercased() == "INFO"
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
