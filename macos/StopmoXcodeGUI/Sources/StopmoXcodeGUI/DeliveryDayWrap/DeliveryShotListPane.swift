import SwiftUI

/// Data/view model for delivery shot list pane.
struct DeliveryShotListPane: View {
    let readyShotEvaluations: [ShotHealthEvaluation]
    let notReadyShotEvaluations: [ShotHealthEvaluation]
    @Binding var selectedShotNames: Set<String>
    @Binding var showNotReadyShots: Bool

    let isBusy: Bool
    let dpxRootReady: Bool
    let isRunningDelivery: Bool
    let activeRunLabel: String
    let availableHeight: CGFloat

    let onSelectAllReady: () -> Void
    let onSelectNone: () -> Void
    let onRunSelected: () -> Void
    let onToggleSelection: (String) -> Void
    let onRunShot: (ShotSummaryRow) -> Void
    let onOpenShotFolder: (ShotSummaryRow) -> Void
    let onOpenPath: (String) -> Void

    private var selectedReadyCount: Int {
        readyShotEvaluations.filter { selectedShotNames.contains($0.shot.shotName) }.count
    }

    private var canRunBulk: Bool {
        !isBusy && dpxRootReady && selectedReadyCount > 0
    }

    private var shotListMaxHeight: CGFloat {
        max(240, availableHeight - DeliveryLayoutMetrics.shotListBaseMaxOffset)
    }

    var body: some View {
        SectionCard(
            "Deliverable Shots",
            subtitle: "Select completed shots and deliver ProRes in one run.",
            density: .compact,
            surfaceLevel: .panel,
            chrome: .quiet,
            showSubtitle: false
        ) {
            DeliverableShotsPane(
                readyCount: readyShotEvaluations.count,
                selectedCount: selectedReadyCount,
                notReadyCount: notReadyShotEvaluations.count,
                canRunBulk: canRunBulk,
                isBusy: isBusy,
                dpxRootReady: dpxRootReady,
                selectAllAction: onSelectAllReady,
                selectNoneAction: onSelectNone,
                runSelectedAction: onRunSelected
            ) {
                if readyShotEvaluations.isEmpty {
                    EmptyStateCard(message: "No shots are ready for delivery yet.")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                            ForEach(readyShotEvaluations) { evaluation in
                                shotRow(evaluation)
                            }
                        }
                        .padding(.horizontal, 2)
                        .padding(.vertical, 2)
                    }
                    .frame(minHeight: DeliveryLayoutMetrics.shotListMinHeight, maxHeight: shotListMaxHeight)
                }
            }

