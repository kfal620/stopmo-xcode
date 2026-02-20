import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var state: AppState
    var embedded: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.lg) {
                if !embedded {
                    ScreenHeader(
                        title: "Setup",
                        subtitle: "Workspace permissions, runtime readiness, and config bootstrapping."
                    )
                }

                pathsCard
                permissionsCard
                runtimeHealthCard
                dependencyChecksCard
                configValidationCard
                watchSafetyCard
            }
            .padding(embedded ? StopmoUI.Spacing.md : StopmoUI.Spacing.lg)
        }
    }

    private var pathsCard: some View {
        SectionCard("Paths", subtitle: "Set repo/config locations and bootstrap from sample config.") {
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

            ViewThatFits(in: .horizontal) {
                HStack(spacing: StopmoUI.Spacing.sm) {
                    pathsActions
                }
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                    Button("Use Sample Config Path") {
                        state.useSampleConfig()
                    }
                    .disabled(state.isBusy)

                    Button("Create Config From Sample") {
                        state.createConfigFromSample()
                    }
                    .disabled(state.isBusy)

                    Button("Open Config In Finder") {
                        state.openConfigInFinder()
                    }
                    .disabled(state.isBusy)
                }
            }

            HStack {
                Text("Sample Config")
                    .foregroundStyle(.secondary)
                Spacer()
                StatusChip(label: sampleConfigExists ? "Found" : "Missing", tone: sampleConfigExists ? .success : .danger)
            }
            Text(state.sampleConfigPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var permissionsCard: some View {
        SectionCard("Permissions", subtitle: "Grant workspace access once to avoid repeated folder prompts.") {
            HStack {
                Text("Workspace Access")
                    .foregroundStyle(.secondary)
                Spacer()
                StatusChip(
                    label: state.workspaceAccessActive ? "Granted" : "Not Granted",
                    tone: state.workspaceAccessActive ? .success : .warning
                )
            }
            Text("Use a single workspace root and keep source/work/output under it for stable permissions.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Grant Workspace Access…") {
                state.chooseWorkspaceDirectory()
            }
            .disabled(state.isBusy)
        }
    }

    private var runtimeHealthCard: some View {
        SectionCard("Runtime Health", subtitle: "Verify Python runtime and bridge prerequisites.") {
            Button("Check Runtime Health") {
                Task { await state.refreshHealth() }
            }
            .disabled(state.isBusy)

            if let health = state.health {
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
            } else {
                EmptyStateCard(message: "Runtime health not loaded yet.")
            }
        }
    }

    private var dependencyChecksCard: some View {
        SectionCard("Dependency Checks", subtitle: "Status, details, and remediation hints per dependency.") {
            if state.health != nil {
                if dependencyRows.isEmpty {
                    EmptyStateCard(message: "No dependency checks available in this runtime report.")
                } else {
                    VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                        HStack(spacing: StopmoUI.Spacing.sm) {
                            tableHeading("Dependency", width: 140)
                            tableHeading("Status", width: 100)
                            tableHeading("Detail", width: 220)
                            tableHeading("Fix Hint", width: nil)
                        }
                        ForEach(dependencyRows, id: \.name) { row in
                            HStack(alignment: .firstTextBaseline, spacing: StopmoUI.Spacing.sm) {
                                tableCell(row.name, width: 140)
                                StatusChip(label: row.ok ? "Available" : "Missing", tone: row.ok ? .success : .danger)
                                    .frame(width: 100, alignment: .leading)
                                tableCell(row.detail, width: 220)
                                tableCell(row.fixHint, width: nil)
                            }
                            .font(.caption)
                        }
                    }
                }
            } else {
                EmptyStateCard(message: "Run Check Runtime Health to populate dependency checks.")
            }
        }
    }

    private var configValidationCard: some View {
        SectionCard("Config Validation", subtitle: "Schema and value checks for current config file.") {
            HStack(spacing: StopmoUI.Spacing.sm) {
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
            }

            if let validation = state.configValidation {
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
            } else {
                EmptyStateCard(message: "No validation report yet.")
            }
        }
    }

    private var watchSafetyCard: some View {
        SectionCard("Watch Start Safety", subtitle: "Preflight check before launching watch service.") {
            Button("Run Watch Preflight") {
                Task { await state.refreshWatchPreflight() }
            }
            .disabled(state.isBusy)

            if let preflight = state.watchPreflight {
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
            } else {
                EmptyStateCard(message: "No preflight report yet.")
            }
        }
    }

    private var sampleConfigExists: Bool {
        FileManager.default.fileExists(atPath: state.sampleConfigPath)
    }

    private var pathsActions: some View {
        Group {
            Button("Use Sample Config Path") {
                state.useSampleConfig()
            }
            .disabled(state.isBusy)

            Button("Create Config From Sample") {
                state.createConfigFromSample()
            }
            .disabled(state.isBusy)

            Button("Open Config In Finder") {
                state.openConfigInFinder()
            }
            .disabled(state.isBusy)
        }
    }

    private var dependencyRows: [DependencyRow] {
        guard let health = state.health else { return [] }
        let keys = health.checks.keys.sorted()
        var rows = keys.map { key in
            let ok = health.checks[key] ?? false
            return DependencyRow(
                name: key,
                ok: ok,
                detail: ok ? "Import OK" : "Import failed",
                fixHint: dependencyFixHint(for: key)
            )
        }
        let hasFfmpeg = keys.contains { $0.lowercased() == "ffmpeg" }
        if !hasFfmpeg {
            rows.append(
                DependencyRow(
                    name: "ffmpeg",
                    ok: health.ffmpegPath != nil,
                    detail: health.ffmpegPath ?? "Not in PATH",
                    fixHint: dependencyFixHint(for: "ffmpeg")
                )
            )
        }
        return rows.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private func dependencyFixHint(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("rawpy") {
            return "Install extras: `.venv/bin/pip install -e \".[raw]\"`."
        }
        if lower.contains("opencolorio") || lower.contains("ocio") {
            return "Install extras: `.venv/bin/pip install -e \".[ocio]\"`."
        }
        if lower.contains("tifffile") {
            return "Install extras: `.venv/bin/pip install -e \".[io]\"`."
        }
        if lower.contains("ffmpeg") {
            return "Install FFmpeg and ensure it is available in PATH."
        }
        if lower.contains("exiftool") {
            return "Install ExifTool and rerun runtime health."
        }
        return "Install the missing dependency in `.venv`, then rerun health check."
    }

    private func tableHeading(_ text: String, width: CGFloat?) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .leading)
    }

    private func tableCell(_ text: String, width: CGFloat?) -> some View {
        Text(text)
            .lineLimit(2)
            .truncationMode(.tail)
            .frame(width: width, alignment: .leading)
            .textSelection(.enabled)
    }
}

private struct DependencyRow {
    let name: String
    let ok: Bool
    let detail: String
    let fixHint: String
}
