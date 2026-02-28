import Foundation

/// Resolver for preview file paths across backend-emitted and derived shot paths.
enum ShotPreviewResolver {
    static func preferredPath(
        for shot: ShotSummaryRow,
        preferred: ShotPreviewKind,
        baseOutputDir: String,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> String? {
        let ordered = candidatePaths(for: shot, preferred: preferred, baseOutputDir: baseOutputDir)
        for path in ordered {
            if let trimmed = trimmed(path), fileExists(trimmed) {
                return trimmed
            }
        }
        return nil
    }

    static func candidatePaths(
        for shot: ShotSummaryRow,
        preferred: ShotPreviewKind,
        baseOutputDir: String
    ) -> [String] {
        let firstCandidates = trimmed(shot.previewFirstPath).map { [$0] }
            ?? canonicalPaths(baseOutputDir: baseOutputDir, shotName: shot.shotName, kind: .first)
        let latestCandidates = trimmed(shot.previewLatestPath).map { [$0] }
            ?? canonicalPaths(baseOutputDir: baseOutputDir, shotName: shot.shotName, kind: .latest)

        switch preferred {
        case .latest:
            return latestCandidates + firstCandidates
        case .first:
            return firstCandidates + latestCandidates
        }
    }

    static func canonicalPaths(baseOutputDir: String, shotName: String, kind: ShotPreviewKind) -> [String] {
        guard let root = trimmed(baseOutputDir), let name = trimmed(shotName) else {
            return []
        }
        let shotRoot = PathTimestampHelpers.shotRootPath(baseOutputDir: root, shotName: name)
        let stem = kind == .first ? "first" : "latest"
        let previewDir = (shotRoot as NSString).appendingPathComponent("preview")
        return [
            (previewDir as NSString).appendingPathComponent("\(stem).jpg"),
            (previewDir as NSString).appendingPathComponent("\(stem).jpeg"),
            (previewDir as NSString).appendingPathComponent("\(stem).png"),
            (previewDir as NSString).appendingPathComponent("\(stem).tiff"),
            (previewDir as NSString).appendingPathComponent("\(stem).tif"),
        ]
    }

    private static func trimmed(_ value: String?) -> String? {
        PathTimestampHelpers.trimmedOrNil(value)
    }
}
