import XCTest
@testable import StopmoXcodeGUI

final class ToolsWorkspaceMapperTests: XCTestCase {
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
}
