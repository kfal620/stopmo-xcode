import Foundation

enum ToolsPreflightReducer {
    static func transcode(
        inputPath: String,
        outputDir: String,
        pathExists: (String) -> Bool
    ) -> ToolPreflight {
        var blockers: [String] = []
        var warnings: [String] = []

        let input = inputPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.isEmpty {
            blockers.append("Input RAW frame path is required.")
        } else if !pathExists(input) {
            blockers.append("Input RAW frame path does not exist.")
        }

        let output = outputDir.trimmingCharacters(in: .whitespacesAndNewlines)
        if !output.isEmpty, !pathExists(output) {
            warnings.append("Output override path does not currently exist and will be created if possible.")
        }

        return ToolPreflight(blockers: blockers, warnings: warnings)
    }

    static func matrix(
        inputPath: String,
        writeJsonPath: String,
        pathExists: (String) -> Bool
    ) -> ToolPreflight {
        var blockers: [String] = []
        var warnings: [String] = []

        let input = inputPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.isEmpty {
            blockers.append("Input RAW frame path is required.")
        } else if !pathExists(input) {
            blockers.append("Input RAW frame path does not exist.")
        }

        let reportPath = writeJsonPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !reportPath.isEmpty {
            let parent = (reportPath as NSString).deletingLastPathComponent
            if parent.isEmpty || !pathExists(parent) {
                warnings.append("JSON report parent folder does not exist.")
            }
        }

        return ToolPreflight(blockers: blockers, warnings: warnings)
    }

    static func dpx(
        inputDir: String,
        outputDir: String,
        pathExists: (String) -> Bool,
        dpxCount: (String) -> Int
    ) -> ToolPreflight {
        var blockers: [String] = []
        var warnings: [String] = []

        let input = inputDir.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.isEmpty {
            blockers.append("Input directory is required.")
        } else if !pathExists(input) {
            blockers.append("Input directory does not exist.")
        } else if dpxCount(input) == 0 {
            warnings.append("No .dpx files were found under the input directory.")
        }

        let output = outputDir.trimmingCharacters(in: .whitespacesAndNewlines)
        if !output.isEmpty, !pathExists(output) {
            warnings.append("Output directory does not exist and will be created if possible.")
        }
        if !input.isEmpty, !output.isEmpty, input == output {
            warnings.append("Input and output directories are the same.")
        }

        return ToolPreflight(blockers: blockers, warnings: warnings)
    }
}
