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

    var iconName: String {
        switch self {
        case .setup:
            return "wrench.and.screwdriver"
        case .project:
            return "slider.horizontal.3"
        case .liveMonitor:
            return "dot.radiowaves.left.and.right"
        case .shots:
            return "film.stack"
        case .queue:
            return "list.bullet.rectangle"
        case .tools:
            return "hammer"
        case .logs:
            return "doc.text.magnifyingglass"
        case .history:
            return "clock.arrow.circlepath"
        }
    }

    var subtitle: String {
        switch self {
        case .setup:
            return "Runtime, paths, and safety checks"
        case .project:
            return "Watch, pipeline, and output config"
        case .liveMonitor:
            return "Watch controls and live telemetry"
        case .shots:
            return "Shot-level progress and assembly"
        case .queue:
            return "Recent jobs and retry context"
        case .tools:
            return "One-off transcode and matrix tools"
        case .logs:
            return "Warnings, logs, diagnostics bundle"
        case .history:
            return "Past runs and reproducibility data"
        }
    }
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
    struct CrashRecovery: Codable, Sendable {
        var lastStartupUtc: String?
        var lastShutdownUtc: String?
        var lastInflightResetCount: Int
        var runtimeRunning: Bool
    }

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
    var startBlocked: Bool?
    var launchError: String?
    var preflight: WatchPreflight?
    var crashRecovery: CrashRecovery?
}

struct OperationEventRecord: Codable, Sendable, Identifiable {
    var seq: Int
    var operationId: String
    var timestampUtc: String
    var eventType: String
    var message: String?
    var payload: [String: JSONValue]?

    var id: Int { seq }
}

struct OperationSnapshotRecord: Codable, Sendable {
    var id: String
    var kind: String
    var status: String
    var progress: Double
    var createdAtUtc: String
    var startedAtUtc: String?
    var finishedAtUtc: String?
    var cancelRequested: Bool
    var cancellable: Bool
    var error: String?
    var metadata: [String: JSONValue]
    var result: [String: JSONValue]?
}

struct ToolOperationEnvelope: Codable, Sendable {
    var operationId: String
    var operation: OperationSnapshotRecord
    var events: [OperationEventRecord]
}

struct LogEntryRecord: Codable, Sendable, Identifiable {
    var timestamp: String?
    var severity: String
    var logger: String
    var message: String
    var raw: String

    var id: String { "\(timestamp ?? "none")|\(logger)|\(raw)" }
}

struct DiagnosticWarningRecord: Codable, Sendable, Identifiable {
    var code: String
    var severity: String
    var timestamp: String?
    var message: String
    var logger: String?

    var id: String { "\(code)|\(timestamp ?? "none")|\(message)" }
}

struct LogsDiagnosticsSnapshot: Codable, Sendable {
    var configPath: String
    var logSources: [String]
    var entries: [LogEntryRecord]
    var warnings: [DiagnosticWarningRecord]
    var queueCounts: [String: Int]
    var watchRunning: Bool
    var watchPid: Int?
}

struct HistoryRunRecord: Codable, Sendable, Identifiable {
    var runId: String
    var startUtc: String
    var endUtc: String
    var totalJobs: Int
    var failedJobs: Int
    var counts: [String: Int]
    var shots: [String]
    var outputs: [String]
    var manifestPaths: [String]
    var pipelineHashes: [String]
    var toolVersions: [String]

    var id: String { runId }
}

struct HistorySummarySnapshot: Codable, Sendable {
    var configPath: String
    var dbPath: String
    var count: Int
    var runs: [HistoryRunRecord]
}

struct DiagnosticsBundleResult: Codable, Sendable {
    var bundlePath: String
    var createdAtUtc: String
    var sizeBytes: Int
}

struct ValidationItem: Codable, Sendable, Identifiable {
    var code: String
    var message: String
    var field: String

    var id: String { "\(code)|\(field)|\(message)" }
}

struct ConfigValidationSnapshot: Codable, Sendable {
    var configPath: String
    var ok: Bool
    var errors: [ValidationItem]
    var warnings: [ValidationItem]
}

struct WatchPreflight: Codable, Sendable {
    var configPath: String
    var ok: Bool
    var blockers: [String]
    var validation: ConfigValidationSnapshot
    var healthChecks: [String: Bool]
}

enum JSONValue: Codable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    var stringValue: String? {
        if case let .string(v) = self {
            return v
        }
        return nil
    }

    var doubleValue: Double? {
        if case let .number(v) = self {
            return v
        }
        return nil
    }

    var intValue: Int? {
        guard let value = doubleValue else { return nil }
        return Int(value)
    }

    var boolValue: Bool? {
        if case let .bool(v) = self {
            return v
        }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case let .object(v) = self {
            return v
        }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case let .array(v) = self {
            return v
        }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
            return
        }
        if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}
