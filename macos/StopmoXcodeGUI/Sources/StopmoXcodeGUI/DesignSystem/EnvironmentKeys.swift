import SwiftUI

/// Environment key carrying measured detail-pane width for adaptive layouts.
private struct HubContentWidthEnvironmentKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var hubContentWidth: CGFloat {
        get { self[HubContentWidthEnvironmentKey.self] }
        set { self[HubContentWidthEnvironmentKey.self] = newValue }
    }
}