            notReadyDisclosure
        }
    }

    private func shotRow(_ evaluation: ShotHealthEvaluation) -> some View {
        let shot = evaluation.shot
        let isSelected = selectedShotNames.contains(shot.shotName)
        let isRunningShot = isRunningDelivery && activeRunLabel.localizedCaseInsensitiveContains(shot.shotName)

        return SurfaceContainer(level: .card, chrome: .quiet, cornerRadius: DenseShotRowStyle.cornerRadius) {
            VStack(alignment: .leading, spacing: DeliveryLayoutMetrics.shotRowSpacing) {
                HStack(alignment: .center, spacing: DeliveryLayoutMetrics.shotRowActionSpacing) {
                    Button {
                        onToggleSelection(shot.shotName)
                    } label: {
                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 14, height: 14)
                            .foregroundStyle(isSelected ? LifecycleHub.deliver.accentColor : AppVisualTokens.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help(isSelected ? "Unselect shot" : "Select shot")

                    Text(shot.shotName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: DeliveryLayoutMetrics.shotNameColumnWidth, alignment: .leading)
                        .help(shot.shotName)

                    StatusChip(label: evaluation.healthState.rawValue, tone: evaluation.healthState.tone, density: .compact)
                    StatusChip(label: evaluation.completionLabel, tone: .success, density: .compact)
                    Text(ShotHealthModel.updatedDisplayLabel(for: shot))
                        .metadataTextStyle(.tertiary)
                        .help(shot.lastUpdatedAt ?? "No update timestamp")

                    Spacer(minLength: 0)
                }

                ProgressView(value: progressRatio(for: shot))
                    .tint(progressTint(for: evaluation.healthState))

                HStack(spacing: DeliveryLayoutMetrics.shotRowActionSpacing) {
                    Button(isRunningShot ? "Delivering..." : "Deliver ProRes") {
                        onRunShot(shot)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(isBusy || !dpxRootReady || isRunningShot)

                    Menu("More") {
                        Button("Open Shot Folder") {
                            onOpenShotFolder(shot)
                        }
                        if let output = shot.outputMovPath, !output.isEmpty {
                            Button("Open Output MOV") {
                                onOpenPath(output)
                            }
                        }
                        if let review = shot.reviewMovPath, !review.isEmpty {
                            Button("Open Review MOV") {
                                onOpenPath(review)
                            }
                        }
                    }
                    .controlSize(.mini)
                }
            }
            .padding(.horizontal, DeliveryLayoutMetrics.shotRowHorizontalPadding)
            .padding(.vertical, DeliveryLayoutMetrics.shotRowVerticalPadding)
        }
    }

    private var notReadyDisclosure: some View {
        DisclosureGroup(isExpanded: $showNotReadyShots) {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                if notReadyShotEvaluations.isEmpty {
                    EmptyStateCard(message: "All shots are currently deliverable.")
                } else {
                    ForEach(notReadyShotEvaluations) { evaluation in
                        HStack(alignment: .center, spacing: DeliveryLayoutMetrics.shotRowActionSpacing) {
                            Text(evaluation.shot.shotName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(width: DeliveryLayoutMetrics.shotNameColumnWidth, alignment: .leading)
                                .help(evaluation.shot.shotName)
                            StatusChip(label: evaluation.healthState.rawValue, tone: evaluation.healthState.tone, density: .compact)
                            StatusChip(label: evaluation.readinessReason ?? "not ready", tone: .warning, density: .compact)
                            Spacer(minLength: 0)
                            Text(ShotHealthModel.updatedDisplayLabel(for: evaluation.shot))
                                .metadataTextStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(.top, StopmoUI.Spacing.xs)
        } label: {
            DisclosureRowLabel(title: "Not Ready (\(notReadyShotEvaluations.count))", isExpanded: $showNotReadyShots)
        }
        .padding(.top, StopmoUI.Spacing.xs)
    }

    private func progressRatio(for shot: ShotSummaryRow) -> Double {
        guard shot.totalFrames > 0 else {
            return 0
        }
        return min(1.0, max(0.0, Double(shot.doneFrames) / Double(shot.totalFrames)))
    }

    private func progressTint(for state: ShotHealthState) -> Color {
        switch state {
        case .clean:
            return Color.green.opacity(0.7)
        case .issues:
            return Color.red.opacity(0.85)
        case .inflight:
            return Color.orange.opacity(0.8)
        case .queued:
            return Color.white.opacity(0.35)
        }
    }
}

/// Data/view model for deliverable shots pane.
private struct DeliverableShotsPane<Rows: View>: View {
    let readyCount: Int
    let selectedCount: Int
    let notReadyCount: Int
    let canRunBulk: Bool
    let isBusy: Bool
    let dpxRootReady: Bool
    let selectAllAction: () -> Void
    let selectNoneAction: () -> Void
    let runSelectedAction: () -> Void
    @ViewBuilder let rows: Rows

    init(
        readyCount: Int,
        selectedCount: Int,
        notReadyCount: Int,
        canRunBulk: Bool,
        isBusy: Bool,
        dpxRootReady: Bool,
        selectAllAction: @escaping () -> Void,
        selectNoneAction: @escaping () -> Void,
        runSelectedAction: @escaping () -> Void,
        @ViewBuilder rows: () -> Rows
    ) {
        self.readyCount = readyCount
        self.selectedCount = selectedCount
        self.notReadyCount = notReadyCount
        self.canRunBulk = canRunBulk
        self.isBusy = isBusy
        self.dpxRootReady = dpxRootReady
        self.selectAllAction = selectAllAction
        self.selectNoneAction = selectNoneAction
        self.runSelectedAction = runSelectedAction
        self.rows = rows()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
            HStack(spacing: StopmoUI.Spacing.xs) {
                StatusChip(label: "Ready \(readyCount)", tone: .success, density: .compact)
                StatusChip(label: "Selected \(selectedCount)", tone: selectedCount > 0 ? .warning : .neutral, density: .compact)
                StatusChip(label: "Not Ready \(notReadyCount)", tone: notReadyCount > 0 ? .warning : .neutral, density: .compact)
                StatusChip(label: dpxRootReady ? "Root Ready" : "Root Missing", tone: dpxRootReady ? .success : .danger, density: .compact)
                Spacer(minLength: 0)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    Button("Select All Ready", action: selectAllAction)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isBusy || readyCount == 0)
                    Button("Select None", action: selectNoneAction)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isBusy || selectedCount == 0)
                    Spacer(minLength: 0)
                    Button("Deliver Selected", action: runSelectedAction)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!canRunBulk)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Button("Select All Ready", action: selectAllAction)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(isBusy || readyCount == 0)
                        Button("Select None", action: selectNoneAction)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(isBusy || selectedCount == 0)
                    }
                    Button("Deliver Selected", action: runSelectedAction)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!canRunBulk)
                }
            }

            rows
        }
    }
}
