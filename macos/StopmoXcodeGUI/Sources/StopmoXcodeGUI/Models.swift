import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case setup = "Setup"
    case project = "Project"
    case liveMonitor = "Live Monitor"
    case shots = "Shots"
    case queue = "Queue"
    case tools = "Tools"
    case logs = "Logs & Diagnostics"
    case history = "History"

    var id: String { rawValue }
}

struct BridgeHealth: Codable, Sendable {
    var pythonExecutable: String
    var pythonVersion: String
    var venvPython: String
    var venvPythonExists: Bool
    var checks: [String: Bool]
    var ffmpegPath: String?
    var stopmoVersion: String?
    var configPath: String?
    var configExists: Bool?
    var configLoadOk: Bool?
    var configError: String?
    var watchDbPath: String?
}

struct StopmoConfigDocument: Codable, Sendable {
    struct Watch: Codable, Sendable {
        var sourceDir: String
        var workingDir: String
        var outputDir: String
        var dbPath: String
        var includeExtensions: [String]
        var stableSeconds: Double
        var pollIntervalSeconds: Double
        var scanIntervalSeconds: Double
        var maxWorkers: Int
        var shotCompleteSeconds: Double
        var shotRegex: String?
    }

    struct Pipeline: Codable, Sendable {
        var cameraToReferenceMatrix: [[Double]]
        var exposureOffsetStops: Double
        var autoExposureFromIso: Bool
        var autoExposureFromShutter: Bool
        var targetShutterS: Double?
        var autoExposureFromAperture: Bool
        var targetApertureF: Double?
        var contrast: Double
        var contrastPivotLinear: Double
        var lockWbFromFirstFrame: Bool
        var targetEi: Int
        var applyMatchLut: Bool
        var matchLutPath: String?
        var useOcio: Bool
        var ocioConfigPath: String?
        var ocioInputSpace: String
        var ocioReferenceSpace: String
        var ocioOutputSpace: String
    }

    struct Output: Codable, Sendable {
        var emitPerFrameJson: Bool
        var emitTruthFramePack: Bool
        var truthFrameIndex: Int
        var writeDebugTiff: Bool
        var writeProresOnShotComplete: Bool
        var framerate: Int
        var showLutRec709Path: String?
    }

    var configPath: String?
    var watch: Watch
    var pipeline: Pipeline
    var output: Output
    var logLevel: String
    var logFile: String?
}

extension StopmoConfigDocument {
    static var empty: StopmoConfigDocument {
        StopmoConfigDocument(
            configPath: nil,
            watch: .init(
                sourceDir: "",
                workingDir: "",
                outputDir: "",
                dbPath: "",
                includeExtensions: [".cr2", ".cr3", ".raw"],
                stableSeconds: 3.0,
                pollIntervalSeconds: 1.0,
                scanIntervalSeconds: 5.0,
                maxWorkers: 2,
                shotCompleteSeconds: 30.0,
                shotRegex: nil
            ),
            pipeline: .init(
                cameraToReferenceMatrix: [[1, 0, 0], [0, 1, 0], [0, 0, 1]],
                exposureOffsetStops: 0.0,
                autoExposureFromIso: false,
                autoExposureFromShutter: false,
                targetShutterS: nil,
                autoExposureFromAperture: false,
                targetApertureF: nil,
                contrast: 1.0,
                contrastPivotLinear: 0.18,
                lockWbFromFirstFrame: true,
                targetEi: 800,
                applyMatchLut: false,
                matchLutPath: nil,
                useOcio: false,
                ocioConfigPath: nil,
                ocioInputSpace: "camera_linear",
                ocioReferenceSpace: "ACES2065-1",
                ocioOutputSpace: "ARRI_LogC3_EI800_AWG"
            ),
            output: .init(
                emitPerFrameJson: true,
                emitTruthFramePack: true,
                truthFrameIndex: 1,
                writeDebugTiff: false,
                writeProresOnShotComplete: false,
                framerate: 24,
                showLutRec709Path: nil
            ),
            logLevel: "INFO",
            logFile: nil
        )
    }
}

struct QueueJobRecord: Codable, Sendable, Identifiable {
    var id: Int
    var state: String
    var shot: String
    var frame: Int
    var source: String
    var attempts: Int
    var lastError: String?
    var workerId: String?
    var detectedAt: String
    var updatedAt: String
}

struct QueueSnapshot: Codable, Sendable {
    var dbPath: String
    var counts: [String: Int]
    var total: Int
    var recent: [QueueJobRecord]
}

struct ShotSummaryRow: Codable, Sendable, Identifiable {
    var shotName: String
    var state: String
    var totalFrames: Int
    var doneFrames: Int
    var failedFrames: Int
    var inflightFrames: Int
    var progressRatio: Double
    var lastUpdatedAt: String?
    var assemblyState: String?
    var outputMovPath: String?
    var reviewMovPath: String?
    var exposureOffsetStops: Double?
    var wbMultipliers: [Double]?

    var id: String { shotName }
}

struct ShotsSummarySnapshot: Codable, Sendable {
    var dbPath: String
    var count: Int
    var shots: [ShotSummaryRow]
}

struct WatchServiceState: Codable, Sendable {
    var running: Bool
    var pid: Int?
    var startedAtUtc: String?
    var configPath: String
    var logPath: String?
    var logTail: [String]
    var queue: QueueSnapshot
    var progressRatio: Double
    var completedFrames: Int
    var inflightFrames: Int
    var totalFrames: Int
}
