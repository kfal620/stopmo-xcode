import XCTest
@testable import StopmoXcodeGUI

final class Phase0SmokeTests: XCTestCase {
    func testPrimarySidebarSectionsArePresentAndOrdered() {
        XCTAssertEqual(
            AppSection.allCases.map(\.rawValue),
            [
                "Setup",
                "Project",
                "Live Monitor",
                "Shots",
                "Queue",
                "Tools",
                "Logs & Diagnostics",
                "History",
            ]
        )
    }

    func testSidebarSectionIdentifiersAreUnique() {
        let ids = AppSection.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testSidebarMetadataIsPresent() {
        for section in AppSection.allCases {
            XCTAssertFalse(section.iconName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(section.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    func testInterpretationContractDefaultsRemainStable() {
        let cfg = StopmoConfigDocument.empty
        XCTAssertEqual(cfg.pipeline.targetEi, 800)
        XCTAssertEqual(cfg.pipeline.ocioOutputSpace, "ARRI_LogC3_EI800_AWG")
        XCTAssertTrue(cfg.pipeline.lockWbFromFirstFrame)
    }

    @MainActor
    func testCriticalAppStateActionsRemainCallable() {
        let state = AppState()

        let _: () async -> Void = state.refreshHealth
        let _: () async -> Void = state.loadConfig
        let _: () async -> Void = state.saveConfig
        let _: () async -> Void = state.startWatchService
        let _: () async -> Void = state.stopWatchService
        let _: (Bool) async -> Void = state.refreshLiveData
        let _: (String?) async -> Void = state.refreshLogsDiagnostics
        let _: () async -> Void = state.validateConfig
        let _: () async -> Void = state.refreshWatchPreflight
        let _: () async -> Void = state.refreshHistory
        let _: (String?) async -> Void = state.copyDiagnosticsBundle
        let _: () -> Void = state.chooseWorkspaceDirectory
        let _: () -> Void = state.chooseRepoRootDirectory
        let _: () -> Void = state.chooseConfigFile
    }

    func testCriticalBridgeActionsRemainCallable() {
        let client = BridgeClient()

        let _: (String, String?) throws -> BridgeHealth = client.health
        let _: (String, String) throws -> StopmoConfigDocument = client.readConfig
        let _: (String, String, StopmoConfigDocument) throws -> StopmoConfigDocument = client.writeConfig
        let _: (String, String, Int) throws -> QueueSnapshot = client.queueStatus
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
