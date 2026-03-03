import SwiftUI

/// View rendering root status bar view.
struct RootStatusBarView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPresented: Bool = false
    @State private var hasPresentedNonReadyStatus: Bool = false
    @State private var dismissTask: Task<Void, Never>?
    private static let fadeDelayNanoseconds: UInt64 = 3_500_000_000

    var body: some View {
        Group {
            if isPresented {
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
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isPresented)
        .onAppear {
            refreshPresentation()
        }
        .onChange(of: state.statusMessage) { _, _ in
            refreshPresentation()
        }
        .onChange(of: state.isBusy) { _, _ in
            refreshPresentation()
        }
        .onChange(of: state.errorMessage) { _, _ in
            refreshPresentation()
        }
        .onDisappear {
            dismissTask?.cancel()
            dismissTask = nil
        }
    }

    private func refreshPresentation() {
        let trimmedStatus = state.statusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasError = (state.errorMessage?.isEmpty == false)
        let isReadyState = trimmedStatus.isEmpty || trimmedStatus == "Ready"

        if !hasPresentedNonReadyStatus {
            if state.isBusy || hasError || !isReadyState {
                hasPresentedNonReadyStatus = true
            } else {
                dismissTask?.cancel()
                dismissTask = nil
                setPresented(false)
                return
            }
        }

        setPresented(true)

        guard !state.isBusy else {
            dismissTask?.cancel()
            dismissTask = nil
            return
        }

        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: Self.fadeDelayNanoseconds)
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                guard !state.isBusy else {
                    return
                }
                setPresented(false)
                dismissTask = nil
            }
        }
    }

    private func setPresented(_ nextValue: Bool) {
        guard isPresented != nextValue else {
            return
        }
        if reduceMotion {
            isPresented = nextValue
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                isPresented = nextValue
            }
        }
    }
}
