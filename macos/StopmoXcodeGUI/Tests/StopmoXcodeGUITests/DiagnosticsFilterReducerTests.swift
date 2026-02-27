import XCTest
@testable import StopmoXcodeGUI

final class DiagnosticsFilterReducerTests: XCTestCase {
    func testWarningFilterBySeverityCodeAndSearch() {
        let warnings = [
            DiagnosticWarningRecord(code: "decode_failure", severity: "ERROR", timestamp: "2026-02-26T10:00:00Z", message: "Decode failed", logger: "decode"),
            DiagnosticWarningRecord(code: "wb_drift", severity: "WARNING", timestamp: "2026-02-26T10:01:00Z", message: "WB drift", logger: "color"),
        ]

        let errorsOnly = DiagnosticsFilterReducer.filteredWarnings(
            warnings: warnings,
            severityFilter: .errorsOnly,
            warningCodeFilter: "",
            messageSearch: ""
        )
        XCTAssertEqual(errorsOnly.map { $0.code }, ["decode_failure"])

        let codeMatch = DiagnosticsFilterReducer.filteredWarnings(
            warnings: warnings,
            severityFilter: .all,
            warningCodeFilter: "wb_",
            messageSearch: ""
        )
        XCTAssertEqual(codeMatch.map { $0.code }, ["wb_drift"])

        let textMatch = DiagnosticsFilterReducer.filteredWarnings(
            warnings: warnings,
            severityFilter: .all,
            warningCodeFilter: "",
            messageSearch: "decode"
        )
        XCTAssertEqual(textMatch.map { $0.code }, ["decode_failure"])
    }

    func testLogEntryFilterBySeverityLoggerAndText() {
        let entries = [
            LogEntryRecord(timestamp: "2026-02-26T10:00:00Z", severity: "INFO", logger: "watcher", message: "started", raw: "started"),
            LogEntryRecord(timestamp: "2026-02-26T10:01:00Z", severity: "ERROR", logger: "worker", message: "decode failed", raw: "decode failed"),
            LogEntryRecord(timestamp: "2026-02-26T10:02:00Z", severity: "WARNING", logger: "worker", message: "slow", raw: "slow"),
        ]

        let errorsWarn = DiagnosticsFilterReducer.filteredEntries(
            entries: entries,
            severityFilter: .errorsAndWarnings,
            loggerFilter: "",
            messageSearch: ""
        )
        XCTAssertEqual(errorsWarn.map(\.severity), ["ERROR", "WARNING"])

        let loggerFiltered = DiagnosticsFilterReducer.filteredEntries(
            entries: entries,
            severityFilter: .all,
            loggerFilter: "watch",
            messageSearch: ""
        )
        XCTAssertEqual(loggerFiltered.map(\.logger), ["watcher"])

        let textFiltered = DiagnosticsFilterReducer.filteredEntries(
            entries: entries,
            severityFilter: .all,
            loggerFilter: "",
            messageSearch: "decode"
        )
        XCTAssertEqual(textFiltered.map(\.severity), ["ERROR"])
    }
}
