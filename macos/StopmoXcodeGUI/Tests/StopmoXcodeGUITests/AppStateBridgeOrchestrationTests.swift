import XCTest
@testable import StopmoXcodeGUI

@MainActor
final class AppStateBridgeOrchestrationTests: XCTestCase {
    func testRefreshHealthUsesBridgeService() async {
        let bridge = FakeBridgeService()
        let state = makeState(bridge: bridge)

        await state.refreshHealth()

        XCTAssertEqual(bridge.healthCallCount, 1)
        XCTAssertEqual(state.health?.pythonExecutable, "/usr/bin/python3")
        XCTAssertEqual(state.statusMessage, "Health check completed")
    }

    func testRefreshLiveDataInCaptureRequestsShotsSummary() async {
        let bridge = FakeBridgeService()
        let state = makeState(bridge: bridge)
        state.selectedHub = .capture

        await state.refreshLiveData(silent: true)

        XCTAssertEqual(bridge.watchStateCallCount, 1)
        XCTAssertEqual(bridge.shotsSummaryCallCount, 1)
    }

    func testRefreshLiveDataInTriageQueueSkipsShotsSummary() async {
        let bridge = FakeBridgeService()
        let state = makeState(bridge: bridge)
        state.selectedHub = .triage
        state.selectedTriagePanel = .queue

        await state.refreshLiveData(silent: true)

        XCTAssertEqual(bridge.watchStateCallCount, 1)
        XCTAssertEqual(bridge.shotsSummaryCallCount, 0)
    }

    func testRetryFailedJobsForShotUsesShotMutationBridgeCall() async {
        let bridge = FakeBridgeService()
        let state = makeState(bridge: bridge)

        await state.retryFailedJobsForShot("SHOT_A")

        XCTAssertEqual(bridge.queueRetryShotFailedCallCount, 1)
        XCTAssertEqual(bridge.shotsSummaryCallCount, 1)
        XCTAssertEqual(state.statusMessage, "Retried failed frames for SHOT_A")
    }

    func testRestartShotFromBeginningUsesShotMutationBridgeCall() async {
        let bridge = FakeBridgeService()
        let state = makeState(bridge: bridge)

        await state.restartShotFromBeginning("SHOT_A", cleanOutput: true, resetLocks: true)

        XCTAssertEqual(bridge.queueRestartShotCallCount, 1)
        XCTAssertEqual(bridge.shotsSummaryCallCount, 1)
        XCTAssertEqual(state.statusMessage, "Restarted shot SHOT_A")
    }

    func testDeleteShotUsesShotMutationBridgeCall() async {
        let bridge = FakeBridgeService()
        let state = makeState(bridge: bridge)

        await state.deleteShot("SHOT_A", deleteOutputs: true)

        XCTAssertEqual(bridge.queueDeleteShotCallCount, 1)
        XCTAssertEqual(bridge.shotsSummaryCallCount, 1)
        XCTAssertEqual(state.statusMessage, "Deleted shot SHOT_A")
    }

