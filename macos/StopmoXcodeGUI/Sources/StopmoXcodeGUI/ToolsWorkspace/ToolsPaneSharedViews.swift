import SwiftUI

struct ToolsPreflightSummaryView: View {
    let preflight: ToolPreflight
    let context: ToolKind

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.xxs) {
            HStack(spacing: StopmoUI.Spacing.xs) {
                StatusChip(label: preflight.ok ? "Preflight OK" : "Preflight Blocked", tone: preflight.ok ? .success : .danger)
                StatusChip(label: context.rawValue, tone: .neutral)
            }
            if !preflight.blockers.isEmpty {
                ForEach(preflight.blockers, id: \.self) { item in
                    Text("Blocker: \(item)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            if !preflight.warnings.isEmpty {
                ForEach(preflight.warnings, id: \.self) { item in
                    Text("Warning: \(item)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

struct ToolsRecentsMenuRow: View {
    let title: String
    let values: [String]
    let onPick: (String) -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: StopmoUI.Spacing.sm) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: StopmoUI.Width.formLabel, alignment: .leading)
            if values.isEmpty {
                Text("No recents yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Menu("Use Recent") {
                    ForEach(values, id: \.self) { value in
                        Button(value) {
                            onPick(value)
                        }
                    }
                }
                Button("Clear", action: onClear)
                    .buttonStyle(.borderless)
            }
        }
    }
}
