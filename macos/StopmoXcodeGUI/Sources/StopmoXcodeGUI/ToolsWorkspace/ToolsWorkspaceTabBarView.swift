import SwiftUI

/// View rendering tools workspace tab bar view.
struct ToolsWorkspaceTabBarView: View {
    let tabs: [ToolsTab]
    @Binding var selectedTab: ToolsTab

    var body: some View {
        SurfaceContainer(level: .panel, chrome: .quiet) {
            HStack(spacing: StopmoUI.Spacing.xs) {
                ForEach(tabs) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.rawValue, systemImage: tab.iconName)
                            .font(.callout.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, StopmoUI.Spacing.sm)
                            .padding(.vertical, StopmoUI.Spacing.xs)
                            .frame(minWidth: 132, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedTab == tab ? AppVisualTokens.textPrimary : AppVisualTokens.textSecondary)
                    .background(
                        RoundedRectangle(cornerRadius: StopmoUI.Radius.chip, style: .continuous)
                            .fill(selectedTab == tab ? Color.accentColor.opacity(0.20) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: StopmoUI.Radius.chip, style: .continuous)
                            .stroke(selectedTab == tab ? Color.accentColor.opacity(0.38) : Color.white.opacity(0.08), lineWidth: 0.75)
                    )
                    .contentShape(Rectangle())
                }
                Spacer(minLength: 0)
            }
            .padding(StopmoUI.Spacing.xs)
            .animation(.easeOut(duration: StopmoUI.Motion.hover), value: selectedTab)
        }
    }
}
