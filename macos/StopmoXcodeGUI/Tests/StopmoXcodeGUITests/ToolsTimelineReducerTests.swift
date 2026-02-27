import XCTest
@testable import StopmoXcodeGUI

final class ToolsTimelineReducerTests: XCTestCase {
    func testFilteredEventsErrorsFilterMatchesFailureSignals() {
        let events = [
            makeEvent(type: "stage_start", message: "begin"),
            makeEvent(type: "worker_fail", message: "bad frame"),
            makeEvent(type: "complete", message: "ok"),
        ]

        let filtered = ToolsTimelineReducer.filteredEvents(
            from: events,
            filter: .errors,
            search: ""
        )

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.eventType, "worker_fail")
    }

    func testFilteredEventsMilestonesFilterMatchesLifecycleEvents() {
        let events = [
            makeEvent(type: "stage_start", message: "begin"),
            makeEvent(type: "progress_tick", message: "50%"),
            makeEvent(type: "worker_fail", message: "bad frame"),
            makeEvent(type: "complete", message: "ok"),
        ]

        let filtered = ToolsTimelineReducer.filteredEvents(
            from: events,
            filter: .milestones,
            search: ""
        )

        XCTAssertEqual(filtered.map(\.eventType), ["stage_start", "worker_fail", "complete"])
    }

    func testAppendTimelineHonorsMaxCount() {
        var items: [ToolTimelineItem] = []
        for idx in 0 ..< 5 {
            ToolsTimelineReducer.appendTimeline(
                items: &items,
                title: "E\(idx)",
                detail: "event",
                tone: .neutral,
                timestampLabel: "12:00",
                maxCount: 3
            )
        }

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.first?.title, "E4")
        XCTAssertEqual(items.last?.title, "E2")
    }

    func testRunStatusMapsOperationStatus() {
        XCTAssertEqual(ToolsTimelineReducer.runStatus(from: "succeeded"), .succeeded)
        XCTAssertEqual(ToolsTimelineReducer.runStatus(from: "running"), .running)
        XCTAssertEqual(ToolsTimelineReducer.runStatus(from: "failed"), .failed)
        XCTAssertEqual(ToolsTimelineReducer.runStatus(from: "idle"), .idle)
    }

    func testToneMappingUsesExpectedSeverity() {
        XCTAssertEqual(ToolsTimelineReducer.toneForOperationStatus("succeeded"), .success)
        XCTAssertEqual(ToolsTimelineReducer.toneForOperationStatus("failed"), .danger)
        XCTAssertEqual(ToolsTimelineReducer.toneForOperationStatus("running"), .warning)

        XCTAssertEqual(ToolsTimelineReducer.toneForEvent(makeEvent(type: "worker_fail", message: "error")), .danger)
        XCTAssertEqual(ToolsTimelineReducer.toneForEvent(makeEvent(type: "complete", message: "done")), .success)
        XCTAssertEqual(ToolsTimelineReducer.toneForEvent(makeEvent(type: "start", message: "go")), .warning)
    }

    private func makeEvent(type: String, message: String) -> OperationEventRecord {
        OperationEventRecord(
            seq: 1,
            operationId: "op-1",
            timestampUtc: "2026-02-27T10:00:00Z",
            eventType: type,
            message: message,
            payload: nil
        )
    }
}
