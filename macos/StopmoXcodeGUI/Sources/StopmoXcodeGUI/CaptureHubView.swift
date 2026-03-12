import SwiftUI

/// Top-level capture workspace that hosts live monitoring and capture-side tooling.
struct CaptureHubView: View {
    var body: some View {
        LiveMonitorView(embedded: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