    func testCreateNewProjectInitializesProjectAndRecordsRecent() async {
        UserDefaults.standard.removeObject(forKey: "framerelay_recent_projects_v1")
        let bridge = FakeBridgeService()
        let state = makeState(bridge: bridge)
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("framerelay-new-project-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        state.newProjectDraft = NewProjectDraft(projectName: "PawPatrol", parentDirectory: parent.path)

        await state.createNewProject()

        XCTAssertEqual(bridge.projectInitCallCount, 1)
        XCTAssertEqual(bridge.readConfigCallCount, 1)
        XCTAssertEqual(bridge.configValidateCallCount, 1)
        XCTAssertEqual(bridge.watchPreflightCallCount, 1)
        XCTAssertEqual(state.repoRoot, parent.appendingPathComponent("PawPatrol", isDirectory: true).path)
        XCTAssertEqual(state.configPath, parent.appendingPathComponent("PawPatrol/config/sample.yaml").path)
        XCTAssertEqual(state.recentProjects.first?.displayName, "PawPatrol")
        XCTAssertFalse(state.isNewProjectSheetPresented)
    }

    func testRunDayWrapBatchDeliveryResolvesRelativePathsAgainstConfig() async {
        let bridge = FakeBridgeService()
        let state = makeState(bridge: bridge)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("framerelay-relative-delivery-\(UUID().uuidString)", isDirectory: true)
        let configPath = root.appendingPathComponent("config/sample.yaml").path
        state.repoRoot = root.path
        state.configPath = configPath
        state.config.watch.outputDir = "../output"

        _ = await state.runDayWrapBatchDelivery(
            inputDir: "../output",
            outputDir: "../delivery",
            framerate: 24,
            overwrite: true
        )

        XCTAssertEqual(bridge.lastDpxInputDir, root.appendingPathComponent("output").path)
        XCTAssertEqual(bridge.lastDpxOutputDir, root.appendingPathComponent("delivery").path)
    }

    func testDeliverShotsToProresResolvesRelativeShotRootsAgainstConfig() async {
        let bridge = FakeBridgeService()
        let state = makeState(bridge: bridge)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("framerelay-relative-shot-\(UUID().uuidString)", isDirectory: true)
        let configPath = root.appendingPathComponent("config/sample.yaml").path
        state.repoRoot = root.path
        state.configPath = configPath
        state.config.watch.outputDir = "../output"

        let outputs = await state.deliverShotsToProres(
            shotInputRoots: ["../output/SHOT_A"],
            framerate: 24,
            overwrite: true,
            outputDir: "../delivery"
        )

        XCTAssertEqual(outputs, ["/tmp/output.mov"])
        XCTAssertEqual(bridge.lastDpxInputDir, root.appendingPathComponent("output/SHOT_A").path)
        XCTAssertEqual(bridge.lastDpxOutputDir, root.appendingPathComponent("delivery").path)
    }

    private func makeState(bridge: FakeBridgeService) -> AppState {
        let deps = AppStateDependencies(
            bridgeService: bridge,
            workspaceConfigService: FakeWorkspaceConfigService(),
            workspaceIOService: WorkspaceIOService(),
            monitoringCoordinatorFactory: { FakeMonitoringCoordinator() }
        )
        return AppState(dependencies: deps)
    }
}

private final class FakeBridgeService: BridgeServicing {
    private(set) var healthCallCount = 0
    private(set) var readConfigCallCount = 0
    private(set) var projectInitCallCount = 0
    private(set) var configValidateCallCount = 0
    private(set) var watchPreflightCallCount = 0
    private(set) var watchStateCallCount = 0
    private(set) var shotsSummaryCallCount = 0
    private(set) var queueRetryShotFailedCallCount = 0
    private(set) var queueRestartShotCallCount = 0
    private(set) var queueDeleteShotCallCount = 0
    private(set) var lastDpxInputDir: String?
    private(set) var lastDpxOutputDir: String?

    func health(repoRoot: String, configPath: String) async throws -> BridgeHealth {
        healthCallCount += 1
        return BridgeHealth(
            backendMode: "dev",
            backendRoot: repoRoot,
            workspaceRoot: repoRoot,
            pythonExecutable: "/usr/bin/python3",
            pythonVersion: "3.11",
            venvPython: "/tmp/.venv/bin/python",
            venvPythonExists: true,
            checks: [:],
            ffmpegPath: nil,
            ffmpegSource: nil,
            stopmoVersion: nil,
            configPath: configPath,
            configExists: true,
            configLoadOk: true,
            configError: nil,
            watchDbPath: nil
        )
    }

    func readConfig(repoRoot: String, configPath: String) async throws -> StopmoConfigDocument {
        readConfigCallCount += 1
        return .empty
    }

    func writeConfig(repoRoot: String, configPath: String, config: StopmoConfigDocument) async throws -> StopmoConfigDocument {
        config
    }

    func projectInit(repoRoot: String, configPath: String) async throws -> ProjectInitResult {
        projectInitCallCount += 1
        return ProjectInitResult(
            configPath: configPath,
            dbPath: "\(repoRoot)/work/queue.sqlite3",
            sourceDir: "\(repoRoot)/incoming",
            workingDir: "\(repoRoot)/work",
            outputDir: "\(repoRoot)/output",
            initialized: true
        )
    }

    func watchStart(repoRoot: String, configPath: String) async throws -> WatchServiceState {
        stubWatchState(configPath: configPath)
    }

    func watchStop(repoRoot: String, configPath: String) async throws -> WatchServiceState {
        stubWatchState(configPath: configPath)
    }

