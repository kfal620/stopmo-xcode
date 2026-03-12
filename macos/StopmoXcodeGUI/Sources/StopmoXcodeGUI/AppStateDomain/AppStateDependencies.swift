import Foundation

/// Dependency bundle used to construct AppState with live services or targeted test doubles.
struct AppStateDependencies {
    let bridgeService: BridgeServicing
    let workspaceConfigService: WorkspaceConfigServicing
    let workspaceIOService: WorkspaceIOService
    let monitoringCoordinatorFactory: () -> LiveMonitoringCoordinating

    @MainActor
    static let live = AppStateDependencies(
        bridgeService: LiveBridgeService(),
        workspaceConfigService: LiveWorkspaceConfigService(),
        workspaceIOService: WorkspaceIOService(),
        monitoringCoordinatorFactory: { LiveMonitoringCoordinator() }
    )
}
