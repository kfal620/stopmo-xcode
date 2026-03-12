import SwiftUI

/// Shot-selection pane for day-wrap delivery, including readiness state and preview access.
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
    let baseOutputDir: String

    let onSelectAllReady: () -> Void
    let onSelectNone: () -> Void
    let onRunSelected: () -> Void
    let onToggleSelection: (String) -> Void
    let onRunShot: (ShotSummaryRow) -> Void
    let onOpenShotFolder: (ShotSummaryRow) -> Void
    let onOpenPath: (String) -> Void
    let onShowPreview: (ShotSummaryRow, ShotPreviewKind, String) -> Void

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
            subtitle: "Ready-to-ship shots first, blocked shots second.",
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
                HStack(alignment: .top, spacing: DeliveryLayoutMetrics.shotRowActionSpacing) {
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

                    ShotThumbnailView(
                        shot: shot,
                        preferredKind: .first,
                        baseOutputDir: baseOutputDir,
                        width: 52,
                        height: 32,
                        cornerRadius: 6,
                        onOpenLightbox: { previewPath in
                            onShowPreview(shot, .first, previewPath)
                        }
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(shot.shotName)
                            .appTextRole(.primaryMeta)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(shot.shotName)
                        Text(evaluation.issueSummary)
                            .metadataTextStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    StatusChip(label: evaluation.healthState.rawValue, tone: evaluation.healthState.tone, density: .compact)
                }

                ProgressView(value: progressRatio(for: shot))
                    .tint(progressTint(for: evaluation.healthState))

                SummaryFactStrip(
                    facts: [
                        SummaryFact(id: "\(shot.id)-completion", label: "Completion", value: evaluation.completionLabel, tone: .success),
                        SummaryFact(id: "\(shot.id)-updated", label: "Updated", value: ShotHealthModel.updatedDisplayLabel(for: shot).replacingOccurrences(of: "Updated ", with: ""), tone: .neutral),
                    ],
                    minItemWidth: 110,
                    compact: true
                )

                HStack(spacing: DeliveryLayoutMetrics.shotRowActionSpacing) {
                    Button(isRunningShot ? "Delivering..." : "Deliver ProRes") {
                        onRunShot(shot)
                    }
                    .buttonStyle(.borderedProminent)
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
                            ShotThumbnailView(
                                shot: evaluation.shot,
                                preferredKind: .first,
                                baseOutputDir: baseOutputDir,
                                width: 44,
                                height: 28,
                                cornerRadius: 6,
                                onOpenLightbox: { previewPath in
                                    onShowPreview(evaluation.shot, .first, previewPath)
                                }
                            )
                            Text(evaluation.shot.shotName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(width: DeliveryLayoutMetrics.shotNameColumnWidth, alignment: .leading)
                                .help(evaluation.shot.shotName)
                            StatusChip(label: evaluation.healthState.rawValue, tone: evaluation.healthState.tone, density: .compact)
                            Text(evaluation.issueSummary)
                                .metadataTextStyle(.secondary)
                                .lineLimit(1)
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

/// Ready-shot list used when operators need to launch delivery from explicit shot selections.
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
            SummaryFactStrip(
                facts: [
                    SummaryFact(id: "ready", label: "Ready", value: "\(readyCount)", tone: .success),
                    SummaryFact(id: "selected", label: "Selected", value: "\(selectedCount)", tone: selectedCount > 0 ? .warning : .neutral),
                    SummaryFact(id: "blocked", label: "Blocked", value: "\(notReadyCount)", tone: notReadyCount > 0 ? .warning : .neutral),
                    SummaryFact(id: "root", label: "Root", value: dpxRootReady ? "Ready" : "Missing", tone: dpxRootReady ? .success : .danger),
                ],
                minItemWidth: 88,
                compact: true
            )

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
                        .buttonStyle(.bordered)
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
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!canRunBulk)
                }
            }

            rows
        }
    }
}
