import Foundation

/// Result payload for workspace bootstrap result.
struct WorkspaceBootstrapResult: Equatable {
    let resolvedConfigPath: String
    let createdConfig: Bool
}

/// Protocol defining workspace config servicing behavior.
protocol WorkspaceConfigServicing {
    func defaultConfigPath(forWorkspaceRoot root: String) -> String
    func resolveInitialRepoRoot(
        environment: [String: String],
        rememberedRepoRoot: String?,
        bundlePath: String?,
        currentDirectoryPath: String
    ) -> String
    func discoverRepoRootNear(path: String) -> String?
    func isLikelyRepoRoot(path: String) -> Bool
    func bundledSampleConfigPath(bundleResourceURL: URL?, bundleURL: URL) -> String?
    func resolvedSampleConfigSourcePath(
        repoRoot: String,
        environment: [String: String],
        currentDirectoryPath: String,
        bundleSamplePath: String?
    ) -> String?
    func writeDefaultConfigTemplate(destination: String, workspaceRoot: String) throws
    func bootstrapWorkspaceIfNeeded(workspaceRoot: String, configPath: String) throws -> WorkspaceBootstrapResult
}

/// Service type for live workspace config service.
struct LiveWorkspaceConfigService: WorkspaceConfigServicing {
    private static let defaultWorkspaceFolderName = "StopmoXcodeWorkspace"

    func defaultConfigPath(forWorkspaceRoot root: String) -> String {
        "\(root)/config/sample.yaml"
    }

    func resolveInitialRepoRoot(
        environment: [String: String],
        rememberedRepoRoot: String?,
        bundlePath: String?,
        currentDirectoryPath: String
    ) -> String {
        if let workspaceRoot = environment["FRAMERELAY_WORKSPACE_ROOT"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !workspaceRoot.isEmpty {
            return workspaceRoot
        }
        if let workspaceRoot = environment["STOPMO_XCODE_WORKSPACE_ROOT"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !workspaceRoot.isEmpty {
            return workspaceRoot
        }
        for key in ["FRAMERELAY_ROOT", "STOPMO_XCODE_ROOT", "SRCROOT", "PROJECT_DIR"] {
            let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value, !value.isEmpty {
                if let resolved = resolveCandidateRoot(value) {
                    return resolved
                }
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: value, isDirectory: &isDir), isDir.boolValue {
                    return value
                }
            }
        }
        if let remembered = rememberedRepoRoot {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: remembered, isDirectory: &isDir), isDir.boolValue {
                return remembered
            }
        }
        if let bundlePath, let fromBundle = discoverRepoRootNear(path: bundlePath) {
            return fromBundle
        }
        if let fromCwd = discoverRepoRootNear(path: currentDirectoryPath) {
            return fromCwd
        }
        return defaultWorkspaceRoot()
    }

    func discoverRepoRootNear(path: String) -> String? {
        var url = URL(fileURLWithPath: path).standardizedFileURL
        if !url.hasDirectoryPath {
            url.deleteLastPathComponent()
        }
        for _ in 0..<10 {
            let candidate = url.path
            if isLikelyRepoRoot(path: candidate) {
                return candidate
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path {
                break
            }
            url = parent
        }
        return nil
    }

    func isLikelyRepoRoot(path root: String) -> Bool {
        let fm = FileManager.default
        let pyproject = (root as NSString).appendingPathComponent("pyproject.toml")
        let moduleDir = (root as NSString).appendingPathComponent("src/stopmo_xcode")
        return fm.fileExists(atPath: pyproject) && fm.fileExists(atPath: moduleDir)
    }

    func bundledSampleConfigPath(bundleResourceURL: URL?, bundleURL: URL) -> String? {
        var candidates: [String] = []
        if let resourcePath = bundleResourceURL?.appendingPathComponent("backend/defaults/sample.yaml").path {
            candidates.append(resourcePath)
        }
        candidates.append(bundleURL.appendingPathComponent("Contents/Resources/backend/defaults/sample.yaml").path)
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }
        return nil
    }

