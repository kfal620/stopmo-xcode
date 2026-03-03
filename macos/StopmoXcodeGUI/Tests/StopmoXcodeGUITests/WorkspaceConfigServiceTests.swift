import XCTest
@testable import StopmoXcodeGUI

final class WorkspaceConfigServiceTests: XCTestCase {
    private let service = LiveWorkspaceConfigService()

    func testDefaultConfigPathUsesWorkspaceRoot() {
        XCTAssertEqual(
            service.defaultConfigPath(forWorkspaceRoot: "/tmp/workspace"),
            "/tmp/workspace/config/sample.yaml"
        )
    }

    func testDiscoverRepoRootNearFindsPyprojectAndModuleDirectory() throws {
        let root = try makeTempDirectory()
        let pyproject = URL(fileURLWithPath: root).appendingPathComponent("pyproject.toml")
        let moduleDir = URL(fileURLWithPath: root).appendingPathComponent("src/stopmo_xcode", isDirectory: true)
        try "name='stopmo-xcode'\n".write(to: pyproject, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: moduleDir, withIntermediateDirectories: true)

        let nested = URL(fileURLWithPath: root).appendingPathComponent("macos/StopmoXcodeGUI/Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let discovered = service.discoverRepoRootNear(path: nested.path)
        XCTAssertEqual(discovered, root)
    }

    func testResolveInitialRepoRootPrefersFrameRelayWorkspaceEnv() {
        let resolved = service.resolveInitialRepoRoot(
            environment: ["FRAMERELAY_WORKSPACE_ROOT": "/tmp/env-workspace"],
            rememberedRepoRoot: "/tmp/remembered",
            bundlePath: nil,
            currentDirectoryPath: "/tmp/cwd"
        )
        XCTAssertEqual(resolved, "/tmp/env-workspace")
    }

    func testResolveInitialRepoRootFallsBackToLegacyWorkspaceEnv() {
        let resolved = service.resolveInitialRepoRoot(
            environment: ["STOPMO_XCODE_WORKSPACE_ROOT": "/tmp/legacy-workspace"],
            rememberedRepoRoot: "/tmp/remembered",
            bundlePath: nil,
            currentDirectoryPath: "/tmp/cwd"
        )
        XCTAssertEqual(resolved, "/tmp/legacy-workspace")
    }

    func testBootstrapWorkspaceCreatesConfigWhenMissing() throws {
        let root = try makeTempDirectory()
        let requestedConfig = "\(root)/config/sample.yaml"

        let result = try service.bootstrapWorkspaceIfNeeded(workspaceRoot: root, configPath: requestedConfig)

        XCTAssertEqual(result.resolvedConfigPath, requestedConfig)
        XCTAssertTrue(result.createdConfig)
        XCTAssertTrue(FileManager.default.fileExists(atPath: requestedConfig))
    }

    private func makeTempDirectory() throws -> String {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("stopmo-gui-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.path
    }
}
