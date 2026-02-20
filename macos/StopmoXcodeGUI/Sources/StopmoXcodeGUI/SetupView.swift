import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.lg) {
                ScreenHeader(
                    title: "Setup",
                    subtitle: "Workspace access, runtime checks, and startup safety."
                )

                SectionCard("Workspace", subtitle: "Select repo/config paths and run setup checks.") {
                    LabeledPathField(
                        label: "Repo Root",
                        placeholder: "Repo root",
                        text: $state.repoRoot,
                        icon: "folder",
                        browseHelp: "Browse for repo root",
                        isDisabled: state.isBusy
                    ) {
                        state.chooseRepoRootDirectory()
                    }

                    LabeledPathField(
                        label: "Config Path",
                        placeholder: "Config path",
                        text: $state.configPath,
                        icon: "doc",
                        browseHelp: "Browse for config file",
                        isDisabled: state.isBusy
                    ) {
                        state.chooseConfigFile()
                    }

                    actionRows

                    HStack {
                        Text("Workspace Access")
                            .foregroundStyle(.secondary)
                        Spacer()
                        StatusChip(
                            label: state.workspaceAccessActive ? "Granted" : "Not Granted",
                            tone: state.workspaceAccessActive ? .success : .warning
                        )
                    }
                }

                if let health = state.health {
                    SectionCard("Runtime Health") {
                        KeyValueRow(key: "Python", value: health.pythonExecutable)
                        KeyValueRow(key: "Python Version", value: health.pythonVersion)
                        KeyValueRow(key: "Venv Python", value: health.venvPython)
                        KeyValueRow(
                            key: "Venv Exists",
                            value: health.venvPythonExists ? "yes" : "no",
                            tone: health.venvPythonExists ? .success : .danger
                        )
                        KeyValueRow(key: "stopmo Version", value: health.stopmoVersion ?? "unknown")
                        KeyValueRow(
                            key: "FFmpeg",
                            value: health.ffmpegPath ?? "not found",
                            tone: health.ffmpegPath == nil ? .warning : .success
                        )
                        if let configLoadOk = health.configLoadOk {
                            KeyValueRow(
                                key: "Config Load",
                                value: configLoadOk ? "ok" : "failed",
                                tone: configLoadOk ? .success : .danger
                            )
                        }
                        if let configError = health.configError, !configError.isEmpty {
                            KeyValueRow(key: "Config Error", value: configError, tone: .danger)
                        }
                    }

                    SectionCard("Dependency Checks") {
                        let keys = health.checks.keys.sorted()
                        ForEach(keys, id: \.self) { key in
                            HStack {
                                Text(key)
                                Spacer()
                                let ok = health.checks[key] ?? false
                                StatusChip(label: ok ? "Available" : "Missing", tone: ok ? .success : .danger)
                            }
                            .font(.callout)
                        }
                    }
                } else {
                    EmptyStateCard(message: "Runtime health not loaded yet. Click Check Runtime Health.")
                }

                if let validation = state.configValidation {
                    SectionCard("Config Validation") {
                        HStack {
                            Text("Status")
                                .foregroundStyle(.secondary)
                            Spacer()
                            StatusChip(
                                label: validation.ok ? "OK" : "Failed",
                                tone: validation.ok ? .success : .danger
                            )
                        }
                        if !validation.errors.isEmpty {
                            Text("Errors")
                                .font(.subheadline)
                            ForEach(validation.errors) { item in
                                Text("[\(item.field)] \(item.message)")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        if !validation.warnings.isEmpty {
                            Text("Warnings")
                                .font(.subheadline)
                            ForEach(validation.warnings) { item in
                                Text("[\(item.field)] \(item.message)")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                if let preflight = state.watchPreflight {
                    SectionCard("Watch Start Safety") {
                        HStack {
                            Text("Ready")
                                .foregroundStyle(.secondary)
                            Spacer()
                            StatusChip(
                                label: preflight.ok ? "Yes" : "No",
                                tone: preflight.ok ? .success : .danger
                            )
                        }
                        if !preflight.blockers.isEmpty {
                            KeyValueRow(
                                key: "Blockers",
                                value: preflight.blockers.joined(separator: ", "),
                                tone: .danger
                            )
                        }
                        let checks = preflight.healthChecks.keys.sorted()
                        if !checks.isEmpty {
                            Text("Health Checks")
                                .font(.subheadline)
                            ForEach(checks, id: \.self) { key in
                                HStack {
                                    Text(key)
                                    Spacer()
                                    let ok = preflight.healthChecks[key] ?? false
                                    StatusChip(label: ok ? "OK" : "Missing", tone: ok ? .success : .danger)
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
            }
            .padding(StopmoUI.Spacing.lg)
        }
    }

    @ViewBuilder
    private var actionRows: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: StopmoUI.Spacing.sm) {
                workspaceActionButtons
            }
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                HStack(spacing: StopmoUI.Spacing.sm) {
                    Button("Choose Workspace…") {
                        state.chooseWorkspaceDirectory()
                    }
                    .disabled(state.isBusy)

                    Button("Check Runtime Health") {
                        Task { await state.refreshHealth() }
                    }
                    .disabled(state.isBusy)

                    Button("Load Config") {
                        Task { await state.loadConfig() }
                    }
                    .disabled(state.isBusy)
                }
                HStack(spacing: StopmoUI.Spacing.sm) {
                    Button("Save Config") {
                        Task { await state.saveConfig() }
                    }
                    .disabled(state.isBusy)

                    Button("Validate Config") {
                        Task { await state.validateConfig() }
                    }
                    .disabled(state.isBusy)

                    Button("Watch Preflight") {
                        Task { await state.refreshWatchPreflight() }
                    }
                    .disabled(state.isBusy)
                }
            }
        }
    }

    private var workspaceActionButtons: some View {
        Group {
            Button("Choose Workspace…") {
                state.chooseWorkspaceDirectory()
            }
            .disabled(state.isBusy)

            Button("Check Runtime Health") {
                Task { await state.refreshHealth() }
            }
            .disabled(state.isBusy)

            Button("Load Config") {
                Task { await state.loadConfig() }
            }
            .disabled(state.isBusy)

            Button("Save Config") {
                Task { await state.saveConfig() }
            }
            .disabled(state.isBusy)

            Button("Validate Config") {
                Task { await state.validateConfig() }
            }
            .disabled(state.isBusy)

            Button("Watch Preflight") {
                Task { await state.refreshWatchPreflight() }
            }
            .disabled(state.isBusy)
        }
    }
}
