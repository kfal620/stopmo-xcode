import XCTest
@testable import StopmoXcodeGUI

@MainActor
final class NotificationPresenterStateTests: XCTestCase {
    func testNotificationCenterPresentationTogglesAndDismisses() {
        let state = AppState()

        XCTAssertFalse(state.isNotificationsCenterPresented)
        state.toggleNotificationsCenter()
        XCTAssertTrue(state.isNotificationsCenterPresented)

        state.dismissNotificationsCenter()
        XCTAssertFalse(state.isNotificationsCenterPresented)
    }

    func testBadgeTextAndToneReflectNotificationSeverity() {
        let state = AppState()
        XCTAssertNil(state.notificationsBadgeText)

        state.presentInfo(title: "Info", message: "Background task completed")
        XCTAssertEqual(state.notificationsBadgeText, "1")
        XCTAssertEqual(state.notificationsBadgeTone, .warning)

        state.presentError(title: "Decode", message: "decode failed")
        XCTAssertEqual(state.notificationsBadgeText, "2")
        XCTAssertEqual(state.notificationsBadgeTone, .danger)
    }

    func testClearNotificationsResetsBadge() {
        let state = AppState()

        state.presentWarning(title: "Warn", message: "Needs attention")
        XCTAssertEqual(state.notificationsBadgeText, "1")

        state.clearNotifications()
        XCTAssertTrue(state.notifications.isEmpty)
        XCTAssertNil(state.notificationsBadgeText)
    }

    func testErrorDoesNotCreateToastButWarningDoes() {
        let state = AppState()

        state.presentError(title: "Bridge", message: "No module named stopmo_xcode")
        XCTAssertNil(state.activeToast)

        state.presentWarning(title: "Watch", message: "watch was blocked")
        XCTAssertNotNil(state.activeToast)

        state.dismissToast()
        XCTAssertNil(state.activeToast)
    }
}
