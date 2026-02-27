import XCTest
@testable import StopmoXcodeGUI

final class QueueFilterReducerTests: XCTestCase {
    func testFiltersFailedRows() {
        let jobs = [
            makeJob(id: 1, state: "failed", shot: "A", attempts: 1),
            makeJob(id: 2, state: "done", shot: "B", attempts: 1),
        ]

        let filtered = QueueFilterReducer.filteredJobs(
            jobs: jobs,
            searchText: "",
            stateFilter: .failed,
            sort: .updatedDesc,
            showOnlySelected: false,
            selectedJobIDs: []
        )

        XCTAssertEqual(filtered.map(\.id), [1])
    }

    func testSearchMatchesShotOrError() {
        let jobs = [
            makeJob(id: 1, state: "done", shot: "PAW_001", attempts: 1, lastError: nil),
            makeJob(id: 2, state: "failed", shot: "PAW_002", attempts: 1, lastError: "decode failed"),
        ]

        let searchShot = QueueFilterReducer.filteredJobs(
            jobs: jobs,
            searchText: "paw_001",
            stateFilter: .all,
            sort: .updatedDesc,
            showOnlySelected: false,
            selectedJobIDs: []
        )
        XCTAssertEqual(searchShot.map(\.id), [1])

        let searchError = QueueFilterReducer.filteredJobs(
            jobs: jobs,
            searchText: "decode",
            stateFilter: .all,
            sort: .updatedDesc,
            showOnlySelected: false,
            selectedJobIDs: []
        )
        XCTAssertEqual(searchError.map(\.id), [2])
    }

    func testSortByAttemptsDescThenUpdated() {
        let jobs = [
            makeJob(id: 1, state: "failed", shot: "A", attempts: 2, updatedAt: "2026-02-26T10:00:00Z"),
            makeJob(id: 2, state: "failed", shot: "A", attempts: 3, updatedAt: "2026-02-26T09:00:00Z"),
            makeJob(id: 3, state: "failed", shot: "A", attempts: 2, updatedAt: "2026-02-26T11:00:00Z"),
        ]

        let filtered = QueueFilterReducer.filteredJobs(
            jobs: jobs,
            searchText: "",
            stateFilter: .all,
            sort: .attemptsDesc,
            showOnlySelected: false,
            selectedJobIDs: []
        )

        XCTAssertEqual(filtered.map(\.id), [2, 3, 1])
    }

    func testPaginateReturnsClampedPageAndRange() {
        let page = QueueFilterReducer.paginate(filteredCount: 210, pageSize: 100, pageIndex: 99)
        XCTAssertEqual(page.safePageIndex, 2)
        XCTAssertEqual(page.pageCount, 3)
        XCTAssertEqual(page.pageRangeLabel, "Rows 201-210")
    }

    private func makeJob(
        id: Int,
        state: String,
        shot: String,
        attempts: Int,
        updatedAt: String = "2026-02-26T12:00:00Z",
        lastError: String? = nil
    ) -> QueueJobRecord {
        QueueJobRecord(
            id: id,
            state: state,
            shot: shot,
            frame: id,
            source: "/tmp/\(shot)_\(id).cr3",
            attempts: attempts,
            lastError: lastError,
            workerId: "w1",
            detectedAt: "2026-02-26T08:00:00Z",
            updatedAt: updatedAt
        )
    }
}
