import XCTest
@testable import StopmoXcodeGUI

final class DesignSystemContractsTests: XCTestCase {
    func testStopmoUISpacingAndMotionContractsRemainStable() {
        XCTAssertEqual(StopmoUI.Spacing.xxs, 4)
        XCTAssertEqual(StopmoUI.Spacing.xs, 6)
        XCTAssertEqual(StopmoUI.Spacing.sm, 10)
        XCTAssertEqual(StopmoUI.Spacing.md, 14)
        XCTAssertEqual(StopmoUI.Spacing.lg, 20)

        XCTAssertEqual(StopmoUI.Motion.hover, 0.10, accuracy: 0.0001)
        XCTAssertEqual(StopmoUI.Motion.disclosure, 0.18, accuracy: 0.0001)
    }

    func testSurfaceSpecMatchesLevelChromeDefaults() {
        let panel = AppVisualTokens.surfaceSpec(for: .panel)
        XCTAssertEqual(panel.fillOpacity, 0.03, accuracy: 0.0001)
        XCTAssertEqual(panel.borderOpacity, 0.055, accuracy: 0.0001)
        XCTAssertEqual(panel.borderWidth, 0.75, accuracy: 0.0001)
        XCTAssertFalse(panel.usesRaisedShadow)
        XCTAssertEqual(panel.shadowOpacity, 0.0, accuracy: 0.0001)
        XCTAssertEqual(panel.shadowRadius, 0)
        XCTAssertEqual(panel.shadowY, 0)

        let cardQuiet = AppVisualTokens.surfaceSpec(for: .card, chrome: .quiet)
        XCTAssertEqual(cardQuiet.borderOpacity, 0.044, accuracy: 0.0001)

        let raisedOutlined = AppVisualTokens.surfaceSpec(for: .raised, chrome: .outlined)
        XCTAssertEqual(raisedOutlined.borderOpacity, 0.10, accuracy: 0.0001)
        XCTAssertEqual(raisedOutlined.borderWidth, 0.9, accuracy: 0.0001)
        XCTAssertTrue(raisedOutlined.usesRaisedShadow)
        XCTAssertEqual(raisedOutlined.shadowOpacity, 0.58, accuracy: 0.0001)
        XCTAssertEqual(raisedOutlined.shadowRadius, 5)
        XCTAssertEqual(raisedOutlined.shadowY, 2)
    }

    func testSurfaceSpecEmphasisAndHoverAffectVisualStrength() {
        let base = AppVisualTokens.surfaceSpec(for: .card, emphasized: false, interactionStyle: .control, isHovered: false)
        let hovered = AppVisualTokens.surfaceSpec(for: .card, emphasized: false, interactionStyle: .control, isHovered: true)
        let emphasized = AppVisualTokens.surfaceSpec(for: .card, emphasized: true, interactionStyle: .control, isHovered: false)
        let passiveHovered = AppVisualTokens.surfaceSpec(for: .card, emphasized: false, interactionStyle: .passive, isHovered: true)

        XCTAssertGreaterThan(hovered.fillOpacity, base.fillOpacity)
        XCTAssertGreaterThan(emphasized.fillOpacity, base.fillOpacity)

        XCTAssertEqual(hovered.shadowRadius, 5)
        XCTAssertEqual(hovered.shadowY, 2)
        XCTAssertGreaterThan(hovered.shadowOpacity, base.shadowOpacity)
        XCTAssertEqual(passiveHovered.fillOpacity, base.fillOpacity, accuracy: 0.0001)
        XCTAssertEqual(passiveHovered.shadowOpacity, base.shadowOpacity, accuracy: 0.0001)
    }
}
