import XCTest
@testable import StopmoXcodeGUI

final class CaptureMonitorFormattingTests: XCTestCase {
    func testParseActivityLineExtractsTimestampMessageAndSeverity() {
        let row = CaptureMonitorFormatting.parseActivityLine("[10:29:33] Queue counts updated: done 42")

        XCTAssertEqual(row.timestamp, "10:29:33")
        XCTAssertEqual(row.message, "Queue counts updated: done 42")
        XCTAssertEqual(row.severity, .system)
    }

    func testInferSeverityRulesRespectErrorWarningAndSystemSignals() {
        XCTAssertEqual(CaptureMonitorFormatting.inferSeverity(for: "decode failed for job=8"), .error)
        XCTAssertEqual(CaptureMonitorFormatting.inferSeverity(for: "watch blocked; missing ffmpeg"), .warning)
        XCTAssertEqual(CaptureMonitorFormatting.inferSeverity(for: "Watch service started with pid 123"), .system)
        XCTAssertEqual(CaptureMonitorFormatting.inferSeverity(for: "frame queued"), .info)
    }

    func testFilterActivityRowsByFilterAndSearch() {
        let rows = [
            CaptureActivityRow(timestamp: "10:00:00", message: "Queue counts updated", severity: .system, rawLine: "[10:00:00] Queue counts updated"),
            CaptureActivityRow(timestamp: "10:00:01", message: "decode failed for job", severity: .error, rawLine: "[10:00:01] decode failed for job"),
            CaptureActivityRow(timestamp: "10:00:02", message: "missing dependency", severity: .warning, rawLine: "[10:00:02] missing dependency"),
        ]

        let errors = CaptureMonitorFormatting.filterActivityRows(rows, filter: .errors, searchTerm: "")
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors.first?.severity, .error)

        let search = CaptureMonitorFormatting.filterActivityRows(rows, filter: .all, searchTerm: "dependency")
        XCTAssertEqual(search.count, 1)
        XCTAssertEqual(search.first?.severity, .warning)
    }

    func testGroupedKPIsReturnsExpectedOrderLabelsAndTones() {
        let groups = CaptureMonitorFormatting.groupedKPIs(
            queueCounts: [
                "detected": 3,
                "decoding": 2,
                "xform": 1,
                "dpx_write": 4,
                "done": 20,
                "failed": 1,
            ],
            throughputFramesPerMinute: 0,
            workersInFlight: 3,
            maxWorkers: 3,
            etaLabel: "ETA --",
            lastFrameLabel: "--",
            hasLastFrame: false
        )

        XCTAssertEqual(groups.map(\.id), ["pipeline", "outputPace", "capacityFreshness"])
        XCTAssertEqual(groups[0].metrics.map(\.label), ["Detected", "Decoding", "Transform", "DPX Write"])
        XCTAssertEqual(groups[1].metrics.map(\.label), ["Done", "Failed", "Throughput"])
        XCTAssertEqual(groups[2].metrics.map(\.label), ["Workers", "ETA", "Last Frame"])
        XCTAssertEqual(groups[1].metrics[1].tone, .danger)
        XCTAssertEqual(groups[1].metrics[2].tone, .warning)
        XCTAssertEqual(groups[2].metrics[0].tone, .warning)
        XCTAssertEqual(groups[2].metrics[2].tone, .warning)
    }
}
