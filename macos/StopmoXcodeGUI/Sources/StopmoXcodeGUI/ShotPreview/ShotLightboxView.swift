import AppKit
import SwiftUI

/// Sheet item payload for preview lightbox presentation.
struct ShotLightboxItem: Identifiable {
    let shot: ShotSummaryRow
    let previewKind: ShotPreviewKind
    let previewPath: String
    let shotRootPath: String

    var id: String { "\(shot.id)|\(previewKind.rawValue)|\(previewPath)" }
}

/// Enlarged shot preview modal with context and quick actions.
struct ShotLightboxView: View {
    let item: ShotLightboxItem
    var onOpenShotFolder: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.md) {
            HStack(spacing: StopmoUI.Spacing.sm) {
                Text(item.shot.shotName)
                    .font(.headline)
                    .lineLimit(1)
                StatusChip(
                    label: item.previewKind == .first ? "First Frame Preview" : "Latest Frame Preview",
                    tone: .neutral,
                    density: .compact
                )
                Spacer(minLength: 0)
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            SurfaceContainer(level: .panel, chrome: .outlined, cornerRadius: 10) {
                Group {
                    if let image {
                        GeometryReader { proxy in
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                                .padding(StopmoUI.Spacing.sm)
                        }
                    } else {
                        VStack(spacing: StopmoUI.Spacing.sm) {
                            Image(systemName: "photo")
                                .font(.title)
                                .foregroundStyle(.secondary)
                            Text("Preview not available")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minHeight: 360, maxHeight: 560)
            }

            HStack(spacing: StopmoUI.Spacing.sm) {
                Text(item.previewPath)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Open Shot Folder") {
                    onOpenShotFolder?(item.shotRootPath)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(StopmoUI.Spacing.md)
        .frame(minWidth: 680, minHeight: 520)
        .onAppear {
            loadImage(from: item.previewPath)
        }
    }

    private func loadImage(from path: String) {
        Task.detached(priority: .userInitiated) {
            let loaded = NSImage(contentsOfFile: path)
            await MainActor.run {
                image = loaded
            }
        }
    }
}
