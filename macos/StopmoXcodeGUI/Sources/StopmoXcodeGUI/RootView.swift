import SwiftUI

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isNotificationsCenterPresented: Bool = false

    var body: some View {
        NavigationSplitView {
            List(selection: $state.selectedSection) {
                ForEach(AppSection.allCases) { section in
                    NavigationLink(value: section) {
                        sidebarRow(for: section)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("stopmo-xcode")
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        commandBar
                        Divider()
                    }
                }
                .navigationSplitViewColumnWidth(min: 760, ideal: 980)
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            state.setMonitoringEnabled(for: state.selectedSection)
            state.reduceMotionEnabled = reduceMotion
        }
        .onChange(of: state.selectedSection) { _, next in
            state.setMonitoringEnabled(for: next)
        }
        .onChange(of: reduceMotion) { _, next in
            state.reduceMotionEnabled = next
        }
        .alert(item: $state.presentedError) { presented in
            Alert(
                title: Text(presented.title),
                message: Text(presented.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let toast = state.activeToast {
                HStack {
                    Spacer(minLength: 0)
                    NotificationToastView(notification: toast) {
                        state.dismissToast()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity)
                )
            }
        }
        .overlay(alignment: .bottomLeading) {
            statusBar
                .padding(.leading, 12)
                .padding(.bottom, 12)
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.2),
            value: state.activeToast?.id
        )
    }

    @ViewBuilder
    private var detailView: some View {
        switch state.selectedSection {
        case .setup:
            SetupView()
        case .project:
            ProjectView()
        case .liveMonitor:
            LiveMonitorView()
        case .shots:
            ShotsView()
        case .queue:
            QueueView()
        case .tools:
            ToolsView()
        case .logs:
            LogsDiagnosticsView()
        case .history:
            HistoryView()
        }
    }

    private var commandBar: some View {
        HStack(spacing: StopmoUI.Spacing.sm) {
            projectContextChip

            if state.watchServiceState?.running == true {
                StatusChip(label: "Watch Running", tone: .success)
            } else {
                StatusChip(label: "Watch Stopped", tone: .warning)
            }

            Spacer(minLength: 0)

            HStack(spacing: 3) {
                ToolbarIconButton(
                    systemImage: "play.fill",
                    tooltip: "Start watch service",
                    accessibilityLabel: "Start Watch",
                    isDisabled: state.isBusy || (state.watchServiceState?.running ?? false)
                ) {
                    Task { await state.startWatchService() }
                }

                ToolbarIconButton(
                    systemImage: "stop.fill",
                    tooltip: "Stop watch service",
                    accessibilityLabel: "Stop Watch",
                    isDisabled: state.isBusy || !(state.watchServiceState?.running ?? false)
                ) {
                    Task { await state.stopWatchService() }
                }

                ToolbarIconButton(
                    systemImage: "arrow.clockwise",
                    tooltip: "Refresh current section",
                    accessibilityLabel: "Refresh",
                    isDisabled: state.isBusy
                ) {
                    Task { await refreshSelectedSection() }
                }

                ToolbarIconButton(
                    systemImage: "bell",
                    tooltip: "Notifications",
                    accessibilityLabel: "Notifications",
                    badgeText: state.notifications.isEmpty ? nil : notificationsBadgeText,
                    badgeTone: state.notifications.contains { $0.kind == .error } ? .danger : .warning
                ) {
                    isNotificationsCenterPresented.toggle()
                }
                .popover(isPresented: $isNotificationsCenterPresented, arrowEdge: .top) {
                    NotificationsCenterPanel()
                        .environmentObject(state)
                }
            }
            .padding(4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.09), lineWidth: 0.75)
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .zIndex(20)
    }

    private var notificationsBadgeText: String {
        let count = state.notifications.count
        if count > 99 {
            return "99+"
        }
        return "\(count)"
    }

    private var projectContextChip: some View {
        HStack(spacing: StopmoUI.Spacing.xs) {
            ToolbarContextChip(
                icon: "folder",
                value: repoRootName,
                tooltip: "Repo Root"
            )
            ToolbarContextChip(
                icon: "doc.text",
                value: configName,
                tooltip: "Config Path"
            )
        }
        .frame(maxWidth: 430, alignment: .leading)
    }

    private func sidebarRow(for section: AppSection) -> some View {
        HStack(alignment: .top, spacing: StopmoUI.Spacing.sm) {
            Image(systemName: section.iconName)
                .frame(width: 18, alignment: .leading)
                .foregroundStyle(.secondary)

            Text(section.rawValue)

            Spacer(minLength: 0)

            if section == .liveMonitor {
                LiveMonitorStatusChip(isRunning: state.watchServiceState?.running == true)
            } else if let badge = sidebarBadge(for: section) {
                StatusChip(label: badge.label, tone: badge.tone)
            }
        }
        .padding(.vertical, 2)
    }

    private func sidebarBadge(for section: AppSection) -> SidebarBadge? {
        switch section {
        case .queue:
            let failed = state.queueSnapshot?.counts["failed"] ?? 0
            if failed > 0 {
                return SidebarBadge(label: "\(failed)!", tone: .danger)
            }
            return nil
        case .logs:
            let warnings = state.logsDiagnostics?.warnings.count ?? 0
            if warnings > 0 {
                return SidebarBadge(label: "\(warnings)", tone: .warning)
            }
            return nil
        case .history:
            let runs = state.historySummary?.count ?? 0
            if runs > 0 {
                return SidebarBadge(label: "\(runs)", tone: .neutral)
            }
            return nil
        default:
            return nil
        }
    }

    private func refreshSelectedSection() async {
        switch state.selectedSection {
        case .setup:
            await state.refreshHealth()
        case .project:
            await state.loadConfig()
        case .liveMonitor, .queue, .shots:
            await state.refreshLiveData()
        case .tools:
            await state.refreshLiveData()
        case .logs:
            await state.refreshLogsDiagnostics()
        case .history:
            await state.refreshHistory()
        }
    }

    private var repoRootName: String {
        URL(fileURLWithPath: state.repoRoot).lastPathComponent
    }

    private var configName: String {
        URL(fileURLWithPath: state.configPath).lastPathComponent
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if state.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
            Text(state.statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let error = state.errorMessage, !error.isEmpty {
                Text("•")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    state.presentError(title: "Last Error", message: error)
                } label: {
                    Label("Error", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .fixedSize(horizontal: true, vertical: true)
    }
}

private struct SidebarBadge {
    let label: String
    let tone: StatusTone
}

private struct LiveMonitorStatusChip: View {
    let isRunning: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .scaleEffect(isRunning && isPulsing ? 1.15 : 1.0)
                .opacity(isRunning && isPulsing ? 0.75 : 1.0)
            Text(isRunning ? "Live" : "Idle")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(isRunning ? Color.green : .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(isRunning ? Color.green.opacity(0.18) : Color.secondary.opacity(0.14))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke((isRunning ? Color.green : Color.secondary).opacity(0.25), lineWidth: 0.75)
        )
        .onAppear {
            setPulseAnimation()
        }
        .onChange(of: isRunning) { _, _ in
            setPulseAnimation()
        }
        .help(isRunning ? "Watcher is running" : "Watcher is stopped")
        .accessibilityLabel(Text(isRunning ? "Watcher live" : "Watcher idle"))
    }

    private var dotColor: Color {
        isRunning ? .green : .secondary
    }

    private func setPulseAnimation() {
        guard isRunning, !reduceMotion else {
            isPulsing = false
            return
        }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }
}

private struct ToolbarContextChip: View {
    let icon: String
    let value: String
    let tooltip: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: StopmoUI.Spacing.xs) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: StopmoUI.Radius.chip, style: .continuous)
                .fill(isHovered ? Color.secondary.opacity(0.22) : Color.secondary.opacity(0.16))
        )
        .overlay(alignment: .top) {
            if isHovered {
                Text(tooltip)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.regularMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.75)
                    )
                    .fixedSize(horizontal: true, vertical: true)
                    .shadow(color: Color.black.opacity(0.16), radius: 6, x: 0, y: 2)
                    .offset(y: -28)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
                    .allowsHitTesting(false)
            }
        }
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .zIndex(isHovered ? 80 : 0)
        .help(tooltip)
        .accessibilityLabel(Text(value))
        .accessibilityHint(Text(tooltip))
    }
}

