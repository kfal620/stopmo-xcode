import Foundation

/// Top-level lifecycle navigation hubs for the desktop app.
enum LifecycleHub: String, CaseIterable, Identifiable {
    case configure = "Configure"
    case capture = "Capture"
    case triage = "Triage"
    case deliver = "Deliver"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .configure:
            return "slider.horizontal.3"
        case .capture:
            return "dot.radiowaves.left.and.right"
        case .triage:
            return "stethoscope"
        case .deliver:
            return "shippingbox"
        }
    }

    var subtitle: String {
        switch self {
        case .configure:
            return "Workspace, project settings, and calibration"
        case .capture:
            return "Live RAW -> DPX conversion & telemetry"
        case .triage:
            return "Converted DPX shots and diagnostics"
        case .deliver:
            return "DPX -> ProRes assembly and history"
        }
    }
}

/// Configure workspace sub-panels.
enum ConfigurePanel: String, CaseIterable, Identifiable {
    case projectSettings = "Project Settings"
    case workspaceHealth = "Workspace & Health"
    case calibration = "Calibration"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .projectSettings:
            return "slider.horizontal.3"
        case .workspaceHealth:
            return "wrench.and.screwdriver"
        case .calibration:
            return "camera.filters"
        }
    }
}

/// Triage workspace sub-panels.
enum TriagePanel: String, CaseIterable, Identifiable {
    case shots = "Shots"
    case queue = "Queue"
    case diagnostics = "Diagnostics"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .shots:
            return "film.stack"
        case .queue:
            return "list.bullet.rectangle"
        case .diagnostics:
            return "doc.text.magnifyingglass"
        }
    }
}

/// Deliver workspace sub-panels.
enum DeliverPanel: String, CaseIterable, Identifiable {
    case dayWrap = "Day Wrap"
    case runHistory = "Run History"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .dayWrap:
            return "film"
        case .runHistory:
            return "clock.arrow.circlepath"
        }
    }
}

/// Aggregated delivery run status presented in the deliver workspace.
enum DeliveryRunStatus: String, Codable, Sendable {
    case idle = "Idle"
    case running = "Running"
    case succeeded = "Succeeded"
    case partial = "Partial"
    case failed = "Failed"
}

/// Delivery run mode for either explicit selection or full day-wrap batch.
enum DeliveryRunKind: String, Codable, Sendable {
    case selectedShots = "Selected Shots"
    case dayWrapBatch = "Day Wrap Batch"
}

/// Visual tone used for per-event delivery run timeline rows.
enum DeliveryRunEventTone: String, Codable, Sendable {
    case neutral
    case success
    case warning
    case danger
}

/// Individual delivery run event row rendered in operation history UI.
struct DeliveryRunEvent: Identifiable, Codable, Sendable {
    var id: String
    var timestampUtc: String
    var tone: DeliveryRunEventTone
    var title: String
    var detail: String
    var shotName: String?
}

/// Summary state for active/last delivery run progress and events.
struct DeliveryRunState: Codable, Sendable {
    var kind: DeliveryRunKind
    var status: DeliveryRunStatus
    var total: Int
    var completed: Int
    var failed: Int
    var activeLabel: String
    var progress: Double
    var latestOutputs: [String]
    var events: [DeliveryRunEvent]
    var startedAtUtc: String?
    var finishedAtUtc: String?

    static var idleDefault: DeliveryRunState {
        DeliveryRunState(
            kind: .selectedShots,
            status: .idle,
            total: 0,
            completed: 0,
            failed: 0,
            activeLabel: "No active delivery",
            progress: 0.0,
            latestOutputs: [],
            events: [],
            startedAtUtc: nil,
            finishedAtUtc: nil
        )
    }
}

/// Runtime/backend health payload returned by Python bridge health command.
struct BridgeHealth: Codable, Sendable {
    var backendMode: String?
    var backendRoot: String?
    var workspaceRoot: String?
    var pythonExecutable: String
    var pythonVersion: String
    var venvPython: String
    var venvPythonExists: Bool
    var checks: [String: Bool]
    var ffmpegPath: String?
    var ffmpegSource: String?
    var stopmoVersion: String?
    var configPath: String?
    var configExists: Bool?
    var configLoadOk: Bool?
    var configError: String?
    var watchDbPath: String?
}

/// Editable project config document mirrored between bridge JSON and Swift UI.
struct StopmoConfigDocument: Codable, Sendable {
    /// Watch section values controlling source ingest and queue worker behavior.
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

