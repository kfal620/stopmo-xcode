import Foundation

/// Data/view model for app state dependencies.
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
