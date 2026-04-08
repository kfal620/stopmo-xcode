import XCTest
@testable import StopmoXcodeGUI

final class BridgeClientTests: XCTestCase {
    func testDpxToProresIgnoresSuccessfulStderrWarnings() throws {
        let repoRoot = resolvedRepoRoot()
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let inputRoot = tempRoot.appendingPathComponent("delivery-input", isDirectory: true)
        let dpxDir = inputRoot.appendingPathComponent("PAWPATROL_00218_AN4_X1/dpx", isDirectory: true)
        let fakeFfmpeg = tempRoot.appendingPathComponent("fake-ffmpeg")

        try FileManager.default.createDirectory(at: dpxDir, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: dpxDir.appendingPathComponent("PAWPATROL_00218_AN4_X1_0001.dpx").path,
            contents: Data(),
            attributes: nil
        )
        try "#!/bin/sh\nexit 0\n".write(to: fakeFfmpeg, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fakeFfmpeg.path
        )
        setenv("STOPMO_XCODE_FFMPEG", fakeFfmpeg.path, 1)
        defer {
            unsetenv("STOPMO_XCODE_FFMPEG")
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let envelope = try BridgeClient().dpxToProres(
            repoRoot: repoRoot,
            inputDir: inputRoot.path,
            outputDir: nil,
            framerate: 24,
            overwrite: true
        )

        XCTAssertEqual(envelope.operation.kind, "dpx_to_prores")
        XCTAssertEqual(envelope.operation.status, "succeeded")
        XCTAssertEqual(envelope.operation.result?["count"]?.intValue, 1)
    }

    private func resolvedRepoRoot(filePath: String = #filePath) -> String {
        var url = URL(fileURLWithPath: filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url.path
    }
}
