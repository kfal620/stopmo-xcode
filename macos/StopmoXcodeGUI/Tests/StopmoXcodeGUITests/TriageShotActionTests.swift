import XCTest
@testable import StopmoXcodeGUI

final class TriageShotActionTests: XCTestCase {
    func testQueueShotMutationResultDecodesFromBridgePayload() throws {
        let json = """
        {
          "action": "restart_shot",
          "shot_name": "PAWPATROL_00104_AN0_X1",
          "jobs_total_before": 128,
          "jobs_changed": 128,
          "failed_before": 4,
          "inflight_before": 0,
          "settings_cleared": true,
          "assembly_cleared": true,
          "outputs_deleted": true,
          "deleted_file_count": 42,
          "deleted_dir_count": 4,
          "queue": {
            "db_path": "/tmp/queue.sqlite3",
            "counts": {"detected": 128, "failed": 0},
            "total": 128,
            "recent": []
          }
        }
        """
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(QueueShotMutationResult.self, from: data)

        XCTAssertEqual(decoded.action, "restart_shot")
        XCTAssertEqual(decoded.shotName, "PAWPATROL_00104_AN0_X1")
        XCTAssertEqual(decoded.jobsTotalBefore, 128)
        XCTAssertEqual(decoded.jobsChanged, 128)
        XCTAssertEqual(decoded.failedBefore, 4)
        XCTAssertEqual(decoded.inflightBefore, 0)
        XCTAssertTrue(decoded.settingsCleared)
        XCTAssertTrue(decoded.assemblyCleared)
        XCTAssertTrue(decoded.outputsDeleted)
        XCTAssertEqual(decoded.deletedFileCount, 42)
        XCTAssertEqual(decoded.deletedDirCount, 4)
        XCTAssertEqual(decoded.queue.total, 128)
    }
}
