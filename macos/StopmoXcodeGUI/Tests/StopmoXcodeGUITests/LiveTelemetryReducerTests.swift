import XCTest
@testable import StopmoXcodeGUI

final class LiveTelemetryReducerTests: XCTestCase {
    func testUpdateTelemetryComputesThroughputAndLastFrame() {
        let watch = makeWatchState(completedFrames: 12)
        let previousAt = Date(timeIntervalSince1970: 100)
        let now = Date(timeIntervalSince1970: 102)

        let update = LiveTelemetryReducer.updateTelemetry(
            watchState: watch,
            counts: ["done": 12, "detected": 1, "decoding": 1, "xform": 0, "dpx_write": 0],
            previousDoneFrameCount: 10,
            previousSampleAt: previousAt,
            previousLastFrameAt: nil,
            previousThroughput: 0,
            previousQueueDepthTrend: [],
            now: now
        )

        XCTAssertEqual(update.lastDoneFrameCountSample, 12)
        XCTAssertEqual(update.queueDepthTrend.last, 2)
        XCTAssertNotNil(update.lastFrameAt)
        XCTAssertEqual(update.throughputFramesPerMinute, 60.0, accuracy: 0.01)
    }

    func testQueueDepthTrendIsCapped() {
        let watch = makeWatchState(completedFrames: 0)
        let trend = Array(repeating: 1, count: 180)
        let update = LiveTelemetryReducer.updateTelemetry(
            watchState: watch,
            counts: ["done": 0, "detected": 3, "decoding": 0, "xform": 0, "dpx_write": 0],
            previousDoneFrameCount: nil,
            previousSampleAt: nil,
            previousLastFrameAt: nil,
            previousThroughput: 0,
            previousQueueDepthTrend: trend,
            now: Date(timeIntervalSince1970: 200)
        )
        XCTAssertEqual(update.queueDepthTrend.count, 180)
        XCTAssertEqual(update.queueDepthTrend.last, 3)
    }

    func testRecordLiveEventCapsLengthAndPrepends() {
        let updated = LiveTelemetryReducer.recordLiveEvent(
            existingEvents: ["[10:00:00] old1", "[09:59:59] old2"],
            message: "new",
            timestamp: "10:00:01",
            maxEvents: 2
        )
        XCTAssertEqual(updated.count, 2)
        XCTAssertTrue(updated[0].contains("new"))
        XCTAssertTrue(updated[1].contains("old1"))
    }

    private func makeWatchState(completedFrames: Int) -> WatchServiceState {
        WatchServiceState(
            running: true,
            pid: nil,
            startedAtUtc: nil,
            configPath: "/tmp/sample.yaml",
            logPath: nil,
            logTail: [],
            queue: QueueSnapshot(
                dbPath: "/tmp/queue.sqlite3",
                counts: [:],
                total: 0,
                recent: []
            ),
            progressRatio: 0,
            completedFrames: completedFrames,
            inflightFrames: 0,
            totalFrames: completedFrames,
            startBlocked: nil,
            launchError: nil,
            preflight: nil,
            crashRecovery: nil
        )
    }
}
