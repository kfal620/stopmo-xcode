import SwiftUI

/// Data/view model for tools workspace diagnostics pane.
struct ToolsWorkspaceDiagnosticsPane: View {
    @Binding var latestEvents: [OperationEventRecord]
    @Binding var toolTimeline: [ToolTimelineItem]
    @Binding var eventFilter: ToolEventFilter
    @Binding var eventSearch: String
    let filteredEvents: [OperationEventRecord]
    let clearAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.lg) {
            SectionCard(
                "Progress Timeline",
                subtitle: "Staged progress milestones for the latest tool run.",
                density: .compact,
                surfaceLevel: .panel,
                chrome: .quiet
            ) {
                if toolTimeline.isEmpty {
                    EmptyStateCard(message: "No timeline yet. Run a tool to capture staged progress.")
                } else {
                    VStack(alignment: .leading, spacing: StopmoUI.Spacing.xxs) {
                        ForEach(toolTimeline) { item in
                            HStack(alignment: .firstTextBaseline, spacing: StopmoUI.Spacing.xs) {
                                StatusChip(label: item.timestampLabel, tone: .neutral, density: .compact)
                                StatusChip(label: item.title, tone: item.tone, density: .compact)
                                Text(item.detail)
                                    .metadataTextStyle()
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 1)
                        }
                    }
                }
            }

            SectionCard(
                "Operation Events",
                subtitle: "Captured backend events from the latest tool run.",
                density: .compact,
                surfaceLevel: .panel,
                chrome: .quiet
            ) {
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                    HStack(spacing: StopmoUI.Spacing.xs) {
                        StatusChip(label: "\(latestEvents.count) Events", tone: .neutral, density: .compact)
                        StatusChip(label: "\(filteredEvents.count) Visible", tone: .neutral, density: .compact)
                        Spacer(minLength: 0)
                        Button("Clear", action: clearAction)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(latestEvents.isEmpty && toolTimeline.isEmpty)
                    }

                    HStack(spacing: StopmoUI.Spacing.sm) {
                        Picker("Filter", selection: $eventFilter) {
                            ForEach(ToolEventFilter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 360)

                        TextField("Search events", text: $eventSearch)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 220)
                    }

                    if filteredEvents.isEmpty {
                        EmptyStateCard(message: "No operation events match the current filters.")
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: StopmoUI.Spacing.xxs) {
                                ForEach(filteredEvents) { ev in
                                    HStack(alignment: .firstTextBaseline, spacing: StopmoUI.Spacing.xs) {
                                        StatusChip(label: ev.eventType, tone: ToolsTimelineReducer.toneForEvent(ev), density: .compact)
                                        Text("[\(ev.timestampUtc)] \(ev.message ?? "")")
                                            .font(.system(.caption, design: .monospaced))
                                            .lineLimit(2)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.vertical, 1)
                                }
                            }
                        }
                        .frame(minHeight: 120, maxHeight: 220)
                    }
                }
            }
        }
    }
}
