import Foundation

/// Scope filters for the redesigned Review workspace.
enum ReviewScopeFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case issues = "Issues"
    case inflight = "Inflight"
    case ready = "Ready"

    var id: String { rawValue }
}

/// Section buckets used to group shots in the redesigned Review workspace.
enum ReviewWorkspaceSectionKind: String, CaseIterable, Identifiable {
    case issues = "Issues"
    case inflight = "Inflight"
    case ready = "Ready"
    case completed = "Delivered / Completed"

    var id: String { rawValue }
}

struct ReviewWorkspaceSection: Identifiable {
    let kind: ReviewWorkspaceSectionKind
    let evaluations: [ShotHealthEvaluation]

    var id: ReviewWorkspaceSectionKind { kind }
}

/// Pure grouping and selection helpers for the Review list-detail workspace.
enum ReviewWorkspaceReducer {
    static func groupedSections(
        snapshot: ShotsSummarySnapshot?,
        filter: ReviewScopeFilter,
        searchText: String
    ) -> [ReviewWorkspaceSection] {
        let filtered = ShotHealthModel.evaluate(snapshot: snapshot)
            .filter { evaluation in
                matchesFilter(evaluation, filter: filter) && matchesSearch(evaluation, searchText: searchText)
            }
            .sorted(by: compareEvaluations(_:_:))

        let groups = Dictionary(grouping: filtered, by: sectionKind(for:))
        return ReviewWorkspaceSectionKind.allCases.compactMap { kind in
            guard let evaluations = groups[kind], !evaluations.isEmpty else {
                return nil
            }
            return ReviewWorkspaceSection(kind: kind, evaluations: evaluations)
        }
    }

    static func resolvedSelection(
        currentSelection: String?,
        sections: [ReviewWorkspaceSection]
    ) -> String? {
        let flattened = sections.flatMap(\.evaluations)
        guard !flattened.isEmpty else {
            return nil
        }
        if let currentSelection, flattened.contains(where: { $0.shot.shotName == currentSelection }) {
            return currentSelection
        }
        for kind in ReviewWorkspaceSectionKind.allCases {
            if let first = sections.first(where: { $0.kind == kind })?.evaluations.first {
                return first.shot.shotName
            }
        }
        return flattened.first?.shot.shotName
    }

    static func selectedEvaluation(
        sections: [ReviewWorkspaceSection],
        selectedShotName: String?
    ) -> ShotHealthEvaluation? {
        guard let selectedShotName else {
            return nil
        }
        return sections
            .flatMap(\.evaluations)
            .first(where: { $0.shot.shotName == selectedShotName })
    }

    private static func sectionKind(for evaluation: ShotHealthEvaluation) -> ReviewWorkspaceSectionKind {
        switch evaluation.healthState {
        case .issues:
            return .issues
        case .inflight, .queued:
            return .inflight
        case .clean:
            if (evaluation.shot.outputMovPath?.isEmpty == false) || (evaluation.shot.reviewMovPath?.isEmpty == false) {
                return .completed
            }
            return .ready
        }
    }

    private static func matchesFilter(_ evaluation: ShotHealthEvaluation, filter: ReviewScopeFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .issues:
            return evaluation.healthState == .issues
        case .inflight:
            return evaluation.healthState == .inflight || evaluation.healthState == .queued
        case .ready:
            return evaluation.isDeliverable
        }
    }

    private static func matchesSearch(_ evaluation: ShotHealthEvaluation, searchText: String) -> Bool {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return true
        }
        let haystacks = [
            evaluation.shot.shotName,
            evaluation.shot.state,
            evaluation.issueSummary,
            evaluation.shot.assemblyState ?? "",
            evaluation.shot.outputMovPath ?? "",
            evaluation.shot.reviewMovPath ?? "",
        ]
        return haystacks.joined(separator: " ").localizedCaseInsensitiveContains(trimmed)
    }

    private static func compareEvaluations(_ lhs: ShotHealthEvaluation, _ rhs: ShotHealthEvaluation) -> Bool {
        let left = lhs.shot.lastUpdatedAt ?? ""
        let right = rhs.shot.lastUpdatedAt ?? ""
        if left == right {
            return lhs.shot.shotName.localizedCaseInsensitiveCompare(rhs.shot.shotName) == .orderedAscending
        }
        return left > right
    }
}
