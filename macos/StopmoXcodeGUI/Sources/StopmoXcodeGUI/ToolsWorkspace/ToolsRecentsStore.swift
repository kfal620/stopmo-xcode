import Foundation

/// Enumeration for tools recents store.
enum ToolsRecentsStore {
    static let maxEntries = 8

    static func decode(_ raw: String) -> [String] {
        raw
            .split(separator: "\n")
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func append(_ value: String, to currentRaw: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return currentRaw }

        var values = decode(currentRaw)
        values.removeAll { $0 == trimmed }
        values.insert(trimmed, at: 0)
        if values.count > maxEntries {
            values = Array(values.prefix(maxEntries))
        }
        return values.joined(separator: "\n")
    }
}