private struct ToolbarIconButton: View {
    let systemImage: String
    let tooltip: String
    let accessibilityLabel: String
    var isDisabled: Bool = false
    var badgeText: String? = nil
    var badgeTone: StatusTone = .warning
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(
                        width: 31,
                        height: 31
                    )
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(hoverBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(hoverBorder, lineWidth: 0.75)
                    )
                if let badgeText {
                    Text(badgeText)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(badgeTone == .danger ? Color.red : Color.orange)
                        )
                        .offset(x: 10, y: -9)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { hovering in
            isHovered = hovering
        }
        .overlay(alignment: .top) {
            if isHovered && !isDisabled {
                tooltipBubble
                    .offset(y: -30)
            }
        }
        .zIndex(isHovered ? 120 : 0)
        .help(tooltip)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityHint(Text(tooltip))
    }

    private var iconColor: Color {
        isDisabled ? Color.secondary.opacity(0.6) : Color.primary
    }

    private var hoverBackground: Color {
        guard !isDisabled else { return .clear }
        return isHovered ? Color.primary.opacity(0.12) : .clear
    }

    private var hoverBorder: Color {
        guard !isDisabled else { return .clear }
        return isHovered ? Color.primary.opacity(0.16) : .clear
    }

    private var tooltipBubble: some View {
        Text(tooltip)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.75)
            )
            .fixedSize(horizontal: true, vertical: true)
            .shadow(color: Color.black.opacity(0.16), radius: 6, x: 0, y: 2)
            .allowsHitTesting(false)
    }
}

