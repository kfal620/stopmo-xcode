import Foundation

/// Formatting helpers for turning backend timestamps and filesystem paths into compact UI labels.
enum PathTimestampHelpers {
    static func trimmedOrNil(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    static func resolveFilesystemPath(
        _ value: String?,
        configPath: String? = nil,
        workspaceRoot: String? = nil
    ) -> String? {
        guard let raw = trimmedOrNil(value) else {
            return nil
        }
        let expanded = NSString(string: raw).expandingTildeInPath
        if NSString(string: expanded).isAbsolutePath {
            return URL(fileURLWithPath: expanded).standardizedFileURL.path
        }

        if let configDirectory = resolvedConfigDirectory(configPath: configPath, workspaceRoot: workspaceRoot) {
            return URL(fileURLWithPath: configDirectory, isDirectory: true)
                .appendingPathComponent(expanded, isDirectory: false)
                .standardizedFileURL
                .path
        }

        if let workspaceRoot = trimmedOrNil(workspaceRoot) {
            return URL(fileURLWithPath: workspaceRoot, isDirectory: true)
                .appendingPathComponent(expanded, isDirectory: false)
                .standardizedFileURL
                .path
        }

        return expanded
    }

    static func pathExists(
        _ value: String?,
        configPath: String? = nil,
        workspaceRoot: String? = nil
    ) -> Bool {
        guard let value = resolveFilesystemPath(value, configPath: configPath, workspaceRoot: workspaceRoot) else {
            return false
        }
        return FileManager.default.fileExists(atPath: value)
    }

    static func appendingPath(base: String, component: String) -> String {
        (base as NSString).appendingPathComponent(component)
    }

    static func shotRootPath(
        baseOutputDir: String,
        shotName: String,
        configPath: String? = nil,
        workspaceRoot: String? = nil
    ) -> String {
        guard let normalizedShotName = trimmedOrNil(shotName) else {
            return shotName
        }
        guard let base = resolveFilesystemPath(
            baseOutputDir,
            configPath: configPath,
            workspaceRoot: workspaceRoot
        ) ?? trimmedOrNil(baseOutputDir) else {
            return normalizedShotName
        }
        return appendingPath(base: base, component: normalizedShotName)
    }

    static func parseIso8601(_ value: String?) -> Date? {
        guard let value = trimmedOrNil(value) else {
            return nil
        }
        if let date = iso8601Formatter(withFractionalSeconds: true).date(from: value) {
            return date
        }
        return iso8601Formatter(withFractionalSeconds: false).date(from: value)
    }

    static func shortTimeLabel(_ timestampUtc: String?) -> String {
        guard let raw = trimmedOrNil(timestampUtc) else {
            return "-"
        }
        guard let date = parseIso8601(raw) else {
            return raw
        }
        return shortTimeFormatter().string(from: date)
    }

    static func nowTimeLabel(_ now: Date = Date()) -> String {
        shortTimeFormatter().string(from: now)
    }

    static func relativeUpdatedLabel(_ timestamp: String?, now: Date = Date()) -> String {
        guard let date = parseIso8601(timestamp) else {
            return "Updated -"
        }

        let delta = max(0, Int(now.timeIntervalSince(date)))
        if delta < 5 {
            return "Updated now"
        }
        if delta < 60 {
            return "Updated \(delta)s ago"
        }
        if delta < 3600 {
            return "Updated \(delta / 60)m ago"
        }
        if delta < 86_400 {
            let hours = delta / 3600
            let minutes = (delta % 3600) / 60
            if minutes == 0 {
                return "Updated \(hours)h ago"
            }
            return "Updated \(hours)h \(minutes)m ago"
        }
        let days = delta / 86_400
        return "Updated \(days)d ago"
    }

    static func filenameLabel(_ value: String?, defaultExtension: String? = nil) -> String {
        guard let value = trimmedOrNil(value) else {
            return "-"
        }
        let filename = (value as NSString).lastPathComponent
        if let defaultExtension, !defaultExtension.isEmpty {
            let hasExtension = !URL(fileURLWithPath: filename).pathExtension.isEmpty
            return hasExtension ? filename : "\(filename).\(defaultExtension)"
        }
        return filename
    }

    private static func iso8601Formatter(withFractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = withFractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }

    private static func shortTimeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }

    private static func resolvedConfigDirectory(configPath: String?, workspaceRoot: String?) -> String? {
        guard let configPath = trimmedOrNil(configPath) else {
            return nil
        }
        let expanded = NSString(string: configPath).expandingTildeInPath
        let configURL: URL
        if NSString(string: expanded).isAbsolutePath {
            configURL = URL(fileURLWithPath: expanded)
        } else if let workspaceRoot = trimmedOrNil(workspaceRoot) {
            configURL = URL(fileURLWithPath: workspaceRoot, isDirectory: true)
                .appendingPathComponent(expanded, isDirectory: false)
                .standardizedFileURL
        } else {
            return nil
        }
        return configURL.deletingLastPathComponent().path
    }
}
