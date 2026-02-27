import SwiftUI

extension LifecycleHub {
    var accentColor: Color {
        switch self {
        case .configure:
            return Color.blue
        case .capture:
            return Color.green
        case .triage:
            return Color.orange
        case .deliver:
            return Color.teal
        }
    }

    var accentGradient: LinearGradient {
        LinearGradient(
            colors: [
                AppVisualTokens.stageAccent(hub: self).opacity(0.32),
                AppVisualTokens.stageAccent(hub: self).opacity(0.13),
                Color.black.opacity(0.12),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
