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
    }
}
