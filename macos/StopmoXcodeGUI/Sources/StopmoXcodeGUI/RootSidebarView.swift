import SwiftUI
import AppKit

/// Primary app rail for lifecycle navigation and high-level system status.
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
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.md) {
            railHeader

            VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                ForEach(LifecycleHub.allCases) { hub in
                    let isSelected = state.selectedHub == hub
                    let isHovered = hoveredHub == hub

                    Button {
                        state.selectedHub = hub
                    } label: {
                        sidebarRow(for: hub, isSelected: isSelected, isHovered: isHovered)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onHover { hovering in
                        hoveredHub = hovering ? hub : (hoveredHub == hub ? nil : hoveredHub)
                    }
                }
            }

            Spacer(minLength: 0)

            railFooter
        }
        .padding(.horizontal, 12)
        .padding(.top, topContentInset + 14)
        .padding(.bottom, 14)
        .background {
            ZStack {
                SidebarBehindWindowMaterial()
                Rectangle()
                    .fill(AppVisualTokens.rootSidebarTintOverlay)
            }
            .ignoresSafeArea(edges: [.top, .bottom, .leading])
        }
    }

    private var railHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FrameRelay")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.98))
            Text("Deterministic stop-motion ingest and delivery")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var railFooter: some View {
        SurfaceContainer(level: .panel, chrome: .quiet, cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    LiveStateChip(
                        isRunning: state.watchServiceState?.running == true,
                        runningLabel: "Live",
                        idleLabel: "Idle"
                    )
                    StatusChip(label: monitoringLabel, tone: monitoringTone, density: .compact)
                }
                Text("Use Capture for live watch control, Review for shot recovery, and Deliver for day wrap.")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
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
            HStack(alignment: .center, spacing: StopmoUI.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(hub.accentColor.opacity(isSelected ? 0.28 : 0.14))
                    Image(systemName: hub.iconName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.82))
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(hub.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.98))

                    if showSubtitle {
                        Text(hub.subtitle)
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.62))
                            .lineLimit(2)
                            .transition(.opacity)
                    }
                }

                Spacer(minLength: 0)

                if hub == .capture {
                    LiveStateChip(isRunning: state.watchServiceState?.running == true)
                        .help(state.watchServiceState?.running == true ? "Watcher is running" : "Watcher is stopped")
                } else if let badge = sidebarBadge(for: hub) {
                    StatusChip(label: badge.label, tone: badge.tone, density: .compact)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    isSelected
                        ? Color.white.opacity(0.16)
                        : (isHovered ? Color.white.opacity(0.08) : Color.clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isSelected ? Color.white.opacity(0.18) : Color.clear,
                    lineWidth: 0.9
                )
        )
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(hub.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 8)
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
                return SidebarBadge(label: "\(failed)", tone: .danger)
            }
            let warnings = state.logsDiagnostics?.warnings.count ?? 0
            if warnings > 0 {
                return SidebarBadge(label: "\(warnings)", tone: .warning)
            }
            return nil
        case .deliver:
            if state.deliveryRunState.status == .running {
                return SidebarBadge(label: "Run", tone: .warning)
            }
            return nil
        default:
            return nil
        }
    }

    private var monitoringLabel: String {
        state.monitoringStatusLabel
    }

    private var monitoringTone: StatusTone {
        if state.monitoringConsecutiveFailures >= 3 {
            return .danger
        }
        if state.monitoringConsecutiveFailures > 0 {
            return .warning
        }
        return state.monitoringEnabled ? .success : .neutral
    }
}

/// Sidebar badge model for surfacing queue, warning, or activity counts beside a hub.
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
