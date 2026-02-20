import SwiftUI

struct NotificationBellButton: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        CommandIconButton(
            systemImage: "bell",
            tooltip: "Notifications",
            accessibilityLabel: "Notifications",
            badgeText: state.notificationsBadgeText,
            badgeTone: state.notificationsBadgeTone
        ) {
            state.toggleNotificationsCenter()
        }
        .popover(isPresented: $state.isNotificationsCenterPresented, arrowEdge: .top) {
            NotificationsCenterPanel()
        }
    }
}

struct NotificationDockView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
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
}

private struct NotificationPresentationModifier: ViewModifier {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                NotificationDockView()
            }
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.2),
                value: state.activeToast?.id
            )
    }
}

extension View {
    func notificationPresentation() -> some View {
        modifier(NotificationPresentationModifier())
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
                    .frame(width: 22, height: 22)
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

struct NotificationsCenterPanel: View {
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
