import SwiftUI
import AppKit

/// View rendering root sidebar view.
struct RootSidebarView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredHub: LifecycleHub?
    let topContentInset: CGFloat
    private let detailMode: SidebarDetailMode = .progressive

    init(topContentInset: CGFloat = 0) {
        self.topContentInset = max(0, topContentInset)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(LifecycleHub.allCases) { hub in
                        let isSelected = state.selectedHub == hub
                        let isHovered = hoveredHub == hub

                        Button {
                            state.selectedHub = hub
                        } label: {
                            sidebarRow(
                                for: hub,
                                isSelected: isSelected,
                                isHovered: isHovered
                            )
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onHover { hovering in
                            withAnimation(reduceMotion ? nil : .easeOut(duration: StopmoUI.Motion.hover)) {
                                hoveredHub = hovering ? hub : (hoveredHub == hub ? nil : hoveredHub)
                            }
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, -15 + topContentInset)   /// Padding above the sidebar rows (vertically between traffic lights and sidebar rows)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background {
            ZStack {
                SidebarBehindWindowMaterial()
                Rectangle()
                    .fill(AppVisualTokens.rootSidebarTintOverlay)
            }
            .ignoresSafeArea(edges: [.top, .bottom, .leading])
        }
    }

    private func sidebarRow(
        for hub: LifecycleHub,
        isSelected: Bool,
        isHovered: Bool
    ) -> some View {
        let showSubtitle = Self.shouldShowSubtitle(
            mode: detailMode,
            isSelected: isSelected,
            isHovered: isHovered
        )

        return VStack(alignment: .leading, spacing: StopmoUI.Spacing.xxs) {
            HStack(alignment: .top, spacing: StopmoUI.Spacing.sm) {
                Image(systemName: hub.iconName)
                    .frame(width: 18, alignment: .leading)
                    .foregroundStyle(isSelected ? hub.accentColor : AppVisualTokens.textSecondary)

                Text(hub.rawValue)
                    .foregroundStyle(AppVisualTokens.textPrimary)

                Spacer(minLength: 0)

                if hub == .capture {
                    LiveStateChip(isRunning: state.watchServiceState?.running == true)
                        .help(state.watchServiceState?.running == true ? "Watcher is running" : "Watcher is stopped")
                        .accessibilityLabel(Text(state.watchServiceState?.running == true ? "Watcher live" : "Watcher idle"))
                } else if let badge = sidebarBadge(for: hub) {
                    StatusChip(label: badge.label, tone: badge.tone)
                }
            }

            if showSubtitle {
                Text(hub.subtitle)
                    .metadataTextStyle(.secondary)
                    .lineLimit(2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: StopmoUI.Radius.card, style: .continuous)
                .fill(
                    isSelected
                        ? hub.accentColor.opacity(0.16)
                        : (isHovered ? AppVisualTokens.fill(for: .panel, emphasized: true) : Color.clear)
                )
        )
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(hub.accentColor.opacity(0.88))
                    .frame(width: 2)
                    .padding(.vertical, 3)
                    .padding(.leading, 1)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: StopmoUI.Motion.hover), value: showSubtitle)
    }

    nonisolated static func shouldShowSubtitle(mode: SidebarDetailMode, isSelected: Bool, isHovered: Bool) -> Bool {
        switch mode {
        case .always:
            return true
        case .hidden:
            return false
        case .progressive:
            return isSelected || isHovered
        }
    }

    private func sidebarBadge(for hub: LifecycleHub) -> SidebarBadge? {
        switch hub {
        case .triage:
            let failed = state.queueSnapshot?.counts["failed"] ?? 0
            if failed > 0 {
                return SidebarBadge(label: "\(failed)!", tone: .danger)
            }
            let warnings = state.logsDiagnostics?.warnings.count ?? 0
            if warnings > 0 {
                return SidebarBadge(label: "\(warnings)", tone: .warning)
            }
            return nil
        case .deliver:
            let runs = state.historySummary?.count ?? 0
            if runs > 0 {
                return SidebarBadge(label: "\(runs)", tone: .neutral)
            }
            return nil
        default:
            return nil
        }
    }
}

/// Data/view model for sidebar badge.
private struct SidebarBadge {
    let label: String
    let tone: StatusTone
}

private struct SidebarBehindWindowMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
    }
}
