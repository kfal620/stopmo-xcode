import XCTest
@testable import StopmoXcodeGUI

final class DeliveryFormattingTests: XCTestCase {
    func testDeliveryShortTimeLabelWithValidISODate() {
        let value = deliveryShortTimeLabel("2026-02-26T10:00:01.123Z")
        XCTAssertEqual(value.count, 8)
        XCTAssertTrue(value.contains(":"))
    }

    func testDeliveryShortTimeLabelWithInvalidValueFallsBackToRaw() {
        let raw = "not-a-date"
        XCTAssertEqual(deliveryShortTimeLabel(raw), raw)
    }

    func testDeliveryShortTimeLabelWithNilOrEmptyReturnsDash() {
        XCTAssertEqual(deliveryShortTimeLabel(nil), "-")
        XCTAssertEqual(deliveryShortTimeLabel("   "), "-")
    }

    func testDeliveryTimelineFilenameFormatting() {
        XCTAssertEqual(deliveryTimelineFilename("/tmp/path/SHOT_001.mov"), "SHOT_001.mov")
        XCTAssertEqual(deliveryTimelineFilename("SHOT_002"), "SHOT_002.mov")
        XCTAssertEqual(deliveryTimelineFilename(nil), "-")
    }
}
