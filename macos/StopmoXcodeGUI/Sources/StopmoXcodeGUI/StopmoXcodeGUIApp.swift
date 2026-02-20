import SwiftUI

@main
struct StopmoXcodeGUIApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("stopmo-xcode GUI") {
            RootView()
                .environmentObject(state)
                .frame(minWidth: 1120, minHeight: 760)
        }
        .commands {
            CommandMenu("Stopmo") {
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
                Button("Configure") { state.selectedHub = .configure }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("Capture") { state.selectedHub = .capture }
                    .keyboardShortcut("2", modifiers: [.command])
                Button("Triage") { state.selectedHub = .triage }
                    .keyboardShortcut("3", modifiers: [.command])
                Button("Deliver") { state.selectedHub = .deliver }
                    .keyboardShortcut("4", modifiers: [.command])

                Divider()

                Menu("Configure Panels") {
                    Button("Project Settings") {
                        state.selectedHub = .configure
                        state.selectedConfigurePanel = .projectSettings
                    }
                    Button("Workspace & Health") {
                        state.selectedHub = .configure
                        state.selectedConfigurePanel = .workspaceHealth
                    }
                    Button("Calibration") {
                        state.selectedHub = .configure
                        state.selectedConfigurePanel = .calibration
                    }
                }

                Menu("Triage Panels") {
                    Button("Shots") {
                        state.selectedHub = .triage
                        state.selectedTriagePanel = .shots
                    }
                    Button("Queue") {
                        state.selectedHub = .triage
                        state.selectedTriagePanel = .queue
                    }
                    Button("Diagnostics") {
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
