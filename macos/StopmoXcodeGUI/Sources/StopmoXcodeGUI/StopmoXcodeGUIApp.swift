import SwiftUI

@main
/// Main FrameRelay app entry point that wires shared state into the root window scene.
struct StopmoXcodeGUIApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("FrameRelay") {
            RootView()
                .environmentObject(state)
                .preferredColorScheme(.light)
                .frame(minWidth: 1120, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("FrameRelay") {
                Button("Start Watch") {
                    Task { await state.startWatchService() }
                }
                .keyboardShortcut("s", modifiers: [.command, .option])

                Button("Stop Watch") {
                    Task { await state.stopWatchService() }
                }
                .keyboardShortcut(".", modifiers: [.command, .option])

                Divider()

                Button("Refresh Current Panel") {
                    Task { await state.refreshCurrentSelection() }
                }
                .keyboardShortcut("r", modifiers: [.command, .option])

                Button("Validate Config") {
                    Task { await state.validateConfig() }
                }
                .keyboardShortcut("v", modifiers: [.command, .option])

                Button("Check Runtime Health") {
                    Task { await state.refreshHealth() }
                }
                .keyboardShortcut("h", modifiers: [.command, .option])
            }

            CommandMenu("Navigate") {
                Button(LifecycleHub.configure.displayTitle) { state.selectedHub = .configure }
                    .keyboardShortcut("1", modifiers: [.command])
                Button(LifecycleHub.capture.displayTitle) { state.selectedHub = .capture }
                    .keyboardShortcut("2", modifiers: [.command])
                Button(LifecycleHub.triage.displayTitle) { state.selectedHub = .triage }
                    .keyboardShortcut("3", modifiers: [.command])
                Button(LifecycleHub.deliver.displayTitle) { state.selectedHub = .deliver }
                    .keyboardShortcut("4", modifiers: [.command])

                Divider()

                Menu("Configure Panels") {
                    Button(ConfigurePanel.projectSettings.displayTitle) {
                        state.selectedHub = .configure
                        state.selectedConfigurePanel = .projectSettings
                    }
                    Button(ConfigurePanel.workspaceHealth.displayTitle) {
                        state.selectedHub = .configure
                        state.selectedConfigurePanel = .workspaceHealth
                    }
                    Button(ConfigurePanel.calibration.displayTitle) {
                        state.selectedHub = .configure
                        state.selectedConfigurePanel = .calibration
                    }
                }

                Menu("Review Workspaces") {
                    Button(TriagePanel.shots.displayTitle) {
                        state.selectedHub = .triage
                        state.selectedTriagePanel = .shots
                    }
                    Button("Queue Workspace") {
                        state.selectedHub = .triage
                        state.selectedTriagePanel = .queue
                    }
                    Button("Diagnostics Workspace") {
                        state.selectedHub = .triage
                        state.selectedTriagePanel = .diagnostics
                    }
                }

                Menu("Deliver Panels") {
                    Button("Day Wrap") {
                        state.selectedHub = .deliver
                        state.selectedDeliverPanel = .dayWrap
                    }
                    Button("Run History") {
                        state.selectedHub = .deliver
                        state.selectedDeliverPanel = .runHistory
                    }
                }
            }
        }
    }
}
