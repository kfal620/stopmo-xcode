import SwiftUI

private struct HubContentWidthEnvironmentKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var hubContentWidth: CGFloat {
        get { self[HubContentWidthEnvironmentKey.self] }
        set { self[HubContentWidthEnvironmentKey.self] = newValue }
    }
}
