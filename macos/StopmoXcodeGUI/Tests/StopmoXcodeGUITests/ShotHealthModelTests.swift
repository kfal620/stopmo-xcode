import XCTest
@testable import StopmoXcodeGUI

final class ShotHealthModelTests: XCTestCase {
    func testDoneShotWithoutFailuresIsCleanAndDeliverable() {
        let shot = makeShot(
            shotName: "SHOT_A",
            state: "done",
            totalFrames: 128,
            doneFrames: 128,
            failedFrames: 0,
            inflightFrames: 0
        )

        let evaluation = ShotHealthModel.evaluate(shot)
        XCTAssertEqual(evaluation.healthState, .clean)
        XCTAssertTrue(evaluation.isDeliverable)
        XCTAssertEqual(evaluation.completionLabel, "128/128 done")
        XCTAssertNil(evaluation.readinessReason)
    }

    func testFailedShotIsIssuesAndNotDeliverable() {
        let shot = makeShot(
            shotName: "SHOT_B",
            state: "issues",
            totalFrames: 100,
            doneFrames: 90,
            failedFrames: 10,
            inflightFrames: 0
        )

        let evaluation = ShotHealthModel.evaluate(shot)
        XCTAssertEqual(evaluation.healthState, .issues)
        XCTAssertFalse(evaluation.isDeliverable)
        XCTAssertEqual(evaluation.readinessReason, "has issues")
    }

    func testInflightShotIsNotDeliverable() {
        let shot = makeShot(
            shotName: "SHOT_C",
            state: "processing",
            totalFrames: 64,
            doneFrames: 40,
            failedFrames: 0,
            inflightFrames: 6
        )

        let evaluation = ShotHealthModel.evaluate(shot)
        XCTAssertEqual(evaluation.healthState, .inflight)
        XCTAssertFalse(evaluation.isDeliverable)
        XCTAssertEqual(evaluation.readinessReason, "inflight")
    }

    func testActiveShotResolverPrefersInflightMostRecent() {
        let done = makeShot(
            shotName: "SHOT_DONE",
            state: "done",
            totalFrames: 24,
            doneFrames: 24,
            failedFrames: 0,
            inflightFrames: 0,
            lastUpdatedAt: "2026-02-24T10:00:00Z"
        )
        let inflightOlder = makeShot(
            shotName: "SHOT_INFLIGHT_OLD",
            state: "processing",
            totalFrames: 24,
            doneFrames: 10,
            failedFrames: 0,
            inflightFrames: 3,
            lastUpdatedAt: "2026-02-24T10:01:00Z"
        )
        let inflightNewest = makeShot(
            shotName: "SHOT_INFLIGHT_NEW",
            state: "processing",
            totalFrames: 24,
            doneFrames: 12,
            failedFrames: 0,
            inflightFrames: 4,
            lastUpdatedAt: "2026-02-24T10:05:00Z"
        )

        let snapshot = ShotsSummarySnapshot(
            dbPath: "/tmp/queue.db",
            count: 3,
            shots: [done, inflightOlder, inflightNewest]
        )

        XCTAssertEqual(ShotHealthModel.resolveActiveShot(from: snapshot)?.shotName, "SHOT_INFLIGHT_NEW")
    }

    func testActiveShotResolverFallsBackToMostRecentUpdated() {
        let shotA = makeShot(
            shotName: "SHOT_A",
            state: "queued",
            totalFrames: 50,
            doneFrames: 0,
            failedFrames: 0,
            inflightFrames: 0,
            lastUpdatedAt: "2026-02-24T10:00:00Z"
        )
        let shotB = makeShot(
            shotName: "SHOT_B",
            state: "queued",
            totalFrames: 50,
            doneFrames: 0,
            failedFrames: 0,
            inflightFrames: 0,
            lastUpdatedAt: "2026-02-24T10:03:00Z"
        )

        let snapshot = ShotsSummarySnapshot(
            dbPath: "/tmp/queue.db",
            count: 2,
            shots: [shotA, shotB]
        )

        XCTAssertEqual(ShotHealthModel.resolveActiveShot(from: snapshot)?.shotName, "SHOT_B")
    }

    func testUpdatedDisplayLabelValidTimestampReturnsRelativeValue() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let timestamp = isoString(from: now.addingTimeInterval(-125))

        let label = ShotHealthModel.updatedDisplayLabel(for: timestamp, now: now)
        XCTAssertEqual(label, "Updated 2m ago")
    }

    func testUpdatedDisplayLabelInvalidOrMissingTimestampReturnsFallback() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(ShotHealthModel.updatedDisplayLabel(for: nil, now: now), "Updated -")
        XCTAssertEqual(ShotHealthModel.updatedDisplayLabel(for: "not-a-timestamp", now: now), "Updated -")
    }

    private func makeShot(
        shotName: String,
        state: String,
        totalFrames: Int,
        doneFrames: Int,
        failedFrames: Int,
        inflightFrames: Int,
        lastUpdatedAt: String? = nil
    ) -> ShotSummaryRow {
        ShotSummaryRow(
            shotName: shotName,
            state: state,
            totalFrames: totalFrames,
            doneFrames: doneFrames,
            failedFrames: failedFrames,
            inflightFrames: inflightFrames,
            progressRatio: totalFrames > 0 ? Double(doneFrames) / Double(totalFrames) : 0,
            lastUpdatedAt: lastUpdatedAt,
            assemblyState: nil,
            outputMovPath: nil,
            reviewMovPath: nil,
            exposureOffsetStops: nil,
            wbMultipliers: nil
        )
    }

    private func isoString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