    func resolvedSampleConfigSourcePath(
        repoRoot: String,
        environment: [String: String],
        currentDirectoryPath: String,
        bundleSamplePath: String?
    ) -> String? {
        let envRepo = environment["FRAMERELAY_ROOT"] ?? environment["STOPMO_XCODE_ROOT"] ?? ""
        var candidates: [String] = [
            "\(repoRoot)/config/sample.yaml",
            "\(envRepo)/config/sample.yaml",
        ]
        if let bundleSamplePath {
            candidates.append(bundleSamplePath)
        }
        if let discovered = discoverRepoRootNear(path: currentDirectoryPath) {
            candidates.append("\(discovered)/config/sample.yaml")
        }
        for candidate in candidates.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) {
            guard !candidate.isEmpty else { continue }
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    func writeDefaultConfigTemplate(destination: String, workspaceRoot: String) throws {
        let incoming = "\(workspaceRoot)/incoming"
        let working = "\(workspaceRoot)/work"
        let output = "\(workspaceRoot)/output"
        let dbPath = "\(working)/queue.sqlite3"
        let logPath = "\(working)/framerelay.log"

        let directories = [incoming, working, output, "\(workspaceRoot)/config"]
        let fm = FileManager.default
        for dir in directories where !fm.fileExists(atPath: dir) {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        let yaml = """
        watch:
          source_dir: \(yamlQuote(incoming))
          working_dir: \(yamlQuote(working))
          output_dir: \(yamlQuote(output))
          db_path: \(yamlQuote(dbPath))
          include_extensions:
          - .cr2
          - .cr3
          - .raw
          stable_seconds: 3.0
          poll_interval_seconds: 1.0
          scan_interval_seconds: 5.0
          max_workers: 2
          shot_complete_seconds: 30.0
          shot_regex: null
        pipeline:
          camera_to_reference_matrix:
          - - 1.0
            - 0.0
            - 0.0
          - - 0.0
            - 1.0
            - 0.0
          - - 0.0
            - 0.0
            - 1.0
          exposure_offset_stops: 2.0
          auto_exposure_from_iso: false
          auto_exposure_from_shutter: false
          target_shutter_s: null
          auto_exposure_from_aperture: false
          target_aperture_f: null
          contrast: 1.25
          contrast_pivot_linear: 0.18
          lock_wb_from_first_frame: true
          target_ei: 800
          apply_match_lut: false
          match_lut_path: null
          use_ocio: false
          ocio_config_path: null
          ocio_input_space: camera_linear
          ocio_reference_space: ACES2065-1
          ocio_output_space: ARRI_LogC3_EI800_AWG
        output:
          emit_per_frame_json: true
          emit_truth_frame_pack: true
          truth_frame_index: 1
          write_debug_tiff: false
          write_prores_on_shot_complete: false
          framerate: 24
          show_lut_rec709_path: null
        log_level: INFO
        log_file: \(yamlQuote(logPath))
        """
        try yaml.appending("\n").write(toFile: destination, atomically: true, encoding: .utf8)
    }

    func bootstrapWorkspaceIfNeeded(workspaceRoot: String, configPath: String) throws -> WorkspaceBootstrapResult {
        let trimmedRoot = workspaceRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConfig = configPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let fm = FileManager.default

        if !fm.fileExists(atPath: trimmedRoot) {
            try fm.createDirectory(atPath: trimmedRoot, withIntermediateDirectories: true)
        }

        let destination = trimmedConfig.isEmpty
            ? defaultConfigPath(forWorkspaceRoot: trimmedRoot)
            : trimmedConfig

        if fm.fileExists(atPath: destination) {
            return WorkspaceBootstrapResult(resolvedConfigPath: destination, createdConfig: false)
        }

        let configParent = (destination as NSString).deletingLastPathComponent
        if !configParent.isEmpty, !fm.fileExists(atPath: configParent) {
            try fm.createDirectory(atPath: configParent, withIntermediateDirectories: true)
        }

        try writeDefaultConfigTemplate(destination: destination, workspaceRoot: trimmedRoot)
        return WorkspaceBootstrapResult(resolvedConfigPath: destination, createdConfig: true)
    }

    private func resolveCandidateRoot(_ value: String) -> String? {
        if isLikelyRepoRoot(path: value) {
            return value
        }
        let url = URL(fileURLWithPath: value).standardizedFileURL
        if url.lastPathComponent == "StopmoXcodeGUI" {
            let parent = url.deletingLastPathComponent().deletingLastPathComponent()
            if isLikelyRepoRoot(path: parent.path) {
                return parent.path
            }
        }
        return discoverRepoRootNear(path: value)
    }

    private func defaultWorkspaceRoot() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents")
            .appendingPathComponent(Self.defaultWorkspaceFolderName)
            .path
    }

    private func yamlQuote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
