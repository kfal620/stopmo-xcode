import SwiftUI

struct ToolsWorkspaceTabBarView: View {
    let tabs: [ToolsTab]
    @Binding var selectedTab: ToolsTab

    var body: some View {
        HStack(spacing: StopmoUI.Spacing.sm) {
            ForEach(tabs) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(selectedTab == tab ? .accentColor : Color.secondary.opacity(0.35))
            }
            Spacer(minLength: 0)
        }
    }
}