private struct NotificationToastView: View {
    let notification: NotificationRecord
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: symbolName(notification.kind))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(emphasisColor(notification.kind))
                .frame(width: 16, height: 16)
                .padding(4)
                .background(
                    Circle()
                        .fill(emphasisColor(notification.kind).opacity(0.18))
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(notification.kind.rawValue.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(emphasisColor(notification.kind))
                    Text(notification.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.96))
                        .lineLimit(1)
                }
                Text(notification.message)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(
                        width: 22,
                        height: 22
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.5))
            .accessibilityLabel(Text("Dismiss notification toast"))
            .accessibilityHint(Text("Closes this temporary notification."))
        }
        .padding(.leading, 9)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .frame(minWidth: 280, idealWidth: 360, maxWidth: 420, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: StopmoUI.Radius.card, style: .continuous)
                .fill(Color.black.opacity(0.72))
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(emphasisColor(notification.kind))
                .frame(width: 3)
                .padding(.vertical, 8)
                .padding(.leading, 6)
        }
        .overlay(
            RoundedRectangle(cornerRadius: StopmoUI.Radius.card, style: .continuous)
                .stroke(emphasisColor(notification.kind).opacity(0.45), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.28), radius: 12, x: 0, y: 5)
    }

    private func tone(_ kind: NotificationKind) -> StatusTone {
        switch kind {
        case .info:
            return .neutral
        case .warning:
            return .warning
        case .error:
            return .danger
        }
    }

    private func symbolName(_ kind: NotificationKind) -> String {
        switch kind {
        case .info:
            return "info.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "exclamationmark.octagon.fill"
        }
    }

    private func emphasisColor(_ kind: NotificationKind) -> Color {
        switch kind {
        case .info:
            return Color.blue
        case .warning:
            return Color.orange
        case .error:
            return Color.red
        }
    }
}

private struct NotificationsCenterPanel: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            HStack {
                Text("Notifications")
                    .font(.headline)
                Spacer()
                if !state.notifications.isEmpty {
                    Button("Clear All") {
                        state.clearNotifications()
                    }
                    .buttonStyle(.borderless)
                }
            }

            if state.notifications.isEmpty {
                EmptyStateCard(message: "No notifications yet.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                        ForEach(state.notifications) { notification in
                            VStack(alignment: .leading, spacing: StopmoUI.Spacing.xxs) {
                                HStack(spacing: StopmoUI.Spacing.xs) {
                                    StatusChip(
                                        label: notification.kind.rawValue.uppercased(),
                                        tone: tone(notification.kind)
                                    )
                                    Text(notification.title)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(notification.createdAtLabel)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text(notification.message)
                                    .font(.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let cause = notification.likelyCause, !cause.isEmpty {
                                    Text("Likely cause: \(cause)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let action = notification.suggestedAction, !action.isEmpty {
                                    Text("Suggested action: \(action)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                HStack {
                                    Button("Copy Details") {
                                        state.copyNotificationToPasteboard(notification)
                                    }
                                    .buttonStyle(.borderless)
                                    Spacer()
                                }
                            }
                            .padding(StopmoUI.Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: StopmoUI.Radius.card, style: .continuous)
                                    .fill(Color.secondary.opacity(0.08))
                            )
                        }
                    }
                }
            }
        }
        .padding(StopmoUI.Spacing.md)
        .frame(minWidth: 460, minHeight: 340, idealHeight: 420)
    }

    private func tone(_ kind: NotificationKind) -> StatusTone {
        switch kind {
        case .info:
            return .neutral
        case .warning:
            return .warning
        case .error:
            return .danger
        }
    }
}
