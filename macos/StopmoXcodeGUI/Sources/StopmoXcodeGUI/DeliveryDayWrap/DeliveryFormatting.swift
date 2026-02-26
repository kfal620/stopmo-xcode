import Foundation

func deliveryShortTimeLabel(_ timestampUtc: String?) -> String {
    guard let raw = timestampUtc?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
        return "-"
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    let fallback = ISO8601DateFormatter()
    fallback.formatOptions = [.withInternetDateTime]

    guard let date = formatter.date(from: raw) ?? fallback.date(from: raw) else {
        return raw
    }

    let output = DateFormatter()
    output.dateFormat = "HH:mm:ss"
    return output.string(from: date)
}

func deliveryTimelineFilename(_ value: String?) -> String {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        return "-"
    }
    let filename = (value as NSString).lastPathComponent
    let hasExtension = !URL(fileURLWithPath: filename).pathExtension.isEmpty
    return hasExtension ? filename : "\(filename).mov"
}
