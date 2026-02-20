import SwiftUI

private enum ShotStateFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case issues = "Issues"
    case processing = "Processing"
    case queued = "Queued"
    case done = "Done"

    var id: String { rawValue }
}

private enum ShotSortOption: String, CaseIterable, Identifiable {
    case updatedDesc = "Updated (Newest)"
    case progressDesc = "Progress (High-Low)"
    case failedDesc = "Failed Frames"
    case shotAsc = "Shot (A-Z)"

    var id: String { rawValue }
}

private enum ShotsFocusField: Hashable {
    case search
}

struct ShotsView: View {
    @EnvironmentObject private var state: AppState

    @State private var searchText: String = ""
    @State private var selectedFilter: ShotStateFilter = .all
    @State private var selectedSort: ShotSortOption = .updatedDesc
    @State private var selectedShotName: String?
    @State private var pageSize: Int = 75
    @State private var pageIndex: Int = 0
    @FocusState private var focusedField: ShotsFocusField?

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.lg) {
            ScreenHeader(
                title: "Shots",
                subtitle: "Shot-level progress, assembly triage, and output navigation."
            ) {
                HStack(spacing: StopmoUI.Spacing.sm) {
                    if let count = state.shotsSnapshot?.count {
                        StatusChip(label: "Shots \(count)", tone: .neutral)
                    }
                    if issuesCount > 0 {
                        StatusChip(label: "Issues \(issuesCount)", tone: .danger)
                    }
                    if processingCount > 0 {
                        StatusChip(label: "Processing \(processingCount)", tone: .warning)
                    }
                    Button("Refresh") {
                        Task { await state.refreshLiveData() }
                    }
                    .disabled(state.isBusy)
                }
            }

            controlsCard
            shotsTableCard
            selectedShotDetailCard
            Spacer()
        }
        .padding(StopmoUI.Spacing.lg)
        .onAppear {
            if state.shotsSnapshot == nil {
                Task { await state.refreshLiveData() }
            } else {
                syncSelectedShot()
            }
            focusedField = .search
        }
        .onChange(of: state.shotsSnapshot?.count ?? -1) { _, _ in
            clampPageIndex()
            syncSelectedShot()
        }
        .onChange(of: filteredShots.map(\.shotName)) { _, _ in
            clampPageIndex()
            syncSelectedShot()
        }
        .onChange(of: pageSize) { _, _ in
            clampPageIndex()
            syncSelectedShot()
        }
    }

    private var controlsCard: some View {
        SectionCard("Filters") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: StopmoUI.Spacing.sm) {
                    TextField("Search shot/output/review path", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 290)
                        .focused($focusedField, equals: .search)

                    Picker("State", selection: $selectedFilter) {
                        ForEach(ShotStateFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 420)

                    Picker("Sort", selection: $selectedSort) {
                        ForEach(ShotSortOption.allCases) { sort in
                            Text(sort.rawValue).tag(sort)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)

                    StatusChip(label: "Visible \(filteredShots.count)", tone: .neutral)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ScrollView(.horizontal, showsIndicators: false) {
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
                    .disabled(pageIndex == 0 || filteredShots.isEmpty)

                    Button("Next") {
                        pageIndex = min(pageCount - 1, pageIndex + 1)
                    }
                    .disabled(pageIndex >= pageCount - 1 || filteredShots.isEmpty)

                    StatusChip(label: "Page \(safePageIndex + 1)/\(pageCount)", tone: .neutral)
                    StatusChip(label: pageRangeLabel, tone: .neutral)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var shotsTableCard: some View {
        SectionCard("Shot Summary Table") {
            if state.shotsSnapshot != nil {
                if filteredShots.isEmpty {
                    EmptyStateCard(message: "No shots match the current filters.")
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        LazyVStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                            headerRow
                            Divider()
                            ForEach(pagedShots) { row in
                                shotRow(row)
                            }
                        }
                    }
                    .frame(minHeight: 220, maxHeight: 340)
                }
            } else {
                EmptyStateCard(message: "No shot summary yet.")
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            col("Select", width: 58)
            col("Shot", width: 160)
            col("State", width: 90)
            col("Frames", width: 120)
            col("Done", width: 80)
            col("Failed", width: 80)
            col("Inflight", width: 80)
            col("Progress", width: 90)
            col("Assembly", width: 110)
            col("Updated", width: 210)
            col("Output MOV", width: 250)
            col("Review MOV", width: 250)
            col("Actions", width: 110)
        }
        .font(.caption.bold())
    }

    private func shotRow(_ shot: ShotSummaryRow) -> some View {
        HStack(spacing: 10) {
            IconActionButton(
                systemName: selectedShotName == shot.shotName ? "checkmark.circle.fill" : "circle",
                accessibilityLabel: selectedShotName == shot.shotName
                    ? "Deselect shot \(shot.shotName)"
                    : "Select shot \(shot.shotName)",
                accessibilityHint: "Selects this shot for detail inspection."
            ) {
                selectedShotName = shot.shotName
            }
            .foregroundStyle(selectedShotName == shot.shotName ? Color.accentColor : .secondary)
            .help("Select shot")
            .frame(width: 58, alignment: .leading)

            col(shot.shotName, width: 160)
            shotStateCell(shot.state)
            col("\(shot.totalFrames)", width: 120)
            col("\(shot.doneFrames)", width: 80)
            col("\(shot.failedFrames)", width: 80)
            col("\(shot.inflightFrames)", width: 80)
            progressCell(shot.progressRatio)
            assemblyCell(shot.assemblyState)
            col(shot.lastUpdatedAt ?? "-", width: 210)
            col(shot.outputMovPath ?? "-", width: 250)
            col(shot.reviewMovPath ?? "-", width: 250)
            actionsCell(for: shot)
        }
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: StopmoUI.Radius.chip, style: .continuous)
                .fill(selectedShotName == shot.shotName ? Color.accentColor.opacity(0.12) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedShotName = shot.shotName
        }
    }

    private func actionsCell(for shot: ShotSummaryRow) -> some View {
        HStack(spacing: 8) {
            IconActionButton(
                systemName: "folder",
                accessibilityLabel: "Open shot folder for \(shot.shotName)",
                accessibilityHint: "Opens the shot folder in Finder."
            ) {
                state.openPathInFinder(shotRootPath(for: shot))
            }
            .help("Open shot folder in Finder")

            IconActionButton(
                systemName: "doc.on.doc",
                accessibilityLabel: "Copy shot name \(shot.shotName)",
                accessibilityHint: "Copies the selected shot name."
            ) {
                state.copyTextToPasteboard(shot.shotName, label: "shot name")
            }
            .help("Copy shot name")
        }
        .frame(width: 110, alignment: .leading)
    }

    private var selectedShotDetailCard: some View {
        SectionCard("Shot Detail") {
            if let shot = selectedShot {
                KeyValueRow(key: "Shot", value: shot.shotName)
                KeyValueRow(key: "State", value: shot.state, tone: stateTone(shot.state))
                KeyValueRow(key: "Assembly", value: shot.assemblyState ?? "-", tone: assemblyTone(shot.assemblyState ?? "-"))
                KeyValueRow(key: "Frames", value: "\(shot.doneFrames) done / \(shot.failedFrames) failed / \(shot.inflightFrames) inflight / \(shot.totalFrames) total")
                KeyValueRow(key: "Last Updated", value: shot.lastUpdatedAt ?? "-")

                if let exposure = shot.exposureOffsetStops {
                    KeyValueRow(key: "Effective Exposure Offset", value: String(format: "%.3f stops", exposure))
                } else {
                    KeyValueRow(key: "Effective Exposure Offset", value: "-")
                }

                if let wb = shot.wbMultipliers, !wb.isEmpty {
                    let wbText = wb.map { String(format: "%.4f", $0) }.joined(separator: ", ")
                    KeyValueRow(key: "Locked WB Multipliers", value: wbText)
                } else {
                    KeyValueRow(key: "Locked WB Multipliers", value: "-")
                }

                KeyValueRow(
                    key: "Output MOV",
                    value: shot.outputMovPath ?? "-",
                    tone: pathExists(shot.outputMovPath) ? .success : .neutral
                )
                KeyValueRow(
                    key: "Review MOV",
                    value: shot.reviewMovPath ?? "-",
                    tone: pathExists(shot.reviewMovPath) ? .success : .neutral
                )

                VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                    Text("Open In Finder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: StopmoUI.Spacing.sm) {
                        Button("Shot Folder") {
                            state.openPathInFinder(shotRootPath(for: shot))
                        }
                        Button("DPX") {
                            state.openPathInFinder(dpxPath(for: shot))
                        }
                        Button("Frame JSON") {
                            state.openPathInFinder(frameJsonPath(for: shot))
                        }
                        Button("Truth Frame") {
                            state.openPathInFinder(truthFramePath(for: shot))
                        }
                        Button("Manifest") {
                            state.openPathInFinder(manifestPath(for: shot))
                        }
                        Button("Output MOV") {
                            state.openPathInFinder(shot.outputMovPath ?? "")
                        }
                        .disabled((shot.outputMovPath ?? "").isEmpty)
                        Button("Review MOV") {
                            state.openPathInFinder(shot.reviewMovPath ?? "")
                        }
                        .disabled((shot.reviewMovPath ?? "").isEmpty)
                    }
                }
            } else {
                EmptyStateCard(message: "Select a shot row to inspect details and output actions.")
            }
        }
    }

    private func col(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width, alignment: .leading)
    }

    private func shotStateCell(_ state: String) -> some View {
        HStack {
            StatusChip(label: state, tone: stateTone(state))
                .frame(width: 90, alignment: .leading)
        }
    }

    private func progressCell(_ ratio: Double) -> some View {
        let pct = Int((ratio * 100.0).rounded())
        return HStack {
            StatusChip(label: "\(pct)%", tone: progressTone(ratio))
                .frame(width: 90, alignment: .leading)
        }
    }

    private func assemblyCell(_ assemblyState: String?) -> some View {
        let text = assemblyState ?? "-"
        return HStack {
            StatusChip(label: text, tone: assemblyTone(text))
                .frame(width: 110, alignment: .leading)
        }
    }

    private func stateTone(_ value: String) -> StatusTone {
        let v = value.lowercased()
        if v.contains("failed") || v.contains("issue") {
            return .danger
        }
        if v.contains("done") {
            return .success
        }
        return .warning
    }

    private func progressTone(_ ratio: Double) -> StatusTone {
        if ratio >= 1.0 {
            return .success
        }
        if ratio <= 0.0 {
            return .neutral
        }
        return .warning
    }

    private func assemblyTone(_ value: String) -> StatusTone {
        let v = value.lowercased()
        if v.contains("done") {
            return .success
        }
        if v.contains("pending") || v.contains("dirty") {
            return .warning
        }
        if v == "-" {
            return .neutral
        }
        return .danger
    }

    private func pathExists(_ path: String?) -> Bool {
        guard let path, !path.isEmpty else {
            return false
        }
        return FileManager.default.fileExists(atPath: path)
    }

    private func shotRootPath(for shot: ShotSummaryRow) -> String {
        let base = state.config.watch.outputDir.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            return shot.shotName
        }
        return (base as NSString).appendingPathComponent(shot.shotName)
    }

    private func dpxPath(for shot: ShotSummaryRow) -> String {
        (shotRootPath(for: shot) as NSString).appendingPathComponent("dpx")
    }

    private func frameJsonPath(for shot: ShotSummaryRow) -> String {
        (shotRootPath(for: shot) as NSString).appendingPathComponent("frame_json")
    }

    private func truthFramePath(for shot: ShotSummaryRow) -> String {
        (shotRootPath(for: shot) as NSString).appendingPathComponent("truth_frame")
    }

    private func manifestPath(for shot: ShotSummaryRow) -> String {
        (shotRootPath(for: shot) as NSString).appendingPathComponent("manifest.json")
    }

    private var selectedShot: ShotSummaryRow? {
        if let selectedShotName {
            if let matched = pagedShots.first(where: { $0.shotName == selectedShotName }) {
                return matched
            }
            if let matched = state.shotsSnapshot?.shots.first(where: { $0.shotName == selectedShotName }) {
                return matched
            }
        }
        return pagedShots.first
    }

    private func syncSelectedShot() {
        guard !filteredShots.isEmpty else {
            selectedShotName = nil
            return
        }
        if let selectedShotName, pagedShots.contains(where: { $0.shotName == selectedShotName }) {
            return
        }
        self.selectedShotName = pagedShots.first?.shotName
    }

    private var issuesCount: Int {
        state.shotsSnapshot?.shots.filter(isIssuesShot).count ?? 0
    }

    private var processingCount: Int {
        state.shotsSnapshot?.shots.filter(isProcessingShot).count ?? 0
    }

    private var filteredShots: [ShotSummaryRow] {
        guard let shots = state.shotsSnapshot?.shots else { return [] }
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var rows = shots.filter { shot in
            switch selectedFilter {
            case .all:
                break
            case .issues:
                if !isIssuesShot(shot) { return false }
            case .processing:
                if !isProcessingShot(shot) { return false }
            case .queued:
                if !isQueuedShot(shot) { return false }
            case .done:
                if !isDoneShot(shot) { return false }
            }

            if !term.isEmpty {
                let haystack = [
                    shot.shotName,
                    shot.state,
                    shot.assemblyState ?? "",
                    shot.lastUpdatedAt ?? "",
                    shot.outputMovPath ?? "",
                    shot.reviewMovPath ?? "",
                    "\(shot.totalFrames)",
                    "\(shot.doneFrames)",
                    "\(shot.failedFrames)",
                    "\(shot.inflightFrames)",
                ]
                    .joined(separator: " ")
                    .lowercased()
                if !haystack.contains(term) {
                    return false
                }
            }
            return true
        }

        switch selectedSort {
        case .updatedDesc:
            rows.sort { ($0.lastUpdatedAt ?? "") > ($1.lastUpdatedAt ?? "") }
        case .progressDesc:
            rows.sort {
                if $0.progressRatio == $1.progressRatio {
                    return $0.shotName.localizedCaseInsensitiveCompare($1.shotName) == .orderedAscending
                }
                return $0.progressRatio > $1.progressRatio
            }
        case .failedDesc:
            rows.sort {
                if $0.failedFrames == $1.failedFrames {
                    return ($0.lastUpdatedAt ?? "") > ($1.lastUpdatedAt ?? "")
                }
                return $0.failedFrames > $1.failedFrames
            }
        case .shotAsc:
            rows.sort { $0.shotName.localizedCaseInsensitiveCompare($1.shotName) == .orderedAscending }
        }

        return rows
    }

    private var safePageIndex: Int {
        guard !filteredShots.isEmpty else { return 0 }
        return min(max(0, pageIndex), pageCount - 1)
    }

    private var pageCount: Int {
        guard !filteredShots.isEmpty else { return 1 }
        return max(1, (filteredShots.count + pageSize - 1) / pageSize)
    }

    private var pagedShots: [ShotSummaryRow] {
        guard !filteredShots.isEmpty else { return [] }
        let start = safePageIndex * pageSize
        let end = min(filteredShots.count, start + pageSize)
        if start >= end {
            return []
        }
        return Array(filteredShots[start..<end])
    }

    private var pageRangeLabel: String {
        guard !pagedShots.isEmpty else { return "Rows 0-0" }
        let start = safePageIndex * pageSize + 1
        let end = start + pagedShots.count - 1
        return "Rows \(start)-\(end)"
    }

    private func clampPageIndex() {
        pageIndex = safePageIndex
    }

    private func isIssuesShot(_ shot: ShotSummaryRow) -> Bool {
        if shot.failedFrames > 0 {
            return true
        }
        let stateLower = shot.state.lowercased()
        if stateLower.contains("issue") || stateLower.contains("fail") {
            return true
        }
        let assemblyLower = (shot.assemblyState ?? "").lowercased()
        return assemblyLower.contains("fail")
    }

    private func isProcessingShot(_ shot: ShotSummaryRow) -> Bool {
        if shot.inflightFrames > 0 {
            return true
        }
        let stateLower = shot.state.lowercased()
        return stateLower.contains("process") || stateLower == "processing"
    }

    private func isDoneShot(_ shot: ShotSummaryRow) -> Bool {
        let stateLower = shot.state.lowercased()
        if stateLower == "done" {
            return true
        }
        return shot.totalFrames > 0 && (shot.doneFrames + shot.failedFrames) >= shot.totalFrames && shot.failedFrames == 0
    }

    private func isQueuedShot(_ shot: ShotSummaryRow) -> Bool {
        !isIssuesShot(shot) && !isProcessingShot(shot) && !isDoneShot(shot)
    }
}
