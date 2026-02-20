import SwiftUI

struct RootStatusBarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            if state.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
            Text(state.statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let error = state.errorMessage, !error.isEmpty {
                Text("•")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    state.presentError(title: "Last Error", message: error)
                } label: {
                    Label("Error", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .fixedSize(horizontal: true, vertical: true)
    }
}
