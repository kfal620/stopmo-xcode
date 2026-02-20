import SwiftUI

private enum HistorySortOption: String, CaseIterable, Identifiable {
    case startNewest = "Start (Newest)"
    case failedHighest = "Failed (Highest)"
    case jobsHighest = "Jobs (Highest)"
    case runIdAsc = "Run ID (A-Z)"

    var id: String { rawValue }
}

private struct CompareRowModel: Identifiable {
    let id = UUID()
    let label: String
    let leftValue: String
    let rightValue: String
    let changed: Bool
}

struct HistoryView: View {
    @EnvironmentObject private var state: AppState

    @State private var searchText: String = ""
    @State private var sortOption: HistorySortOption = .startNewest
    @State private var showOnlyFailures: Bool = false
    @State private var compareSelectionOrder: [String] = []
    @State private var showOnlySelected: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.lg) {
                ScreenHeader(
                    title: "History",
                    subtitle: "Run summaries and reproducibility compare mode."
                ) {
                    HStack(spacing: StopmoUI.Spacing.sm) {
                        if let count = state.historySummary?.count {
                            StatusChip(label: "Runs \(count)", tone: .neutral)
                        }
                        StatusChip(
                            label: "Selected \(selectedRunIds.count)/2",
                            tone: selectedRunIds.count == 2 ? .success : .warning
                        )
                        Button("Refresh") {
                            Task { await state.refreshHistory() }
                        }
                        .disabled(state.isBusy)
                    }
                }

                controlsCard
                compareCard
                historyCardsSection
            }
            .padding(StopmoUI.Spacing.lg)
        }
        .onAppear {
            if state.historySummary == nil {
                Task { await state.refreshHistory() }
            }
        }
        .onChange(of: state.historySummary?.count ?? -1) { _, _ in
            pruneCompareSelection()
        }
    }

    private var controlsCard: some View {
        SectionCard("History Filters & Compare Controls") {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                HStack(spacing: StopmoUI.Spacing.sm) {
                    TextField("Search run/shots/outputs/pipeline/tool version", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 280, idealWidth: 420, maxWidth: 520)
                        .layoutPriority(1)

                    Picker("Sort", selection: $sortOption) {
                        ForEach(HistorySortOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 190)
                }

                HStack(spacing: StopmoUI.Spacing.md) {
                    Toggle(isOn: $showOnlyFailures) {
                        Text("Only Failures")
                            .lineLimit(1)
                    }
                    .toggleStyle(.switch)
                    .fixedSize(horizontal: true, vertical: false)

                    Toggle(isOn: $showOnlySelected) {
                        Text("Only Selected")
                            .lineLimit(1)
                    }
                    .toggleStyle(.switch)
                    .fixedSize(horizontal: true, vertical: false)

                    Button("Select Newest Two") {
                        selectNewestTwo()
                    }
                    .disabled(filteredRuns.count < 2)

                    Button("Clear Selection") {
                        compareSelectionOrder = []
                    }
                    .disabled(compareSelectionOrder.isEmpty)

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var compareCard: some View {
        SectionCard("Compare Runs", subtitle: "Counts, failures, outputs, pipeline hashes, and tool versions.") {
            if selectedCompareRuns.count != 2 {
                EmptyStateCard(message: "Select two runs to compare reproducibility and output deltas.")
            } else {
                let left = selectedCompareRuns[0]
                let right = selectedCompareRuns[1]
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                    HStack(spacing: StopmoUI.Spacing.sm) {
                        StatusChip(label: left.runId, tone: .neutral)
                        Text("vs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        StatusChip(label: right.runId, tone: .neutral)
                    }

                    ForEach(compareRows(left: left, right: right)) { row in
                        HStack(alignment: .top, spacing: StopmoUI.Spacing.sm) {
                            Text(row.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 150, alignment: .leading)
                            Text(row.leftValue)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(row.rightValue)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            StatusChip(label: row.changed ? "Changed" : "Same", tone: row.changed ? .warning : .success)
                        }
                    }

                    HStack(spacing: StopmoUI.Spacing.sm) {
                        Button("Copy Compare Summary") {
                            state.copyTextToPasteboard(compareSummaryText(left: left, right: right), label: "compare summary")
                        }
                        Button("Open Left First Output") {
                            if let output = left.outputs.first {
                                state.openPathInFinder(output)
                            }
                        }
                        .disabled(left.outputs.isEmpty)
                        Button("Open Right First Output") {
                            if let output = right.outputs.first {
                                state.openPathInFinder(output)
                            }
                        }
                        .disabled(right.outputs.isEmpty)
                    }
                }
            }
        }
    }

    private var historyCardsSection: some View {
        SectionCard("Run Cards", subtitle: "Selectable run summaries with quick output and manifest actions.") {
            if filteredRuns.isEmpty {
                EmptyStateCard(message: "No run cards match the current filters.")
            } else {
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                    ForEach(filteredRuns) { run in
                        runCard(run)
                    }
                }
            }
        }
    }

    private func runCard(_ run: HistoryRunRecord) -> some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
            HStack(spacing: StopmoUI.Spacing.sm) {
                Button {
                    toggleCompareSelection(run.id)
                } label: {
                    Image(systemName: selectedRunIds.contains(run.id) ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.plain)
                .help("Select for compare mode")

                Text(run.runId)
                    .font(.headline)

                StatusChip(label: "Jobs \(run.totalJobs)", tone: .neutral)
                StatusChip(label: "Failed \(run.failedJobs)", tone: run.failedJobs > 0 ? .danger : .success)
                if run.failedJobs > 0 {
                    StatusChip(label: "Needs Attention", tone: .warning)
                }
            }

            KeyValueRow(key: "Start", value: run.startUtc)
            KeyValueRow(key: "End", value: run.endUtc)
            KeyValueRow(key: "States", value: compactCounts(run.counts))
            KeyValueRow(key: "Shots", value: joinedPreview(run.shots))
            KeyValueRow(key: "Pipeline Hashes", value: joinedPreview(run.pipelineHashes))
            KeyValueRow(key: "Tool Versions", value: joinedPreview(run.toolVersions))
            KeyValueRow(key: "Outputs", value: joinedPreview(run.outputs))

            HStack(spacing: StopmoUI.Spacing.sm) {
                Button("Copy Run Summary") {
                    state.copyTextToPasteboard(runSummaryText(run), label: "run summary")
                }
                Button("Open First Output") {
                    if let firstOutput = run.outputs.first {
                        state.openPathInFinder(firstOutput)
                    }
                }
                .disabled(run.outputs.isEmpty)
                Button("Open First Manifest") {
                    if let firstManifest = run.manifestPaths.first {
                        state.openPathInFinder(firstManifest)
                    }
                }
                .disabled(run.manifestPaths.isEmpty)
            }
        }
        .padding(StopmoUI.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: StopmoUI.Radius.card, style: .continuous)
                .fill(selectedRunIds.contains(run.id) ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.08))
        )
    }

    private var selectedRunIds: Set<String> {
        Set(compareSelectionOrder)
    }

    private var selectedCompareRuns: [HistoryRunRecord] {
        let lookup = Dictionary(uniqueKeysWithValues: (state.historySummary?.runs ?? []).map { ($0.id, $0) })
        return compareSelectionOrder.compactMap { lookup[$0] }
    }

    private var filteredRuns: [HistoryRunRecord] {
        guard let runs = state.historySummary?.runs else { return [] }
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var out = runs.filter { run in
            if showOnlySelected && !selectedRunIds.contains(run.id) {
                return false
            }
            if showOnlyFailures && run.failedJobs == 0 {
                return false
            }
            if term.isEmpty {
                return true
            }
            let haystack = [
                run.runId,
                run.startUtc,
                run.endUtc,
                run.shots.joined(separator: " "),
                run.outputs.joined(separator: " "),
                run.pipelineHashes.joined(separator: " "),
                run.toolVersions.joined(separator: " "),
                run.manifestPaths.joined(separator: " "),
                compactCounts(run.counts),
            ]
                .joined(separator: " ")
                .lowercased()
            return haystack.contains(term)
        }

        switch sortOption {
        case .startNewest:
            out.sort { $0.startUtc > $1.startUtc }
        case .failedHighest:
            out.sort {
                if $0.failedJobs == $1.failedJobs {
                    return $0.startUtc > $1.startUtc
                }
                return $0.failedJobs > $1.failedJobs
            }
        case .jobsHighest:
            out.sort {
                if $0.totalJobs == $1.totalJobs {
                    return $0.startUtc > $1.startUtc
                }
                return $0.totalJobs > $1.totalJobs
            }
        case .runIdAsc:
            out.sort { $0.runId.localizedCaseInsensitiveCompare($1.runId) == .orderedAscending }
        }
        return out
    }

    private func selectNewestTwo() {
        let candidates = filteredRuns
        guard candidates.count >= 2 else { return }
        compareSelectionOrder = [candidates[0].id, candidates[1].id]
    }

    private func toggleCompareSelection(_ runId: String) {
        if compareSelectionOrder.contains(runId) {
            compareSelectionOrder.removeAll { $0 == runId }
            return
        }
        compareSelectionOrder.append(runId)
        if compareSelectionOrder.count > 2 {
            compareSelectionOrder.removeFirst(compareSelectionOrder.count - 2)
        }
    }

    private func pruneCompareSelection() {
        let valid = Set((state.historySummary?.runs ?? []).map(\.id))
        compareSelectionOrder = compareSelectionOrder.filter { valid.contains($0) }
        if compareSelectionOrder.count > 2 {
            compareSelectionOrder = Array(compareSelectionOrder.suffix(2))
        }
    }

    private func compareRows(left: HistoryRunRecord, right: HistoryRunRecord) -> [CompareRowModel] {
        let leftCounts = compactCounts(left.counts)
        let rightCounts = compactCounts(right.counts)
        let leftOutputs = joinedPreview(left.outputs)
        let rightOutputs = joinedPreview(right.outputs)
        let leftHashes = joinedPreview(left.pipelineHashes)
        let rightHashes = joinedPreview(right.pipelineHashes)
        let leftTools = joinedPreview(left.toolVersions)
        let rightTools = joinedPreview(right.toolVersions)

        return [
            CompareRowModel(
                label: "Total Jobs",
                leftValue: "\(left.totalJobs)",
                rightValue: "\(right.totalJobs)",
                changed: left.totalJobs != right.totalJobs
            ),
            CompareRowModel(
                label: "Failed Jobs",
                leftValue: "\(left.failedJobs)",
                rightValue: "\(right.failedJobs)",
                changed: left.failedJobs != right.failedJobs
            ),
            CompareRowModel(
                label: "State Counts",
                leftValue: leftCounts,
                rightValue: rightCounts,
                changed: leftCounts != rightCounts
            ),
            CompareRowModel(
                label: "Outputs",
                leftValue: leftOutputs,
                rightValue: rightOutputs,
                changed: Set(left.outputs) != Set(right.outputs)
            ),
            CompareRowModel(
                label: "Pipeline Hash",
                leftValue: leftHashes,
                rightValue: rightHashes,
                changed: Set(left.pipelineHashes) != Set(right.pipelineHashes)
            ),
            CompareRowModel(
                label: "Tool Version",
                leftValue: leftTools,
                rightValue: rightTools,
                changed: Set(left.toolVersions) != Set(right.toolVersions)
            ),
        ]
    }

    private func compareSummaryText(left: HistoryRunRecord, right: HistoryRunRecord) -> String {
        let rows = compareRows(left: left, right: right)
        var lines: [String] = []
        lines.append("Compare \(left.runId) vs \(right.runId)")
        for row in rows {
            lines.append("\(row.label):")
            lines.append("  \(left.runId): \(row.leftValue)")
            lines.append("  \(right.runId): \(row.rightValue)")
            lines.append("  Changed: \(row.changed ? "yes" : "no")")
        }
        return lines.joined(separator: "\n")
    }

    private func runSummaryText(_ run: HistoryRunRecord) -> String {
        [
            "Run: \(run.runId)",
            "Start: \(run.startUtc)",
            "End: \(run.endUtc)",
            "Jobs: \(run.totalJobs)",
            "Failed: \(run.failedJobs)",
            "Counts: \(compactCounts(run.counts))",
            "Shots: \(run.shots.joined(separator: ", "))",
            "Outputs: \(run.outputs.joined(separator: ", "))",
            "Pipeline Hashes: \(run.pipelineHashes.joined(separator: ", "))",
            "Tool Versions: \(run.toolVersions.joined(separator: ", "))",
            "Manifest Paths: \(run.manifestPaths.joined(separator: ", "))",
        ].joined(separator: "\n")
    }

    private func compactCounts(_ counts: [String: Int]) -> String {
        let keys = ["detected", "decoding", "xform", "dpx_write", "done", "failed"]
        return keys
            .filter { counts[$0] != nil }
            .map { "\($0)=\(counts[$0] ?? 0)" }
            .joined(separator: ", ")
    }

    private func joinedPreview(_ values: [String], maxItems: Int = 4) -> String {
        guard !values.isEmpty else { return "-" }
        let head = Array(values.prefix(maxItems))
        if values.count > maxItems {
            return head.joined(separator: ", ") + " … (+\(values.count - maxItems))"
        }
        return head.joined(separator: ", ")
    }
}
