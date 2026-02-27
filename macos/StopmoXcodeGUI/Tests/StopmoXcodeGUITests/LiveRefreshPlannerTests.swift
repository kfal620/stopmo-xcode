import XCTest
@testable import StopmoXcodeGUI

final class LiveRefreshPlannerTests: XCTestCase {
    func testRefreshKindMappingByHubAndPanel() {
        XCTAssertEqual(
            LiveRefreshPlanner.refreshKind(
                selectedHub: .configure,
                selectedConfigurePanel: .workspaceHealth,
                selectedTriagePanel: .shots,
                selectedDeliverPanel: .dayWrap
            ),
            .health
        )
        XCTAssertEqual(
            LiveRefreshPlanner.refreshKind(
                selectedHub: .triage,
                selectedConfigurePanel: .projectSettings,
                selectedTriagePanel: .diagnostics,
                selectedDeliverPanel: .dayWrap
            ),
            .logs
        )
        XCTAssertEqual(
            LiveRefreshPlanner.refreshKind(
                selectedHub: .deliver,
                selectedConfigurePanel: .projectSettings,
                selectedTriagePanel: .shots,
                selectedDeliverPanel: .runHistory
            ),
            .history
        )
    }

    func testMonitorSelectionRules() {
        XCTAssertTrue(LiveRefreshPlanner.shouldMonitor(selectedHub: .capture, selectedTriagePanel: .shots))
        XCTAssertTrue(LiveRefreshPlanner.shouldMonitor(selectedHub: .triage, selectedTriagePanel: .queue))
        XCTAssertFalse(LiveRefreshPlanner.shouldMonitor(selectedHub: .triage, selectedTriagePanel: .diagnostics))
        XCTAssertFalse(LiveRefreshPlanner.shouldMonitor(selectedHub: .deliver, selectedTriagePanel: .shots))
    }

    func testSnapshotFetchLimitsBySelection() {
        let capture = LiveRefreshPlanner.snapshotFetchLimits(selectedHub: .capture, selectedTriagePanel: .shots)
        XCTAssertEqual(capture, LiveSnapshotFetchLimits(queueLimit: 220, logTailLines: 60, includeShots: true, shotsLimit: 120))

        let triageQueue = LiveRefreshPlanner.snapshotFetchLimits(selectedHub: .triage, selectedTriagePanel: .queue)
        XCTAssertEqual(triageQueue, LiveSnapshotFetchLimits(queueLimit: 350, logTailLines: 40, includeShots: false, shotsLimit: 0))

        let deliver = LiveRefreshPlanner.snapshotFetchLimits(selectedHub: .deliver, selectedTriagePanel: .shots)
        XCTAssertEqual(deliver, LiveSnapshotFetchLimits(queueLimit: 220, logTailLines: 40, includeShots: false, shotsLimit: 0))
    }
}
