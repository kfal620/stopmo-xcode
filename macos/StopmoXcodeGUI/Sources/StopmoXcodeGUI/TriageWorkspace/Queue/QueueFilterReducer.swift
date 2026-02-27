import Foundation

enum QueueStateFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case failed = "Failed"
    case inflight = "Inflight"
    case detected = "Detected"
    case done = "Done"

    var id: String { rawValue }
}

enum QueueSortOption: String, CaseIterable, Identifiable {
    case updatedDesc = "Updated (Newest)"
    case attemptsDesc = "Attempts (Highest)"
    case shotAsc = "Shot (A-Z)"
    case stateAsc = "State (A-Z)"
    case idDesc = "ID (Newest)"

    var id: String { rawValue }
}

struct QueuePaginationResult: Equatable {
    let safePageIndex: Int
    let pageCount: Int
    let pageRangeLabel: String
}

enum QueueFilterReducer {
    static func filteredJobs(
        jobs: [QueueJobRecord],
        searchText: String,
        stateFilter: QueueStateFilter,
        sort: QueueSortOption,
        showOnlySelected: Bool,
        selectedJobIDs: Set<Int>
    ) -> [QueueJobRecord] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var rows = jobs.filter { job in
            if showOnlySelected, !selectedJobIDs.contains(job.id) {
                return false
            }

            let stateValue = job.state.lowercased()
            switch stateFilter {
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

        switch sort {
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

    static func paginate(
        filteredCount: Int,
        pageSize: Int,
        pageIndex: Int
    ) -> QueuePaginationResult {
        guard filteredCount > 0 else {
            return QueuePaginationResult(
                safePageIndex: 0,
                pageCount: 1,
                pageRangeLabel: "Rows 0-0"
            )
        }

        let count = max(1, (filteredCount + pageSize - 1) / pageSize)
        let safe = min(max(0, pageIndex), count - 1)
        let start = safe * pageSize + 1
        let end = min(filteredCount, start + pageSize - 1)
        return QueuePaginationResult(
            safePageIndex: safe,
            pageCount: count,
            pageRangeLabel: "Rows \(start)-\(end)"
        )
    }
}
