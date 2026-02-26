import Foundation

func deliveryShortTimeLabel(_ timestampUtc: String?) -> String {
    PathTimestampHelpers.shortTimeLabel(timestampUtc)
}

func deliveryTimelineFilename(_ value: String?) -> String {
    PathTimestampHelpers.filenameLabel(value, defaultExtension: "mov")
}