    /// Pipeline section values controlling deterministic color/exposure behavior.
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

    /// Output section values controlling sidecars, debug artifacts, and delivery.
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

/// Data/view model for queue job record.
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

/// Data/view model for queue snapshot.
struct QueueSnapshot: Codable, Sendable {
    var dbPath: String
    var counts: [String: Int]
    var total: Int
    var recent: [QueueJobRecord]
}

/// Result payload for queue retry result.
struct QueueRetryResult: Codable, Sendable {
    var retried: Int
    var requestedIds: [Int]
    var failedBefore: Int
    var failedAfter: Int
    var queue: QueueSnapshot
}

/// Data/view model for shot summary row.
struct ShotSummaryRow: Codable, Sendable, Identifiable {
    var shotName: String
    var state: String
    var totalFrames: Int
    var doneFrames: Int
    var failedFrames: Int
    var inflightFrames: Int
    var progressRatio: Double
    var firstShotAt: String? = nil
    var lastUpdatedAt: String? = nil
    var assemblyState: String? = nil
    var outputMovPath: String? = nil
    var reviewMovPath: String? = nil
    var exposureOffsetStops: Double? = nil
    var wbMultipliers: [Double]? = nil
    var previewLatestPath: String? = nil
    var previewFirstPath: String? = nil
    var previewFirstFrameNumber: Int? = nil
    var previewLatestUpdatedAt: String? = nil

    var id: String { shotName }
}

/// Data/view model for shots summary snapshot.
struct ShotsSummarySnapshot: Codable, Sendable {
    var dbPath: String
    var count: Int
    var shots: [ShotSummaryRow]
}

/// State model for watch service state.
struct WatchServiceState: Codable, Sendable {
    /// Data/view model for crash recovery.
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

/// Data/view model for operation event record.
struct OperationEventRecord: Codable, Sendable, Identifiable {
    var seq: Int
    var operationId: String
    var timestampUtc: String
    var eventType: String
    var message: String?
    var payload: [String: JSONValue]?

    var id: Int { seq }
}

/// Data/view model for operation snapshot record.
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

/// Data/view model for tool operation envelope.
struct ToolOperationEnvelope: Codable, Sendable {
    var operationId: String
    var operation: OperationSnapshotRecord
    var events: [OperationEventRecord]
}

/// Data/view model for log entry record.
struct LogEntryRecord: Codable, Sendable, Identifiable {
    var timestamp: String?
    var severity: String
    var logger: String
    var message: String
    var raw: String

    var id: String { "\(timestamp ?? "none")|\(logger)|\(raw)" }
}

/// Data/view model for diagnostic warning record.
struct DiagnosticWarningRecord: Codable, Sendable, Identifiable {
    var code: String
    var severity: String
    var timestamp: String?
    var message: String
    var logger: String?

    var id: String { "\(code)|\(timestamp ?? "none")|\(message)" }
}

/// Data/view model for logs diagnostics snapshot.
struct LogsDiagnosticsSnapshot: Codable, Sendable {
    var configPath: String
    var logSources: [String]
    var entries: [LogEntryRecord]
    var warnings: [DiagnosticWarningRecord]
    var queueCounts: [String: Int]
    var watchRunning: Bool
    var watchPid: Int?
}

/// Data/view model for history run record.
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

/// Data/view model for history summary snapshot.
struct HistorySummarySnapshot: Codable, Sendable {
    var configPath: String
    var dbPath: String
    var count: Int
    var runs: [HistoryRunRecord]
}

/// Result payload for diagnostics bundle result.
struct DiagnosticsBundleResult: Codable, Sendable {
    var bundlePath: String
    var createdAtUtc: String
    var sizeBytes: Int
}

/// Data/view model for validation item.
struct ValidationItem: Codable, Sendable, Identifiable {
    var code: String
    var message: String
    var field: String

    var id: String { "\(code)|\(field)|\(message)" }
}

/// Data/view model for config validation snapshot.
struct ConfigValidationSnapshot: Codable, Sendable {
    var configPath: String
    var ok: Bool
    var errors: [ValidationItem]
    var warnings: [ValidationItem]
}

/// Data/view model for watch preflight.
struct WatchPreflight: Codable, Sendable {
    var configPath: String
    var ok: Bool
    var blockers: [String]
    var validation: ConfigValidationSnapshot
    var healthChecks: [String: Bool]
}

/// Enumeration for jsonvalue.
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
