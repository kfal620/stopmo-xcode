import XCTest
@testable import StopmoXcodeGUI

final class ReviewWorkspaceReducerTests: XCTestCase {
    func testGroupedSectionsFollowPriorityOrder() {
        let sections = ReviewWorkspaceReducer.groupedSections(
            snapshot: sampleSnapshot,
            filter: .all,
            searchText: ""
        )

        XCTAssertEqual(sections.map(\.kind), [.issues, .inflight, .ready, .completed])
    }

    func testResolvedSelectionPrefersIssuesThenInflightThenReady() {
        let sections = ReviewWorkspaceReducer.groupedSections(
            snapshot: sampleSnapshot,
            filter: .all,
            searchText: ""
        )

        XCTAssertEqual(
            ReviewWorkspaceReducer.resolvedSelection(currentSelection: nil, sections: sections),
            "SHOT_ISSUE"
        )
    }

    func testResolvedSelectionKeepsExistingSelectionWhenStillPresent() {
        let sections = ReviewWorkspaceReducer.groupedSections(
            snapshot: sampleSnapshot,
            filter: .all,
            searchText: ""
        )

        XCTAssertEqual(
            ReviewWorkspaceReducer.resolvedSelection(currentSelection: "SHOT_READY", sections: sections),
            "SHOT_READY"
        )
    }

    func testReadyFilterIncludesDeliverableShotsAndSearchNarrowsResults() {
        let readySections = ReviewWorkspaceReducer.groupedSections(
            snapshot: sampleSnapshot,
            filter: .ready,
            searchText: ""
        )

        XCTAssertEqual(readySections.map(\.kind), [.ready, .completed])

        let filtered = ReviewWorkspaceReducer.groupedSections(
            snapshot: sampleSnapshot,
            filter: .all,
            searchText: "completed"
        )
        XCTAssertEqual(filtered.map(\.kind), [.completed])
        XCTAssertEqual(filtered.first?.evaluations.first?.shot.shotName, "SHOT_COMPLETED")
    }

    private var sampleSnapshot: ShotsSummarySnapshot {
        ShotsSummarySnapshot(
            dbPath: "/tmp/queue.sqlite3",
            count: 4,
            shots: [
                makeShot(
                    name: "SHOT_ISSUE",
                    state: "failed",
                    totalFrames: 24,
                    doneFrames: 20,
                    failedFrames: 4,
                    inflightFrames: 0,
                    lastUpdatedAt: "2026-03-12T10:03:00Z"
                ),
                makeShot(
                    name: "SHOT_INFLIGHT",
                    state: "processing",
                    totalFrames: 48,
                    doneFrames: 12,
                    failedFrames: 0,
                    inflightFrames: 3,
                    lastUpdatedAt: "2026-03-12T10:02:00Z"
                ),
                makeShot(
                    name: "SHOT_READY",
                    state: "done",
                    totalFrames: 16,
                    doneFrames: 16,
                    failedFrames: 0,
                    inflightFrames: 0,
                    lastUpdatedAt: "2026-03-12T10:01:00Z"
                ),
                makeShot(
                    name: "SHOT_COMPLETED",
                    state: "done",
                    totalFrames: 12,
                    doneFrames: 12,
                    failedFrames: 0,
                    inflightFrames: 0,
                    lastUpdatedAt: "2026-03-12T10:00:00Z",
                    outputMovPath: "/tmp/completed.mov"
                ),
            ]
        )
    }

    private func makeShot(
        name: String,
        state: String,
        totalFrames: Int,
        doneFrames: Int,
        failedFrames: Int,
        inflightFrames: Int,
        lastUpdatedAt: String,
        outputMovPath: String? = nil
    ) -> ShotSummaryRow {
        ShotSummaryRow(
            shotName: name,
            state: state,
            totalFrames: totalFrames,
            doneFrames: doneFrames,
            failedFrames: failedFrames,
            inflightFrames: inflightFrames,
            progressRatio: totalFrames == 0 ? 0 : Double(doneFrames) / Double(totalFrames),
            firstShotAt: "2026-03-12T09:00:00Z",
            lastUpdatedAt: lastUpdatedAt,
            assemblyState: nil,
            outputMovPath: outputMovPath,
            reviewMovPath: nil,
            exposureOffsetStops: 0,
            wbMultipliers: [1.0, 1.0, 1.0],
            previewLatestPath: nil,
            previewFirstPath: nil,
            previewFirstFrameNumber: nil,
            previewLatestUpdatedAt: nil
        )
    }
}
