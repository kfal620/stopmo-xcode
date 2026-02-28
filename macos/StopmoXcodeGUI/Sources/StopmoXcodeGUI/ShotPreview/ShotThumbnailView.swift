import AppKit
import SwiftUI

/// Compact preview thumbnail with placeholder and optional lightbox action.
struct ShotThumbnailView: View {
    let shot: ShotSummaryRow
    let preferredKind: ShotPreviewKind
    let baseOutputDir: String
    let width: CGFloat
    let height: CGFloat
    var cornerRadius: CGFloat = 8
    var onOpenLightbox: ((String) -> Void)? = nil

    @State private var image: NSImage?
    @State private var loadedPath: String?

    private var resolvedPath: String? {
        ShotPreviewResolver.preferredPath(
            for: shot,
            preferred: preferredKind,
            baseOutputDir: baseOutputDir
        )
    }

    private var reloadKey: String {
        [
            resolvedPath ?? "-",
            shot.lastUpdatedAt ?? "-",
            shot.previewLatestUpdatedAt ?? "-",
            "\(shot.previewFirstFrameNumber ?? -1)",
        ].joined(separator: "|")
    }

    private var canOpenLightbox: Bool {
        onOpenLightbox != nil && resolvedPath != nil && image != nil
    }

    private var helpLabel: String {
        let variant = preferredKind == .first ? "first frame" : "latest frame"
        if let path = resolvedPath {
            return "\(shot.shotName) \(variant) preview\n\(path)"
        }
        return "\(shot.shotName) \(variant) preview unavailable"
    }

    var body: some View {
        Button {
            guard canOpenLightbox, let path = resolvedPath else { return }
            onOpenLightbox?(path)
        } label: {
            thumbnailBody
        }
        .buttonStyle(.plain)
        .help(helpLabel)
        .onAppear(perform: refreshImage)
        .onChange(of: reloadKey) { _, _ in
            refreshImage()
        }
    }

    private var thumbnailBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppVisualTokens.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(AppVisualTokens.borderSubtle, lineWidth: 1)
                )

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
                    .overlay(alignment: .topLeading) {
                        if canOpenLightbox {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(4)
                                .foregroundStyle(.white.opacity(0.95))
                                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                                .padding(4)
                        }
                    }
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(.system(size: min(18, width * 0.2), weight: .medium))
                        .foregroundStyle(AppVisualTokens.textTertiary)
                    Text(preferredKind == .first ? "First" : "Latest")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AppVisualTokens.textTertiary)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func refreshImage() {
        let path = resolvedPath
        guard path != loadedPath || image == nil else {
            return
        }

        loadedPath = path
        image = nil

        guard let path else { return }
        Task.detached(priority: .utility) {
            let loaded = NSImage(contentsOfFile: path)
            await MainActor.run {
                guard loadedPath == path else { return }
                image = loaded
            }
        }
    }
}
