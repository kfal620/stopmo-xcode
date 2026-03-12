import SwiftUI

/// Top-level configure workspace that now renders as one unified setup canvas.
struct ConfigureHubView: View {
    var body: some View {
        ConfigureWorkspaceView()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
