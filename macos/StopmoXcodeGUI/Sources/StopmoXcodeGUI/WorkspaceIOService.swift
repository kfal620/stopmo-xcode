import AppKit
import Foundation
import UniformTypeIdentifiers

enum PathOpenResult {
    case openedTarget
    case openedParent
    case missing
}

struct WorkspaceAccessResolution {
    let url: URL
    let bookmarkWasStale: Bool
    let refreshedBookmarkData: Data?
}

@MainActor
struct WorkspaceIOService {
    func chooseWorkspaceDirectory(initialPath: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Use Workspace"
        panel.directoryURL = URL(fileURLWithPath: initialPath, isDirectory: true)
        guard panel.runModal() == .OK else {
            return nil
        }
        return panel.url
    }

    func chooseRepoRootDirectory(initialPath: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Select Workspace Root"
        panel.directoryURL = URL(fileURLWithPath: initialPath, isDirectory: true)
        guard panel.runModal() == .OK else {
            return nil
        }
        return panel.url
    }

    func chooseConfigFile(initialPath: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "yaml") ?? .text,
            UTType(filenameExtension: "yml") ?? .text,
        ]
        panel.prompt = "Select Config"
        panel.directoryURL = URL(fileURLWithPath: initialPath, isDirectory: true)
        guard panel.runModal() == .OK else {
            return nil
        }
        return panel.url
    }

    func createSecurityScopedBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func resolveWorkspaceBookmark(_ data: Data) throws -> WorkspaceAccessResolution {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        let refreshed = stale ? try createSecurityScopedBookmark(for: url) : nil
        return WorkspaceAccessResolution(url: url, bookmarkWasStale: stale, refreshedBookmarkData: refreshed)
    }

    func startAccessingSecurityScope(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    func stopAccessingSecurityScope(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    func openPathInFinder(_ path: String) -> PathOpenResult {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path)
        if fm.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return .openedTarget
        }
        let parent = url.deletingLastPathComponent()
        if fm.fileExists(atPath: parent.path) {
            NSWorkspace.shared.open(parent)
            return .openedParent
        }
        return .missing
    }

    func openDirectory(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
