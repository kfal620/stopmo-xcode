import SwiftUI

private enum QueueStateFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case failed = "Failed"
    case inflight = "Inflight"
    case detected = "Detected"
    case done = "Done"

    var id: String { rawValue }
}

private enum QueueSortOption: String, CaseIterable, Identifiable {
    case updatedDesc = "Updated (Newest)"
    case attemptsDesc = "Attempts (Highest)"
    case shotAsc = "Shot (A-Z)"
    case stateAsc = "State (A-Z)"
    case idDesc = "ID (Newest)"

    var id: String { rawValue }
}

private enum QueueFocusField: Hashable {
    case search
}

struct QueueView: View {
    @EnvironmentObject private var state: AppState

    @State private var searchText: String = ""
    @State private var selectedFilter: QueueStateFilter = .all
    @State private var selectedSort: QueueSortOption = .updatedDesc
    @State private var selectedJobIDs: Set<Int> = []
    @State private var showOnlySelected: Bool = false
    @State private var focusedJobID: Int?
    @State private var pageSize: Int = 75
    @State private var pageIndex: Int = 0
    @FocusState private var focusedField: QueueFocusField?

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.lg) {
            ScreenHeader(
                title: "Queue",
                subtitle: "Triage jobs, retry failures, and export queue state for diagnostics."
            ) {
                HStack(spacing: StopmoUI.Spacing.sm) {
                    if let total = state.queueSnapshot?.total {
                        StatusChip(label: "Jobs \(total)", tone: .neutral)
                    }
                    if failedCount > 0 {
                        StatusChip(label: "Failed \(failedCount)", tone: .danger)
                    }
                    if inflightCount > 0 {
                        StatusChip(label: "Inflight \(inflightCount)", tone: .warning)
                    }
                    Button("Refresh") {
                        Task { await state.refreshLiveData() }
                    }
                    .disabled(state.isBusy)
                }
            }

            controlsCard
            jobsTableCard
            selectedJobDetailCard
            Spacer()
        }
        .padding(StopmoUI.Spacing.lg)
        .onAppear {
            if state.queueSnapshot == nil {
                Task { await state.refreshLiveData() }
            } else {
                syncFocusedJob()
            }
            focusedField = .search
        }
        .onChange(of: state.queueSnapshot?.total ?? -1) { _, _ in
            pruneSelection()
            clampPageIndex()
            syncFocusedJob()
        }
        .onChange(of: filteredJobs.map(\.id)) { _, _ in
            pruneSelection()
            clampPageIndex()
            syncFocusedJob()
        }
        .onChange(of: pageSize) { _, _ in
            clampPageIndex()
            syncFocusedJob()
        }
    }

    private var controlsCard: some View {
        SectionCard("Filters & Actions") {
            HStack(spacing: StopmoUI.Spacing.sm) {
                TextField("Search id/shot/source/error", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                    .focused($focusedField, equals: .search)

                Picker("State", selection: $selectedFilter) {
                    ForEach(QueueStateFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 360)

                Picker("Sort", selection: $selectedSort) {
                    ForEach(QueueSortOption.allCases) { sort in
                        Text(sort.rawValue).tag(sort)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)

                Toggle("Selected Only", isOn: $showOnlySelected)
                    .toggleStyle(.switch)
            }

            HStack(spacing: StopmoUI.Spacing.sm) {
                Button("Retry Failed") {
                    Task { await state.retryFailedQueueJobs() }
                }
                .disabled(state.isBusy || failedCount == 0)

                Button("Retry Selected Failed") {
                    Task { await state.retryFailedQueueJobs(jobIds: selectedFailedIds) }
                }
                .disabled(state.isBusy || selectedFailedIds.isEmpty)

                Button("Export Queue Snapshot") {
                    state.exportQueueSnapshot()
                }
                .disabled(state.isBusy || state.queueSnapshot == nil)

                Button("Clear Selection") {
                    selectedJobIDs.removeAll()
                }
                .disabled(selectedJobIDs.isEmpty)

                Spacer()

                StatusChip(label: "Visible \(filteredJobs.count)", tone: .neutral)
                StatusChip(label: "Selected \(selectedJobIDs.count)", tone: selectedJobIDs.isEmpty ? .neutral : .warning)
            }

            HStack(spacing: StopmoUI.Spacing.sm) {
                Picker("Page Size", selection: $pageSize) {
                    Text("50").tag(50)
                    Text("75").tag(75)
                    Text("100").tag(100)
                    Text("150").tag(150)
                }
                .pickerStyle(.menu)
                .frame(width: 110)

                Button("Previous") {
                    pageIndex = max(0, pageIndex - 1)
                }
                .disabled(pageIndex == 0 || filteredJobs.isEmpty)

                Button("Next") {
                    pageIndex = min(pageCount - 1, pageIndex + 1)
                }
                .disabled(pageIndex >= pageCount - 1 || filteredJobs.isEmpty)

                Spacer()

                StatusChip(label: "Page \(safePageIndex + 1)/\(pageCount)", tone: .neutral)
                StatusChip(label: pageRangeLabel, tone: .neutral)
            }
        }
    }

    private var jobsTableCard: some View {
        SectionCard("Jobs Table") {
            if let queue = state.queueSnapshot {
                KeyValueRow(key: "DB", value: queue.dbPath)
                KeyValueRow(key: "Total Jobs", value: "\(queue.total)")

                if filteredJobs.isEmpty {
                    EmptyStateCard(message: "No queue rows match the current filters.")
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        LazyVStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                            headerRow
                            Divider()
                            ForEach(pagedJobs) { job in
                                row(job)
                            }
                        }
                    }
                    .frame(minHeight: 220, maxHeight: 360)
                }
            } else {
                EmptyStateCard(message: "No queue data yet.")
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            col("Sel", width: 40)
            col("ID", width: 60)
            col("State", width: 100)
            col("Shot", width: 140)
            col("Frame", width: 70)
            col("Attempts", width: 80)
            col("Worker", width: 120)
            col("Source", width: 240)
            col("Updated", width: 210)
            col("Error", width: 250)
            col("Actions", width: 180)
        }
        .font(.caption.bold())
    }

    private func row(_ job: QueueJobRecord) -> some View {
        HStack(spacing: 10) {
            IconActionButton(
                systemName: selectedJobIDs.contains(job.id) ? "checkmark.square.fill" : "square",
                accessibilityLabel: selectedJobIDs.contains(job.id)
                    ? "Deselect queue job \(job.id)"
                    : "Select queue job \(job.id)",
                accessibilityHint: "Toggles this queue job in bulk selection."
            ) {
                toggleSelection(job.id)
            }
            .help("Toggle selection")
            .frame(width: 40, alignment: .leading)

            col("\(job.id)", width: 60)
            stateCell(job.state)
            col(job.shot, width: 140)
            col("\(job.frame)", width: 70)
            col("\(job.attempts)", width: 80)
            col(job.workerId ?? "-", width: 120)
            col((job.source as NSString).lastPathComponent, width: 240)
            col(job.updatedAt, width: 210)
            col(job.lastError ?? "", width: 250)
            actionsCell(job)
        }
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: StopmoUI.Radius.chip, style: .continuous)
                .fill(focusedJobID == job.id ? Color.accentColor.opacity(0.12) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            focusedJobID = job.id
        }
    }

    private func actionsCell(_ job: QueueJobRecord) -> some View {
        HStack(spacing: 8) {
            IconActionButton(
                systemName: "folder",
                accessibilityLabel: "Open source path for queue job \(job.id)",
                accessibilityHint: "Opens the source file in Finder."
            ) {
                state.openPathInFinder(job.source)
            }
            .help("Open source in Finder")

            IconActionButton(
                systemName: "link",
                accessibilityLabel: "Copy source path for queue job \(job.id)",
                accessibilityHint: "Copies the source path."
            ) {
                state.copyTextToPasteboard(job.source, label: "source path")
            }
            .help("Copy source path")

            IconActionButton(
                systemName: "doc.on.doc",
                accessibilityLabel: "Copy last error for queue job \(job.id)",
                accessibilityHint: "Copies the most recent error text.",
                isDisabled: (job.lastError ?? "").isEmpty
            ) {
                state.copyTextToPasteboard(job.lastError ?? "", label: "error")
            }
            .help("Copy last error")

            IconActionButton(
                systemName: "arrow.counterclockwise",
                accessibilityLabel: "Retry queue job \(job.id)",
                accessibilityHint: "Retries this job if it is in failed state.",
                isDisabled: job.state.lowercased() != "failed"
            ) {
                Task { await state.retryFailedQueueJobs(jobIds: [job.id]) }
            }
            .help("Retry this failed job")
        }
        .frame(width: 180, alignment: .leading)
    }

    private var selectedJobDetailCard: some View {
        SectionCard("Selected Job") {
            if let job = selectedJob {
                KeyValueRow(key: "Job ID", value: "\(job.id)")
                KeyValueRow(key: "State", value: job.state, tone: stateTone(job.state))
                KeyValueRow(key: "Shot", value: job.shot)
                KeyValueRow(key: "Frame", value: "\(job.frame)")
                KeyValueRow(key: "Attempts", value: "\(job.attempts)")
                KeyValueRow(key: "Worker", value: job.workerId ?? "-")
                KeyValueRow(key: "Detected", value: job.detectedAt)
                KeyValueRow(key: "Updated", value: job.updatedAt)
                KeyValueRow(key: "Source", value: job.source)
                KeyValueRow(key: "Shot Output", value: shotOutputPath(for: job))

                if let lastError = job.lastError, !lastError.isEmpty {
                    VStack(alignment: .leading, spacing: StopmoUI.Spacing.xxs) {
                        Text("Last Error")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ScrollView {
                            Text(lastError)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(minHeight: 58, maxHeight: 104)
                        .padding(StopmoUI.Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: StopmoUI.Radius.chip, style: .continuous)
                                .fill(Color.red.opacity(0.08))
                        )
                    }
                }

                HStack(spacing: StopmoUI.Spacing.sm) {
                    Button("Open Source") {
                        state.openPathInFinder(job.source)
                    }
                    Button("Open Shot Output") {
                        state.openPathInFinder(shotOutputPath(for: job))
                    }
                    Button("Copy Error") {
                        state.copyTextToPasteboard(job.lastError ?? "", label: "error")
                    }
                    .disabled((job.lastError ?? "").isEmpty)
                    Button("Retry Job") {
                        Task { await state.retryFailedQueueJobs(jobIds: [job.id]) }
                    }
                    .disabled(job.state.lowercased() != "failed")
                }
            } else {
                EmptyStateCard(message: "Select a queue row to inspect full context and actions.")
            }
        }
    }

    private func col(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width, alignment: .leading)
    }

    private func stateCell(_ stateValue: String) -> some View {
        HStack {
            StatusChip(label: stateValue, tone: stateTone(stateValue))
                .frame(width: 100, alignment: .leading)
        }
    }

    private func stateTone(_ value: String) -> StatusTone {
        let normalized = value.lowercased()
        if normalized.contains("failed") {
            return .danger
        }
        if normalized.contains("done") {
            return .success
        }
        if normalized.contains("detected")
            || normalized.contains("decoding")
            || normalized.contains("xform")
            || normalized.contains("dpx_write")
        {
            return .warning
        }
        return .neutral
    }

    private func toggleSelection(_ id: Int) {
        if selectedJobIDs.contains(id) {
            selectedJobIDs.remove(id)
        } else {
            selectedJobIDs.insert(id)
        }
        focusedJobID = id
    }

    private func pruneSelection() {
        let existing = Set((state.queueSnapshot?.recent ?? []).map(\.id))
        selectedJobIDs = selectedJobIDs.intersection(existing)
    }

    private func syncFocusedJob() {
        guard !filteredJobs.isEmpty else {
            focusedJobID = nil
            return
        }
        if let focusedJobID, pagedJobs.contains(where: { $0.id == focusedJobID }) {
            return
        }
        focusedJobID = pagedJobs.first?.id
    }

    private var selectedJob: QueueJobRecord? {
        if let focusedJobID {
            if let row = filteredJobs.first(where: { $0.id == focusedJobID }) {
                return row
            }
            if let row = state.queueSnapshot?.recent.first(where: { $0.id == focusedJobID }) {
                return row
            }
        }
        return pagedJobs.first
    }

    private var failedCount: Int {
        state.queueSnapshot?.counts["failed", default: 0] ?? 0
    }

    private var inflightCount: Int {
        let counts = state.queueSnapshot?.counts ?? [:]
        return counts["detected", default: 0]
            + counts["decoding", default: 0]
            + counts["xform", default: 0]
            + counts["dpx_write", default: 0]
    }

    private var selectedFailedIds: [Int] {
        (state.queueSnapshot?.recent ?? [])
            .filter { selectedJobIDs.contains($0.id) && $0.state.lowercased() == "failed" }
            .map(\.id)
    }

    private var filteredJobs: [QueueJobRecord] {
        guard let jobs = state.queueSnapshot?.recent else { return [] }
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var rows = jobs.filter { job in
            if showOnlySelected, !selectedJobIDs.contains(job.id) {
                return false
            }

            let stateValue = job.state.lowercased()
            switch selectedFilter {
            case .all:
                break
            case .failed:
                if stateValue != "failed" { return false }
            case .inflight:
                if !(stateValue == "detected" || stateValue == "decoding" || stateValue == "xform" || stateValue == "dpx_write") {
                    return false
                }
            case .detected:
                if stateValue != "detected" { return false }
            case .done:
                if stateValue != "done" { return false }
            }

            if !trimmedSearch.isEmpty {
                let haystack = [
                    "\(job.id)",
                    job.state,
                    job.shot,
                    "\(job.frame)",
                    "\(job.attempts)",
                    job.workerId ?? "",
                    job.source,
                    (job.source as NSString).lastPathComponent,
                    job.updatedAt,
                    job.lastError ?? "",
                ]
                    .joined(separator: " ")
                    .lowercased()
                if !haystack.contains(trimmedSearch) {
                    return false
                }
            }

            return true
        }

        switch selectedSort {
        case .updatedDesc:
            rows.sort { $0.updatedAt > $1.updatedAt }
        case .attemptsDesc:
            rows.sort {
                if $0.attempts == $1.attempts {
                    return $0.updatedAt > $1.updatedAt
                }
                return $0.attempts > $1.attempts
            }
        case .shotAsc:
            rows.sort {
                if $0.shot == $1.shot {
                    return $0.frame < $1.frame
                }
                return $0.shot.localizedCaseInsensitiveCompare($1.shot) == .orderedAscending
            }
        case .stateAsc:
            rows.sort {
                if $0.state == $1.state {
                    return $0.updatedAt > $1.updatedAt
                }
                return $0.state.localizedCaseInsensitiveCompare($1.state) == .orderedAscending
            }
        case .idDesc:
            rows.sort { $0.id > $1.id }
        }

        return rows
    }

    private var safePageIndex: Int {
        guard !filteredJobs.isEmpty else { return 0 }
        return min(max(0, pageIndex), pageCount - 1)
    }

    private var pageCount: Int {
        guard !filteredJobs.isEmpty else { return 1 }
        return max(1, (filteredJobs.count + pageSize - 1) / pageSize)
    }

    private var pagedJobs: [QueueJobRecord] {
        guard !filteredJobs.isEmpty else { return [] }
        let start = safePageIndex * pageSize
        let end = min(filteredJobs.count, start + pageSize)
        if start >= end {
            return []
        }
        return Array(filteredJobs[start..<end])
    }

    private var pageRangeLabel: String {
        guard !pagedJobs.isEmpty else { return "Rows 0-0" }
        let start = safePageIndex * pageSize + 1
        let end = start + pagedJobs.count - 1
        return "Rows \(start)-\(end)"
    }

    private func clampPageIndex() {
        pageIndex = safePageIndex
    }

    private func shotOutputPath(for job: QueueJobRecord) -> String {
        let base = state.config.watch.outputDir.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            return job.shot
        }
        return (base as NSString).appendingPathComponent(job.shot)
    }
}
