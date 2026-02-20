import XCTest
@testable import StopmoXcodeGUI

final class Phase0SmokeTests: XCTestCase {
    func testPrimarySidebarSectionsArePresentAndOrdered() {
        XCTAssertEqual(
            LifecycleHub.allCases.map(\.rawValue),
            [
                "Configure",
                "Capture",
                "Triage",
                "Deliver",
            ]
        )
    }

    func testSidebarSectionIdentifiersAreUnique() {
        let ids = LifecycleHub.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testSidebarMetadataIsPresent() {
        for hub in LifecycleHub.allCases {
            XCTAssertFalse(hub.iconName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(hub.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    func testLifecyclePanelsArePresent() {
        XCTAssertEqual(ConfigurePanel.allCases.map(\.rawValue), ["Project Settings", "Workspace & Health", "Calibration"])
        XCTAssertEqual(TriagePanel.allCases.map(\.rawValue), ["Shots", "Queue", "Diagnostics"])
        XCTAssertEqual(DeliverPanel.allCases.map(\.rawValue), ["Day Wrap", "Run History"])
    }

    func testInterpretationContractDefaultsRemainStable() {
        let cfg = StopmoConfigDocument.empty
        XCTAssertEqual(cfg.pipeline.targetEi, 800)
        XCTAssertEqual(cfg.pipeline.ocioOutputSpace, "ARRI_LogC3_EI800_AWG")
        XCTAssertTrue(cfg.pipeline.lockWbFromFirstFrame)
    }

    @MainActor
    func testErrorCreatesNotificationWithActionableContext() {
        let state = AppState()
        state.presentError(title: "Bridge Failure", message: "No module named stopmo_xcode")

        XCTAssertEqual(state.notifications.count, 1)
        XCTAssertEqual(state.notifications.first?.kind, .error)
        XCTAssertNotNil(state.notifications.first?.likelyCause)
        XCTAssertNotNil(state.notifications.first?.suggestedAction)
        XCTAssertNotNil(state.presentedError)
    }

    @MainActor
    func testRefreshDispatchMappingByHubPanel() {
        let state = AppState()

        state.selectedHub = .configure
        state.selectedConfigurePanel = .workspaceHealth
        XCTAssertEqual(state.refreshKindForCurrentSelection(), .health)

        state.selectedConfigurePanel = .projectSettings
        XCTAssertEqual(state.refreshKindForCurrentSelection(), .config)

        state.selectedConfigurePanel = .calibration
        XCTAssertEqual(state.refreshKindForCurrentSelection(), .config)

        state.selectedHub = .capture
        XCTAssertEqual(state.refreshKindForCurrentSelection(), .live)

        state.selectedHub = .triage
        state.selectedTriagePanel = .shots
        XCTAssertEqual(state.refreshKindForCurrentSelection(), .live)

        state.selectedTriagePanel = .queue
        XCTAssertEqual(state.refreshKindForCurrentSelection(), .live)

        state.selectedTriagePanel = .diagnostics
        XCTAssertEqual(state.refreshKindForCurrentSelection(), .logs)

        state.selectedHub = .deliver
        state.selectedDeliverPanel = .dayWrap
        XCTAssertEqual(state.refreshKindForCurrentSelection(), .dayWrap)

        state.selectedDeliverPanel = .runHistory
        XCTAssertEqual(state.refreshKindForCurrentSelection(), .history)
    }

    @MainActor
    func testMonitoringEnablementRulesByHubPanel() {
        let state = AppState()

        state.selectedHub = .capture
        XCTAssertTrue(state.shouldMonitorCurrentSelection())

        state.selectedHub = .triage
        state.selectedTriagePanel = .shots
        XCTAssertTrue(state.shouldMonitorCurrentSelection())

        state.selectedTriagePanel = .queue
        XCTAssertTrue(state.shouldMonitorCurrentSelection())

        state.selectedTriagePanel = .diagnostics
        XCTAssertFalse(state.shouldMonitorCurrentSelection())

        state.selectedHub = .configure
        XCTAssertFalse(state.shouldMonitorCurrentSelection())

        state.selectedHub = .deliver
        XCTAssertFalse(state.shouldMonitorCurrentSelection())
    }

    func testToolsModeFiltersAndPrefillHelpers() {
        XCTAssertEqual(
            ToolsView.visibleToolKinds(for: .utilitiesOnly),
            [.transcodeOne, .suggestMatrix]
        )
        XCTAssertEqual(
            ToolsView.visibleToolKinds(for: .deliveryOnly),
            [.dpxToProres]
        )

        XCTAssertEqual(
            ToolsView.resolvedDpxInputDir(currentInputDir: "", configOutputDir: "/shots/output"),
            "/shots/output"
        )
        XCTAssertEqual(
            ToolsView.resolvedDpxInputDir(currentInputDir: "/custom/dpx", configOutputDir: "/shots/output"),
            "/custom/dpx"
        )
    }

    @MainActor
    func testCriticalAppStateActionsRemainCallable() {
        let state = AppState()

        let _: () async -> Void = state.refreshHealth
        let _: () async -> Void = state.loadConfig
        let _: (StopmoConfigDocument?) async -> Void = state.saveConfig
        let _: () async -> Void = state.startWatchService
        let _: () async -> Void = state.stopWatchService
        let _: () async -> Void = state.restartWatchService
        let _: (Bool) async -> Void = state.refreshLiveData
        let _: () async -> Void = state.refreshCurrentSelection
        let _: (String?) async -> Void = state.refreshLogsDiagnostics
        let _: () async -> Void = state.validateConfig
        let _: () async -> Void = state.refreshWatchPreflight
        let _: () async -> Void = state.refreshHistory
        let _: (String?) async -> Void = state.copyDiagnosticsBundle
        let _: ([Int]?) async -> Void = state.retryFailedQueueJobs
        let _: () -> Void = state.exportQueueSnapshot
        let _: () -> Void = state.chooseWorkspaceDirectory
        let _: () -> Void = state.chooseRepoRootDirectory
        let _: () -> Void = state.chooseConfigFile
        let _: () -> Void = state.useSampleConfig
        let _: () -> Void = state.createConfigFromSample
        let _: () -> Void = state.openConfigInFinder
        let _: (String) -> Void = state.openPathInFinder
        let _: (String, String) -> Void = state.copyTextToPasteboard
        let _: () -> Void = state.restartMonitoringLoop
        let _: () -> Void = state.updateMonitoringForSelection
        let _: () -> AppState.RefreshKind = state.refreshKindForCurrentSelection
        let _: () -> Bool = state.shouldMonitorCurrentSelection
    }

    func testCriticalBridgeActionsRemainCallable() {
        let client = BridgeClient()

        let _: (String, String?) throws -> BridgeHealth = client.health
        let _: (String, String) throws -> StopmoConfigDocument = client.readConfig
        let _: (String, String, StopmoConfigDocument) throws -> StopmoConfigDocument = client.writeConfig
        let _: (String, String, Int) throws -> QueueSnapshot = client.queueStatus
        let _: (String, String, [Int]?) throws -> QueueRetryResult = client.queueRetryFailed
        let _: (String, String, Int) throws -> ShotsSummarySnapshot = client.shotsSummary
        let _: (String, String) throws -> WatchServiceState = client.watchStart
        let _: (String, String, Double) throws -> WatchServiceState = client.watchStop
        let _: (String, String, Int, Int) throws -> WatchServiceState = client.watchState
        let _: (String, String) throws -> ConfigValidationSnapshot = client.configValidate
        let _: (String, String) throws -> WatchPreflight = client.watchPreflight
        let _: (String, String, String, String?) throws -> ToolOperationEnvelope = client.transcodeOne
        let _: (String, String, String?, String?, String?) throws -> ToolOperationEnvelope = client.suggestMatrix
        let _: (String, String, String?, Int, Bool) throws -> ToolOperationEnvelope = client.dpxToProres
        let _: (String, String, String?, Int) throws -> LogsDiagnosticsSnapshot = client.logsDiagnostics
        let _: (String, String, Int, Int) throws -> HistorySummarySnapshot = client.historySummary
        let _: (String, String, String?) throws -> DiagnosticsBundleResult = client.copyDiagnosticsBundle
    }
}
