import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Setup")
                    .font(.title2)
                    .bold()

                GroupBox("Workspace") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Repo root", text: $state.repoRoot)
                            .textFieldStyle(.roundedBorder)
                        TextField("Config path", text: $state.configPath)
                            .textFieldStyle(.roundedBorder)
                        HStack(spacing: 10) {
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
                    .padding(.top, 6)
                }

                if let health = state.health {
                    GroupBox("Runtime Health") {
                        VStack(alignment: .leading, spacing: 8) {
                            kv("Python", health.pythonExecutable)
                            kv("Python Version", health.pythonVersion)
                            kv("Venv Python", health.venvPython)
                            kv("Venv Exists", health.venvPythonExists ? "yes" : "no")
                            kv("stopmo Version", health.stopmoVersion ?? "unknown")
                            if let ffmpeg = health.ffmpegPath {
                                kv("FFmpeg", ffmpeg)
                            } else {
                                kv("FFmpeg", "not found")
                            }
                            if let configLoadOk = health.configLoadOk {
                                kv("Config Load", configLoadOk ? "ok" : "failed")
                            }
                            if let configError = health.configError, !configError.isEmpty {
                                kv("Config Error", configError)
                            }
                        }
                        .padding(.top, 6)
                    }

                    GroupBox("Dependency Checks") {
                        let keys = health.checks.keys.sorted()
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(keys, id: \.self) { key in
                                HStack {
                                    Text(key)
                                    Spacer()
                                    let ok = health.checks[key] ?? false
                                    Text(ok ? "available" : "missing")
                                        .foregroundStyle(ok ? .green : .red)
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                }

                if let validation = state.configValidation {
                    GroupBox("Config Validation") {
                        VStack(alignment: .leading, spacing: 8) {
                            kv("Status", validation.ok ? "ok" : "failed")
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
                        .padding(.top, 6)
                    }
                }

                if let preflight = state.watchPreflight {
                    GroupBox("Watch Start Safety") {
                        VStack(alignment: .leading, spacing: 8) {
                            kv("Ready", preflight.ok ? "yes" : "no")
                            if !preflight.blockers.isEmpty {
                                kv("Blockers", preflight.blockers.joined(separator: ", "))
                            }
                            let checks = preflight.healthChecks.keys.sorted()
                            if !checks.isEmpty {
                                Text("Health Checks")
                                    .font(.subheadline)
                                ForEach(checks, id: \.self) { key in
                                    HStack {
                                        Text(key)
                                        Spacer()
                                        Text((preflight.healthChecks[key] ?? false) ? "ok" : "missing")
                                            .foregroundStyle((preflight.healthChecks[key] ?? false) ? .green : .red)
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                }
            }
            .padding(20)
        }
    }

    private func kv(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .frame(width: 140, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}
