import XCTest
@testable import StopmoXcodeGUI

final class DesignSystemVisualTokenTests: XCTestCase {
    func testSurfaceLevelNominalOpacityMapping() {
        XCTAssertEqual(SurfaceLevel.canvas.nominalFillOpacity, 0)
        XCTAssertEqual(SurfaceLevel.panel.nominalFillOpacity, 0.03, accuracy: 0.0001)
        XCTAssertEqual(SurfaceLevel.card.nominalFillOpacity, 0.04, accuracy: 0.0001)
        XCTAssertEqual(SurfaceLevel.raised.nominalFillOpacity, 0.055, accuracy: 0.0001)

        XCTAssertEqual(SurfaceLevel.canvas.nominalBorderOpacity, 0)
        XCTAssertEqual(SurfaceLevel.panel.nominalBorderOpacity, 0.055, accuracy: 0.0001)
        XCTAssertEqual(SurfaceLevel.card.nominalBorderOpacity, 0.0594, accuracy: 0.0001)
        XCTAssertEqual(SurfaceLevel.raised.nominalBorderOpacity, 0.10, accuracy: 0.0001)
    }

    func testSidebarSubtitleProgressiveVisibilityRules() {
        XCTAssertTrue(
            RootSidebarView.shouldShowSubtitle(
                mode: .progressive,
                isSelected: true,
                isHovered: false
            )
        )
        XCTAssertTrue(
            RootSidebarView.shouldShowSubtitle(
                mode: .progressive,
                isSelected: false,
                isHovered: true
            )
        )
        XCTAssertFalse(
            RootSidebarView.shouldShowSubtitle(
                mode: .progressive,
                isSelected: false,
                isHovered: false
            )
        )
        XCTAssertTrue(
            RootSidebarView.shouldShowSubtitle(
                mode: .always,
                isSelected: false,
                isHovered: false
            )
        )
        XCTAssertFalse(
            RootSidebarView.shouldShowSubtitle(
                mode: .hidden,
                isSelected: true,
                isHovered: true
            )
        )
    }
}
