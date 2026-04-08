import SwiftUI

/// Modal wizard for creating a new FrameRelay project in a user-chosen location.
struct NewProjectWizardView: View {
    @EnvironmentObject private var state: AppState

    private var validationMessage: String? {
        state.newProjectDraft.validationMessage()
    }

    private var isCreateDisabled: Bool {
        state.isBusy || validationMessage != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.lg) {
            ScreenHeader(
                title: "New Project",
                subtitle: "Create a ready-to-run FrameRelay project with folders, config, and queue database."
            )

            SectionCard("Project Details", subtitle: "Choose a project name and destination parent folder.") {
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                    VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                        Text("Project Name")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Project name", text: $state.newProjectDraft.projectName)
                            .textFieldStyle(.roundedBorder)
                    }

                    LabeledPathField(
                        label: "Destination Folder",
                        placeholder: "Destination folder",
                        text: $state.newProjectDraft.parentDirectory,
                        icon: "folder",
                        browseHelp: "Choose destination folder",
                        isDisabled: state.isBusy
                    ) {
                        state.chooseNewProjectParentDirectory()
                    }

                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    } else if state.newProjectDraft.usesExistingEmptyDirectory {
                        Label("An existing empty folder will be used for this project.", systemImage: "folder.badge.plus")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("A new project folder will be created at the preview path below.", systemImage: "checkmark.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SectionCard("Preview", subtitle: "These paths will be created and wired into the default config.") {
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                    KeyValueRow(
                        key: "Project Root",
                        value: state.newProjectDraft.projectRootPreview.isEmpty ? "Pending…" : state.newProjectDraft.projectRootPreview
                    )
                    KeyValueRow(
                        key: "Config Path",
                        value: state.newProjectDraft.configPathPreview.isEmpty ? "Pending…" : state.newProjectDraft.configPathPreview
                    )
                    KeyValueRow(key: "Folders", value: "incoming, work, output, config")
                    KeyValueRow(key: "Database", value: "work/queue.sqlite3")
                }
            }

            HStack(spacing: StopmoUI.Spacing.sm) {
                StatusChip(
                    label: isCreateDisabled ? "Needs Attention" : "Ready",
                    tone: isCreateDisabled ? .warning : .success
                )
                Spacer(minLength: 0)
                Button("Cancel") {
                    state.dismissNewProjectWizard()
                }
                .disabled(state.isBusy)

                Button("Create Project") {
                    Task { await state.createNewProject() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isCreateDisabled)
            }
        }
        .padding(StopmoUI.Spacing.lg)
        .frame(minWidth: 720, idealWidth: 760)
        .interactiveDismissDisabled(state.isBusy)
    }
}
