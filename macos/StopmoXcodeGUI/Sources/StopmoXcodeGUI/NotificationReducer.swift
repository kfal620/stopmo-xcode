import Foundation

/// Pure notification-list and badge-state helpers plus error hint mapping.
enum NotificationReducer {
    static func badgeText(for notifications: [NotificationRecord]) -> String? {
        guard !notifications.isEmpty else {
            return nil
        }
        if notifications.count > 99 {
            return "99+"
        }
        return "\(notifications.count)"
    }

    static func badgeTone(for notifications: [NotificationRecord]) -> StatusTone {
        notifications.contains { $0.kind == .error } ? .danger : .warning
    }

    static func append(
        _ notification: NotificationRecord,
        to notifications: inout [NotificationRecord],
        maxCount: Int
    ) {
        notifications.insert(notification, at: 0)
        if notifications.count > maxCount {
            notifications = Array(notifications.prefix(maxCount))
        }
    }

    static func errorHints(
        for message: String,
        bundledRuntime: Bool
    ) -> (likelyCause: String?, suggestedAction: String?) {
        let lower = message.lowercased()
        if lower.contains("no module named") || lower.contains("modulenotfounderror") {
            if bundledRuntime {
                return (
                    likelyCause: "Bundled runtime assets are missing or corrupted.",
                    suggestedAction: "Reinstall the app from the latest signed DMG and rerun Runtime Health."
                )
            }
            return (
                likelyCause: "Python dependencies are missing or PYTHONPATH/venv is not configured for this workspace.",
                suggestedAction: "Use the development scheme with STOPMO_XCODE_ROOT pointed at this repository, then install dependencies in `.venv`."
            )
        }
        if lower.contains("invalid repo root") || lower.contains("bridge script not found") {
            return (
                likelyCause: "Development backend root does not point to the stopmo-xcode project root.",
                suggestedAction: "For development mode, set STOPMO_XCODE_ROOT to a repository containing `pyproject.toml` and `src/stopmo_xcode`."
            )
        }
        if lower.contains("permission") || lower.contains("not allowed") || lower.contains("operation not permitted") {
            return (
                likelyCause: "macOS file/system permission access was denied.",
                suggestedAction: "Re-select workspace access in Configure > Workspace & Health and allow permission prompts."
            )
        }
        if lower.contains("ffmpeg") {
            if bundledRuntime {
                return (
                    likelyCause: "Bundled FFmpeg runtime is unavailable.",
                    suggestedAction: "Reinstall the app and run Runtime Health to confirm bundled tooling is present."
                )
            }
            return (
                likelyCause: "FFmpeg is missing or unavailable in PATH.",
                suggestedAction: "Install FFmpeg and run Check Runtime Health to verify dependency availability."
            )
        }
        if lower.contains("decode") || lower.contains("raw") {
            return (
                likelyCause: "Input frame decode failed for the selected file.",
                suggestedAction: "Verify file exists/is supported and inspect Logs & Diagnostics for decode warnings."
            )
        }
        return (
            likelyCause: "The backend operation failed while processing the request.",
            suggestedAction: "Check Logs & Diagnostics and retry the operation after correcting config/runtime issues."
        )
    }
}
