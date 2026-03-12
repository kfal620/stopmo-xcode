import SwiftUI

extension LifecycleHub {
    var accentColor: Color {
        switch self {
        case .configure:
            return Color(red: 0.34, green: 0.48, blue: 0.72)
        case .capture:
            return Color(red: 0.22, green: 0.52, blue: 0.38)
        case .triage:
            return Color(red: 0.66, green: 0.45, blue: 0.16)
        case .deliver:
            return Color(red: 0.16, green: 0.47, blue: 0.62)
        }
    }

    var accentGradient: LinearGradient {
        LinearGradient(
            colors: [
                AppVisualTokens.stageAccent(hub: self).opacity(0.12),
                AppVisualTokens.stageAccent(hub: self).opacity(0.05),
                Color.clear,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
