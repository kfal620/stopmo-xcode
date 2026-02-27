import XCTest
@testable import StopmoXcodeGUI

final class ToolsWorkspaceMapperTests: XCTestCase {
    func testAllModeMapsToAllTabs() {
        let context = ToolsWorkspaceMapper.map(mode: .all, deliveryPresentation: .full)

        XCTAssertEqual(context.tabs, [.transcode, .matrix, .dpxProres, .diagnostics])
        XCTAssertEqual(context.defaultTab, .transcode)
        XCTAssertEqual(context.headerTitle, "Tools")
        XCTAssertTrue(context.showEmbeddedHeaderChips)
    }

    func testUtilitiesModeMapsToUtilityTabs() {
        let context = ToolsWorkspaceMapper.map(mode: .utilitiesOnly, deliveryPresentation: .full)

        XCTAssertEqual(context.tabs, [.transcode, .matrix, .diagnostics])
        XCTAssertEqual(context.defaultTab, .transcode)
        XCTAssertEqual(context.headerTitle, "Calibration")
        XCTAssertTrue(context.showEmbeddedHeaderChips)
    }

    func testDeliveryDiagnosticsModeMapsToDiagnosticsOnly() {
        let context = ToolsWorkspaceMapper.map(mode: .deliveryOnly, deliveryPresentation: .diagnosticsOnly)

        XCTAssertEqual(context.tabs, [.diagnostics])
        XCTAssertEqual(context.defaultTab, .diagnostics)
        XCTAssertEqual(context.headerTitle, "Day Wrap")
        XCTAssertFalse(context.showEmbeddedHeaderChips)
    }

    func testDeliveryFullModeMapsToDpxAndDiagnosticsTabs() {
        let context = ToolsWorkspaceMapper.map(mode: .deliveryOnly, deliveryPresentation: .full)

        XCTAssertEqual(context.tabs, [.dpxProres, .diagnostics])
        XCTAssertEqual(context.defaultTab, .dpxProres)
        XCTAssertEqual(context.headerTitle, "Day Wrap")
        XCTAssertTrue(context.showEmbeddedHeaderChips)
    }
}
