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
        .overlay(alignment: .bottomLeading) {
            statusBar
                .padding(.leading, 12)
                .padding(.bottom, 12)
        }
        .overlay(alignment: .topTrailing) {
            if let toast = state.activeToast {
                NotificationToastView(notification: toast) {
                    state.dismissToast()
                }
                .padding(.trailing, 14)
                .padding(.top, 14)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .top).combined(with: .opacity)
                )
            }
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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.primary.opacity(0.09), lineWidth: 0.75)
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(repoRootName)
                .lineLimit(1)
                .truncationMode(.middle)
            Divider()
                .frame(height: 12)
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            Text(configName)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: StopmoUI.Radius.chip, style: .continuous)
                .fill(Color.secondary.opacity(0.16))
        )
        .frame(maxWidth: 430, alignment: .leading)
    }

    private func sidebarRow(for section: AppSection) -> some View {
        HStack(alignment: .top, spacing: StopmoUI.Spacing.sm) {
            Image(systemName: section.iconName)
                .frame(width: 18, alignment: .leading)
                .foregroundStyle(.secondary)

            Text(section.rawValue)

            Spacer(minLength: 0)

            if let badge = sidebarBadge(for: section) {
                StatusChip(label: badge.label, tone: badge.tone)
            }
        }
        .padding(.vertical, 2)
    }

    private func sidebarBadge(for section: AppSection) -> SidebarBadge? {
        switch section {
        case .liveMonitor:
            if state.watchServiceState?.running == true {
                return SidebarBadge(label: "RUN", tone: .success)
            }
            return nil
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(
                        width: 28,
                        height: 28
                    )
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(hoverBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
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
                        .offset(x: 9, y: -8)
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
        HStack(alignment: .top, spacing: StopmoUI.Spacing.sm) {
            StatusChip(label: notification.kind.rawValue.uppercased(), tone: tone(notification.kind))
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.xxs) {
                Text(notification.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(notification.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .frame(
                        width: StopmoUI.Width.iconTapTarget,
                        height: StopmoUI.Width.iconTapTarget
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text("Dismiss notification toast"))
            .accessibilityHint(Text("Closes this temporary notification."))
        }
        .padding(StopmoUI.Spacing.sm)
        .frame(width: 420, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: StopmoUI.Radius.card, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 3)
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
