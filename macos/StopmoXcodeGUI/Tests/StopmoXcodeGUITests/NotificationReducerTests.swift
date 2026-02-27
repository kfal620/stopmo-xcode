import XCTest
@testable import StopmoXcodeGUI

final class NotificationReducerTests: XCTestCase {
    func testBadgeTextRules() {
        XCTAssertNil(NotificationReducer.badgeText(for: []))

        let one = [
            NotificationRecord(
                kind: .info,
                title: "Info",
                message: "hello",
                likelyCause: nil,
                suggestedAction: nil,
                createdAt: Date()
            ),
        ]
        XCTAssertEqual(NotificationReducer.badgeText(for: one), "1")

        let many = (0..<100).map { idx in
            NotificationRecord(
                kind: .warning,
                title: "W\(idx)",
                message: "message",
                likelyCause: nil,
                suggestedAction: nil,
                createdAt: Date()
            )
        }
        XCTAssertEqual(NotificationReducer.badgeText(for: many), "99+")
    }

    func testBadgeToneRules() {
        let warningOnly = [
            NotificationRecord(
                kind: .warning,
                title: "Warn",
                message: "warn",
                likelyCause: nil,
                suggestedAction: nil,
                createdAt: Date()
            ),
        ]
        XCTAssertEqual(NotificationReducer.badgeTone(for: warningOnly), .warning)

        let withError = warningOnly + [
            NotificationRecord(
                kind: .error,
                title: "Err",
                message: "err",
                likelyCause: nil,
                suggestedAction: nil,
                createdAt: Date()
            ),
        ]
        XCTAssertEqual(NotificationReducer.badgeTone(for: withError), .danger)
    }

    func testAppendCapsAtConfiguredCount() {
        var notifications: [NotificationRecord] = []
        for idx in 0..<4 {
            let notification = NotificationRecord(
                kind: .info,
                title: "N\(idx)",
                message: "M\(idx)",
                likelyCause: nil,
                suggestedAction: nil,
                createdAt: Date()
            )
            NotificationReducer.append(notification, to: &notifications, maxCount: 3)
        }

        XCTAssertEqual(notifications.count, 3)
        XCTAssertEqual(notifications.first?.title, "N3")
        XCTAssertEqual(notifications.last?.title, "N1")
    }

    func testErrorHintsRespectBundledRuntime() {
        let bundled = NotificationReducer.errorHints(
            for: "No module named stopmo_xcode",
            bundledRuntime: true
        )
        XCTAssertTrue((bundled.likelyCause ?? "").contains("Bundled runtime"))

        let dev = NotificationReducer.errorHints(
            for: "No module named stopmo_xcode",
            bundledRuntime: false
        )
        XCTAssertTrue((dev.likelyCause ?? "").contains("Python dependencies"))
    }
}
