import XCTest
@testable import StopmoXcodeGUI

final class DesignSystemContractsTests: XCTestCase {
    func testStopmoUISpacingAndMotionContractsRemainStable() {
        XCTAssertEqual(StopmoUI.Spacing.xxs, 4)
        XCTAssertEqual(StopmoUI.Spacing.xs, 6)
        XCTAssertEqual(StopmoUI.Spacing.sm, 10)
        XCTAssertEqual(StopmoUI.Spacing.md, 14)
        XCTAssertEqual(StopmoUI.Spacing.lg, 20)

        XCTAssertEqual(StopmoUI.Motion.hover, 0.14, accuracy: 0.0001)
        XCTAssertEqual(StopmoUI.Motion.disclosure, 0.18, accuracy: 0.0001)
    }

    func testSurfaceSpecMatchesLevelChromeDefaults() {
        let panel = AppVisualTokens.surfaceSpec(for: .panel)
        XCTAssertEqual(panel.fillOpacity, 0.045, accuracy: 0.0001)
        XCTAssertEqual(panel.borderOpacity, 0.08, accuracy: 0.0001)
        XCTAssertEqual(panel.borderWidth, 0.75, accuracy: 0.0001)
        XCTAssertFalse(panel.usesRaisedShadow)
        XCTAssertEqual(panel.shadowOpacity, 0.0, accuracy: 0.0001)
        XCTAssertEqual(panel.shadowRadius, 0)
        XCTAssertEqual(panel.shadowY, 0)

        let cardQuiet = AppVisualTokens.surfaceSpec(for: .card, chrome: .quiet)
        XCTAssertEqual(cardQuiet.borderOpacity, 0.064, accuracy: 0.0001)

        let raisedOutlined = AppVisualTokens.surfaceSpec(for: .raised, chrome: .outlined)
        XCTAssertEqual(raisedOutlined.borderOpacity, 0.16, accuracy: 0.0001)
        XCTAssertEqual(raisedOutlined.borderWidth, 1.0, accuracy: 0.0001)
        XCTAssertTrue(raisedOutlined.usesRaisedShadow)
        XCTAssertEqual(raisedOutlined.shadowOpacity, 1.0, accuracy: 0.0001)
        XCTAssertEqual(raisedOutlined.shadowRadius, 8)
        XCTAssertEqual(raisedOutlined.shadowY, 2)
    }

    func testSurfaceSpecEmphasisAndHoverAffectVisualStrength() {
        let base = AppVisualTokens.surfaceSpec(for: .card, emphasized: false, isHovered: false)
        let hovered = AppVisualTokens.surfaceSpec(for: .card, emphasized: false, isHovered: true)
        let emphasized = AppVisualTokens.surfaceSpec(for: .card, emphasized: true, isHovered: false)

        XCTAssertGreaterThan(hovered.fillOpacity, base.fillOpacity)
        XCTAssertGreaterThan(emphasized.fillOpacity, base.fillOpacity)

        XCTAssertEqual(hovered.shadowRadius, 8)
        XCTAssertEqual(hovered.shadowY, 2)
        XCTAssertGreaterThan(hovered.shadowOpacity, base.shadowOpacity)
    }
}