    func watchState(repoRoot: String, configPath: String, limit: Int, tailLines: Int) async throws -> WatchServiceState {
        watchStateCallCount += 1
        return stubWatchState(configPath: configPath)
    }

    func shotsSummary(repoRoot: String, configPath: String, limit: Int) async throws -> ShotsSummarySnapshot {
        shotsSummaryCallCount += 1
        return ShotsSummarySnapshot(
            dbPath: "/tmp/queue.sqlite3",
            count: 1,
            shots: [
                ShotSummaryRow(
                    shotName: "SHOT_A",
                    state: "done",
                    totalFrames: 10,
                    doneFrames: 10,
                    failedFrames: 0,
                    inflightFrames: 0,
                    progressRatio: 1.0,
                    firstShotAt: nil,
                    lastUpdatedAt: "2026-02-27T00:00:00Z",
                    assemblyState: nil,
                    outputMovPath: nil,
                    reviewMovPath: nil,
                    exposureOffsetStops: nil,
                    wbMultipliers: nil
                ),
            ]
        )
    }

    func logsDiagnostics(repoRoot: String, configPath: String, severity: String?, limit: Int) async throws -> LogsDiagnosticsSnapshot {
        LogsDiagnosticsSnapshot(
            configPath: configPath,
            logSources: [],
            entries: [],
            warnings: [],
            queueCounts: [:],
            watchRunning: true,
            watchPid: 123
        )
    }

    func configValidate(repoRoot: String, configPath: String) async throws -> ConfigValidationSnapshot {
        configValidateCallCount += 1
        return ConfigValidationSnapshot(configPath: configPath, ok: true, errors: [], warnings: [])
    }

    func watchPreflight(repoRoot: String, configPath: String) async throws -> WatchPreflight {
        watchPreflightCallCount += 1
        return WatchPreflight(
            configPath: configPath,
            ok: true,
            blockers: [],
            validation: ConfigValidationSnapshot(configPath: configPath, ok: true, errors: [], warnings: []),
            healthChecks: [:]
        )
    }

    func historySummary(repoRoot: String, configPath: String, limit: Int, gapMinutes: Int) async throws -> HistorySummarySnapshot {
        HistorySummarySnapshot(configPath: configPath, dbPath: "/tmp/queue.sqlite3", count: 0, runs: [])
    }

    func dpxToProres(
        repoRoot: String,
        inputDir: String,
        outputDir: String?,
        framerate: Int,
        overwrite: Bool
    ) async throws -> ToolOperationEnvelope {
        lastDpxInputDir = inputDir
        lastDpxOutputDir = outputDir
        return ToolOperationEnvelope(
            operationId: "op-1",
            operation: OperationSnapshotRecord(
                id: "op-1",
                kind: "dpx_to_prores",
                status: "succeeded",
                progress: 1.0,
                createdAtUtc: "2026-02-27T00:00:00Z",
                startedAtUtc: "2026-02-27T00:00:01Z",
                finishedAtUtc: "2026-02-27T00:00:02Z",
                cancelRequested: false,
                cancellable: false,
                error: nil,
                metadata: [:],
                result: ["outputs": .array([.string("/tmp/output.mov")])]
            ),
            events: []
        )
    }

    func copyDiagnosticsBundle(repoRoot: String, configPath: String, outDir: String?) async throws -> DiagnosticsBundleResult {
        DiagnosticsBundleResult(bundlePath: "/tmp/diagnostics.zip", createdAtUtc: "2026-02-27T00:00:00Z", sizeBytes: 1024)
    }

    func queueRetryFailed(repoRoot: String, configPath: String, jobIds: [Int]?) async throws -> QueueRetryResult {
        QueueRetryResult(
            retried: 0,
            requestedIds: jobIds ?? [],
            failedBefore: 0,
            failedAfter: 0,
            queue: stubWatchState(configPath: configPath).queue
        )
    }

    func queueRetryShotFailed(repoRoot: String, configPath: String, shotName: String) async throws -> QueueShotMutationResult {
        queueRetryShotFailedCallCount += 1
        return QueueShotMutationResult(
            action: "retry_shot_failed",
            shotName: shotName,
            jobsTotalBefore: 1,
            jobsChanged: 1,
            failedBefore: 1,
            inflightBefore: 0,
            settingsCleared: false,
            assemblyCleared: false,
            outputsDeleted: false,
            deletedFileCount: 0,
            deletedDirCount: 0,
            queue: stubWatchState(configPath: configPath).queue
        )
    }

