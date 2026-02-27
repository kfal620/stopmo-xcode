import SwiftUI

struct ToolsWorkspaceDiagnosticsPane: View {
    @Binding var latestEvents: [OperationEventRecord]
    @Binding var toolTimeline: [ToolTimelineItem]
    @Binding var eventFilter: ToolEventFilter
    @Binding var eventSearch: String
    let filteredEvents: [OperationEventRecord]
    let clearAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.lg) {
            SectionCard("Progress Timeline", subtitle: "Staged progress milestones for the latest tool run.") {
                if toolTimeline.isEmpty {
                    EmptyStateCard(message: "No timeline yet. Run a tool to capture staged progress.")
                } else {
                    VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                        ForEach(toolTimeline) { item in
                            HStack(alignment: .top, spacing: StopmoUI.Spacing.xs) {
                                StatusChip(label: item.timestampLabel, tone: .neutral)
                                StatusChip(label: item.title, tone: item.tone)
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }

            SectionCard("Operation Events", subtitle: "Captured backend events from the latest tool run.") {
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                    HStack(spacing: StopmoUI.Spacing.sm) {
                        Picker("Filter", selection: $eventFilter) {
                            ForEach(ToolEventFilter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 280)

                        TextField("Search events", text: $eventSearch)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 260)

                        Button("Clear", action: clearAction)
                            .disabled(latestEvents.isEmpty && toolTimeline.isEmpty)
                    }

                    if filteredEvents.isEmpty {
                        EmptyStateCard(message: "No operation events match the current filters.")
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: StopmoUI.Spacing.xxs) {
                                ForEach(filteredEvents) { ev in
                                    HStack(alignment: .firstTextBaseline, spacing: StopmoUI.Spacing.xs) {
                                        StatusChip(label: ev.eventType, tone: ToolsTimelineReducer.toneForEvent(ev))
                                        Text("[\(ev.timestampUtc)] \(ev.message ?? "")")
                                            .font(.system(.caption, design: .monospaced))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                        .frame(minHeight: 120, maxHeight: 260)
                    }
                }
            }
        }
    }
}
