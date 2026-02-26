import XCTest
@testable import StopmoXcodeGUI

final class DeliveryRunReducerTests: XCTestCase {
    func testBeginBuildsRunningState() {
        let state = DeliveryRunReducer.begin(
            kind: .selectedShots,
            total: 3,
            label: "Starting",
            nowUtc: "2026-02-26T11:00:00Z"
        )

        XCTAssertEqual(state.kind, .selectedShots)
        XCTAssertEqual(state.status, .running)
        XCTAssertEqual(state.total, 3)
        XCTAssertEqual(state.completed, 0)
        XCTAssertEqual(state.failed, 0)
        XCTAssertEqual(state.activeLabel, "Starting")
        XCTAssertEqual(state.progress, 0)
        XCTAssertEqual(state.startedAtUtc, "2026-02-26T11:00:00Z")
        XCTAssertNil(state.finishedAtUtc)
    }

    func testUpdateProgressTracksCompletion() {
        var state = DeliveryRunState.idleDefault
        state.total = 4

        DeliveryRunReducer.updateProgress(state: &state, completed: 2, failed: 1, activeLabel: "Processed")

        XCTAssertEqual(state.completed, 2)
        XCTAssertEqual(state.failed, 1)
        XCTAssertEqual(state.total, 4)
        XCTAssertEqual(state.activeLabel, "Processed")
        XCTAssertEqual(state.progress, 0.75, accuracy: 0.0001)
    }

    func testFinishSetsStatusOutputsAndTimestamp() {
        var state = DeliveryRunReducer.begin(
            kind: .dayWrapBatch,
            total: 2,
            label: "Running",
            nowUtc: "2026-02-26T11:00:00Z"
        )

        DeliveryRunReducer.finish(
            state: &state,
            status: .succeeded,
            outputs: ["/tmp/out.mov"],
            completed: 2,
            total: 2,
            failed: 0,
            activeLabel: "Done",
            nowUtc: "2026-02-26T11:00:05Z"
        )

        XCTAssertEqual(state.status, .succeeded)
        XCTAssertEqual(state.latestOutputs, ["/tmp/out.mov"])
        XCTAssertEqual(state.progress, 1.0)
        XCTAssertEqual(state.activeLabel, "Done")
        XCTAssertEqual(state.finishedAtUtc, "2026-02-26T11:00:05Z")
    }

    func testAppendEventCapsLengthAndPrepends() {
        var state = DeliveryRunState.idleDefault

        DeliveryRunReducer.appendEvent(
            state: &state,
            tone: .neutral,
            title: "first",
            detail: "a",
            shotName: nil,
            timestampUtc: "2026-02-26T11:00:00Z",
            maxEvents: 2
        )
        DeliveryRunReducer.appendEvent(
            state: &state,
            tone: .success,
            title: "second",
            detail: "b",
            shotName: nil,
            timestampUtc: "2026-02-26T11:00:01Z",
            maxEvents: 2
        )
        DeliveryRunReducer.appendEvent(
            state: &state,
            tone: .danger,
            title: "third",
            detail: "c",
            shotName: nil,
            timestampUtc: "2026-02-26T11:00:02Z",
            maxEvents: 2
        )

        XCTAssertEqual(state.events.count, 2)
        XCTAssertEqual(state.events[0].title, "third")
        XCTAssertEqual(state.events[1].title, "second")
    }
}
