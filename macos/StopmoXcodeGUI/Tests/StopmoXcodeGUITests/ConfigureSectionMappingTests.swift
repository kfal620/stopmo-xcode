import XCTest
@testable import StopmoXcodeGUI

final class ConfigureSectionMappingTests: XCTestCase {
    func testProjectSettingsPanelMapsToLastActiveProjectSection() {
        XCTAssertEqual(
            ConfigureSection.resolve(panel: .projectSettings, lastProjectSection: .recipe),
            .recipe
        )
        XCTAssertEqual(
            ConfigureSection.resolve(panel: .projectSettings, lastProjectSection: .workspace),
            .workspace
        )
    }

    func testWorkspaceHealthAndCalibrationPanelsMapToUnifiedSections() {
        XCTAssertEqual(
            ConfigureSection.resolve(panel: .workspaceHealth, lastProjectSection: .workspace),
            .healthPreflight
        )
        XCTAssertEqual(
            ConfigureSection.resolve(panel: .calibration, lastProjectSection: .workspace),
            .calibrationLab
        )
    }
}
