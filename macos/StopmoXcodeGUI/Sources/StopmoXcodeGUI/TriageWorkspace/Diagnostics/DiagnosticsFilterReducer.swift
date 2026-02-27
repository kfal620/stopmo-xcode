import Foundation

/// Severity filters applied to parsed log-entry rows.
enum LogSeverityFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case errorsAndWarnings = "Error+Warn"
    case errorsOnly = "Errors"
    case warningsOnly = "Warnings"
    case infoOnly = "Info"

    var id: String { rawValue }
}

/// Severity filters applied to derived diagnostic warning rows.
enum DiagnosticSeverityFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case errorsOnly = "Errors"
    case warningsOnly = "Warnings"

    var id: String { rawValue }
}

/// Pure filtering helpers for diagnostics log and warning tables.
enum DiagnosticsFilterReducer {
    static func filteredWarnings(
        warnings: [DiagnosticWarningRecord],
        severityFilter: DiagnosticSeverityFilter,
        warningCodeFilter: String,
        messageSearch: String
    ) -> [DiagnosticWarningRecord] {
        let codeFilter = warningCodeFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let textFilter = messageSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return warnings.filter { warning in
            switch severityFilter {
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

    static func filteredEntries(
        entries: [LogEntryRecord],
        severityFilter: LogSeverityFilter,
        loggerFilter: String,
        messageSearch: String
    ) -> [LogEntryRecord] {
        let loggerFilterTrimmed = loggerFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let textFilter = messageSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return entries.filter { entry in
            switch severityFilter {
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

    static func isErrorSeverity(_ severity: String) -> Bool {
        let normalized = severity.uppercased()
        return normalized == "ERROR" || normalized == "CRITICAL"
    }

    static func isWarningSeverity(_ severity: String) -> Bool {
        let normalized = severity.uppercased()
        return normalized == "WARNING" || normalized == "WARN"
    }

    static func isInfoSeverity(_ severity: String) -> Bool {
        severity.uppercased() == "INFO"
    }
}
