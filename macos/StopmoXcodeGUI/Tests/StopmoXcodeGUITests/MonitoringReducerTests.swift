import XCTest
@testable import StopmoXcodeGUI

final class MonitoringReducerTests: XCTestCase {
    func testSuccessTransitionUsesFastIntervalWhenRunning() {
        let state = MonitoringReducer.successTransition(
            watchState: makeWatchState(running: true, inflightFrames: 0, queueDepth: 0),
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(state.consecutiveFailures, 0)
        XCTAssertEqual(state.pollIntervalSeconds, 1.0)
    }

    func testSuccessTransitionUsesIdleIntervalWhenStoppedAndEmpty() {
        let state = MonitoringReducer.successTransition(
            watchState: makeWatchState(running: false, inflightFrames: 0, queueDepth: 0),
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(state.pollIntervalSeconds, 2.5)
    }

    func testFailureTransitionBackoffAndWarningThreshold() {
        let first = MonitoringReducer.failureTransition(previousFailures: 0, now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(first.consecutiveFailures, 1)
        XCTAssertEqual(first.pollIntervalSeconds, 2.0)
        XCTAssertFalse(first.shouldEmitDegradedWarning)

        let third = MonitoringReducer.failureTransition(previousFailures: 2, now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(third.consecutiveFailures, 3)
        XCTAssertTrue(third.shouldEmitDegradedWarning)
        XCTAssertEqual(third.pollIntervalSeconds, 8.0)

        let capped = MonitoringReducer.failureTransition(previousFailures: 10, now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(capped.pollIntervalSeconds, 12.0)
    }

    private func makeWatchState(running: Bool, inflightFrames: Int, queueDepth: Int) -> WatchServiceState {
        let queue = QueueSnapshot(
            dbPath: "/tmp/queue.sqlite3",
            counts: [
                "detected": queueDepth,
                "decoding": 0,
                "xform": 0,
                "dpx_write": 0,
                "done": 0,
                "failed": 0,
            ],
            total: queueDepth,
            recent: []
        )
        return WatchServiceState(
            running: running,
            pid: nil,
            startedAtUtc: nil,
            configPath: "/tmp/sample.yaml",
            logPath: nil,
            logTail: [],
            queue: queue,
            progressRatio: 0,
            completedFrames: 0,
            inflightFrames: inflightFrames,
            totalFrames: 0,
            startBlocked: nil,
            launchError: nil,
            preflight: nil,
            crashRecovery: nil
        )
    }
}
