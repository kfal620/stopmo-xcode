import XCTest
@testable import StopmoXcodeGUI

final class PathTimestampHelpersTests: XCTestCase {
    func testResolveFilesystemPathUsesConfigDirectoryForRelativePaths() {
        let resolved = PathTimestampHelpers.resolveFilesystemPath(
            "../output",
            configPath: "/tmp/project/config/sample.yaml",
            workspaceRoot: "/tmp/project"
        )

        XCTAssertEqual(resolved, "/tmp/project/output")
    }

    func testShotRootPathUsesResolvedOutputDirectory() {
        let resolved = PathTimestampHelpers.shotRootPath(
            baseOutputDir: "../output",
            shotName: "SHOT_A",
            configPath: "/tmp/project/config/sample.yaml",
            workspaceRoot: "/tmp/project"
        )

        XCTAssertEqual(resolved, "/tmp/project/output/SHOT_A")
    }
}
