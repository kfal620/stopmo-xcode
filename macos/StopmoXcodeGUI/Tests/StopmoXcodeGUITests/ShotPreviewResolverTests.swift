import XCTest
@testable import StopmoXcodeGUI

final class ShotPreviewResolverTests: XCTestCase {
    func testResolverReturnsLatestForLatestPolicy() {
        let shot = makeShot(
            previewLatestPath: "/tmp/shot/latest.jpg",
            previewFirstPath: "/tmp/shot/first.jpg"
        )
        let existing = Set(["/tmp/shot/latest.jpg", "/tmp/shot/first.jpg"])

        let resolved = ShotPreviewResolver.preferredPath(
            for: shot,
            preferred: .latest,
            baseOutputDir: "/tmp/out",
            fileExists: { existing.contains($0) }
        )

        XCTAssertEqual(resolved, "/tmp/shot/latest.jpg")
    }

    func testResolverReturnsFirstForFirstPolicy() {
        let shot = makeShot(
            previewLatestPath: "/tmp/shot/latest.jpg",
            previewFirstPath: "/tmp/shot/first.jpg"
        )
        let existing = Set(["/tmp/shot/latest.jpg", "/tmp/shot/first.jpg"])

        let resolved = ShotPreviewResolver.preferredPath(
            for: shot,
            preferred: .first,
            baseOutputDir: "/tmp/out",
            fileExists: { existing.contains($0) }
        )

        XCTAssertEqual(resolved, "/tmp/shot/first.jpg")
    }

    func testResolverFallsBackToAlternateVariant() {
        let shot = makeShot(
            previewLatestPath: "/tmp/shot/latest.jpg",
            previewFirstPath: "/tmp/shot/first.jpg"
        )
        let existing = Set(["/tmp/shot/latest.jpg"])

        let resolved = ShotPreviewResolver.preferredPath(
            for: shot,
            preferred: .first,
            baseOutputDir: "/tmp/out",
            fileExists: { existing.contains($0) }
        )

        XCTAssertEqual(resolved, "/tmp/shot/latest.jpg")
    }

    func testResolverFallsBackToCanonicalPathWhenBridgePathsMissing() {
        let shot = makeShot(previewLatestPath: nil, previewFirstPath: nil)
        let canonicalFirst = "/tmp/out/SHOT_A/preview/first.jpg"

        let resolved = ShotPreviewResolver.preferredPath(
            for: shot,
            preferred: .first,
            baseOutputDir: "/tmp/out",
            fileExists: { $0 == canonicalFirst }
        )

        XCTAssertEqual(resolved, canonicalFirst)
    }

    private func makeShot(previewLatestPath: String?, previewFirstPath: String?) -> ShotSummaryRow {
        ShotSummaryRow(
            shotName: "SHOT_A",
            state: "done",
            totalFrames: 10,
            doneFrames: 10,
            failedFrames: 0,
            inflightFrames: 0,
            progressRatio: 1.0,
            previewLatestPath: previewLatestPath,
            previewFirstPath: previewFirstPath
        )
    }
}
