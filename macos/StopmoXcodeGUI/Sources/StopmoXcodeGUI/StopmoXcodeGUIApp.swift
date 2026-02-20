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

                Button("Refresh Current Section") {
                    Task { await refreshCurrentSection() }
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
                Button("Setup") { state.selectedSection = .setup }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("Project") { state.selectedSection = .project }
                    .keyboardShortcut("2", modifiers: [.command])
                Button("Live Monitor") { state.selectedSection = .liveMonitor }
                    .keyboardShortcut("3", modifiers: [.command])
                Button("Shots") { state.selectedSection = .shots }
                    .keyboardShortcut("4", modifiers: [.command])
                Button("Queue") { state.selectedSection = .queue }
                    .keyboardShortcut("5", modifiers: [.command])
                Button("Tools") { state.selectedSection = .tools }
                    .keyboardShortcut("6", modifiers: [.command])
                Button("Logs & Diagnostics") { state.selectedSection = .logs }
                    .keyboardShortcut("7", modifiers: [.command])
                Button("History") { state.selectedSection = .history }
                    .keyboardShortcut("8", modifiers: [.command])
            }
        }
    }

    private func refreshCurrentSection() async {
        switch state.selectedSection {
        case .setup:
            await state.refreshHealth()
        case .project:
            await state.loadConfig()
        case .liveMonitor, .queue, .shots:
            await state.refreshLiveData()
        case .tools:
            await state.refreshLiveData()
        case .logs:
            await state.refreshLogsDiagnostics()
        case .history:
            await state.refreshHistory()
        }
    }
}