    func queueRestartShot(
        repoRoot: String,
        configPath: String,
        shotName: String,
        cleanOutput: Bool,
        resetLocks: Bool
    ) async throws -> QueueShotMutationResult {
        queueRestartShotCallCount += 1
        return QueueShotMutationResult(
            action: "restart_shot",
            shotName: shotName,
            jobsTotalBefore: 4,
            jobsChanged: 4,
            failedBefore: 1,
            inflightBefore: 0,
            settingsCleared: resetLocks,
            assemblyCleared: true,
            outputsDeleted: cleanOutput,
            deletedFileCount: cleanOutput ? 3 : 0,
            deletedDirCount: cleanOutput ? 2 : 0,
            queue: stubWatchState(configPath: configPath).queue
        )
    }

    func queueDeleteShot(
        repoRoot: String,
        configPath: String,
        shotName: String,
        deleteOutputs: Bool
    ) async throws -> QueueShotMutationResult {
        queueDeleteShotCallCount += 1
        return QueueShotMutationResult(
            action: "delete_shot",
            shotName: shotName,
            jobsTotalBefore: 4,
            jobsChanged: 4,
            failedBefore: 1,
            inflightBefore: 0,
            settingsCleared: true,
            assemblyCleared: true,
            outputsDeleted: deleteOutputs,
            deletedFileCount: deleteOutputs ? 3 : 0,
            deletedDirCount: deleteOutputs ? 2 : 0,
            queue: stubWatchState(configPath: configPath).queue
        )
    }

    private func stubWatchState(configPath: String) -> WatchServiceState {
        WatchServiceState(
            running: true,
            pid: 123,
            startedAtUtc: "2026-02-27T00:00:00Z",
            configPath: configPath,
            logPath: nil,
            logTail: [],
            queue: QueueSnapshot(
                dbPath: "/tmp/queue.sqlite3",
                counts: [
                    "detected": 0,
                    "decoding": 0,
                    "xform": 0,
                    "dpx_write": 0,
                    "done": 10,
                    "failed": 0,
                ],
                total: 10,
                recent: []
            ),
            progressRatio: 1.0,
            completedFrames: 10,
            inflightFrames: 0,
            totalFrames: 10,
            startBlocked: false,
            launchError: nil,
            preflight: nil,
            crashRecovery: nil
        )
    }
}

private struct FakeWorkspaceConfigService: WorkspaceConfigServicing {
    func defaultConfigPath(forWorkspaceRoot root: String) -> String {
        "\(root)/config/sample.yaml"
    }

    func resolveInitialRepoRoot(
        environment: [String: String],
        rememberedRepoRoot: String?,
        bundlePath: String?,
        currentDirectoryPath: String
    ) -> String {
        "/tmp/stopmo-gui-tests"
    }

    func discoverRepoRootNear(path: String) -> String? {
        nil
    }

    func isLikelyRepoRoot(path: String) -> Bool {
        false
    }

    func bundledSampleConfigPath(bundleResourceURL: URL?, bundleURL: URL) -> String? {
        nil
    }

    func resolvedSampleConfigSourcePath(
        repoRoot: String,
        environment: [String: String],
        currentDirectoryPath: String,
        bundleSamplePath: String?
    ) -> String? {
        nil
    }

    func writeDefaultConfigTemplate(destination: String, workspaceRoot: String) throws {}

    func bootstrapWorkspaceIfNeeded(workspaceRoot: String, configPath: String) throws -> WorkspaceBootstrapResult {
        WorkspaceBootstrapResult(resolvedConfigPath: configPath, createdConfig: false)
    }
}

@MainActor
private final class FakeMonitoringCoordinator: LiveMonitoringCoordinating {
    var sessionToken = UUID()
    var isRunning: Bool = false

    func start(
        force: Bool,
        onStarted: @escaping (UUID) -> Void,
        onStopped: @escaping () -> Void,
        pollInterval: @escaping () -> Double,
        refresh: @escaping (UUID) async -> Bool
    ) {
        isRunning = true
        onStarted(sessionToken)
    }

    func stop(onStopped: @escaping () -> Void) {
        isRunning = false
        sessionToken = UUID()
        onStopped()
    }
}
