import XCTest
@testable import StopmoXcodeGUI

final class ToolsPreflightReducerTests: XCTestCase {
    func testTranscodePreflightBlocksMissingInput() {
        let preflight = ToolsPreflightReducer.transcode(
            inputPath: "",
            outputDir: "",
            pathExists: { _ in false }
        )

        XCTAssertFalse(preflight.ok)
        XCTAssertEqual(preflight.blockers, ["Input RAW frame path is required."])
    }

    func testMatrixPreflightWarnsWhenReportParentMissing() {
        let preflight = ToolsPreflightReducer.matrix(
            inputPath: "/tmp/frame.cr2",
            writeJsonPath: "/missing/report.json",
            pathExists: { $0 == "/tmp/frame.cr2" }
        )

        XCTAssertTrue(preflight.blockers.isEmpty)
        XCTAssertEqual(preflight.warnings, ["JSON report parent folder does not exist."])
    }

    func testDpxPreflightWarnsWhenNoDpxFound() {
        let preflight = ToolsPreflightReducer.dpx(
            inputDir: "/tmp/input",
            outputDir: "",
            pathExists: { $0 == "/tmp/input" },
            dpxCount: { _ in 0 }
        )

        XCTAssertTrue(preflight.blockers.isEmpty)
        XCTAssertEqual(preflight.warnings, ["No .dpx files were found under the input directory."])
    }
}
