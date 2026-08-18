import CodexActivityInsightsContract
import Foundation
import OSLog

public enum ActivityInsightsChartErrorCode: String, Equatable, Sendable {
    case unreadable
    case unsupportedSchema
    case invalidSnapshot
}

public enum ActivityInsightsChartState: Equatable, Sendable {
    case absent
    case disabled
    case collecting(ActivityInsightsChartSnapshot)
    case ready(ActivityInsightsChartSnapshot)
    case partial(ActivityInsightsChartSnapshot)
    case stale(ActivityInsightsChartSnapshot)
    case unavailable(ActivityInsightsChartErrorCode)

    public var snapshot: ActivityInsightsChartSnapshot? {
        switch self {
        case .collecting(let snapshot), .ready(let snapshot), .partial(let snapshot), .stale(let snapshot):
            return snapshot
        case .absent, .disabled, .unavailable:
            return nil
        }
    }
}

public protocol ActivityInsightsChartReading: Sendable {
    func read(at now: Date) async -> ActivityInsightsChartState
}

public actor ActivityInsightsChartReader: ActivityInsightsChartReading {
    public let fileURL: URL

    private let fileManager: FileManager
    private static let log = Logger(
        subsystem: "app.codexpacebar.macos",
        category: "activity-insights.chart"
    )

    public init(
        fileURL: URL = ActivityInsightsChartSnapshotLocation.defaultFileURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func read(at now: Date = Date()) async -> ActivityInsightsChartState {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            Self.log.info("snapshot_read_failed code=missing")
            return .absent
        }
        let snapshot: ActivityInsightsChartSnapshot
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            snapshot = try decoder.decode(
                ActivityInsightsChartSnapshot.self,
                from: Data(contentsOf: fileURL)
            )
        } catch {
            Self.log.error("snapshot_read_failed code=unreadable")
            return .unavailable(.unreadable)
        }
        guard snapshot.schemaVersion == ActivityInsightsChartSnapshot.currentSchemaVersion else {
            Self.log.error("snapshot_read_failed code=unsupported_schema")
            return .unavailable(.unsupportedSchema)
        }
        guard Self.isValid(snapshot, at: now) else {
            Self.log.error("snapshot_read_failed code=invalid_snapshot")
            return .unavailable(.invalidSnapshot)
        }
        guard snapshot.collectionEnabled else {
            Self.log.info("snapshot_read_succeeded state=disabled")
            return .disabled
        }
        let heartbeatFresh = snapshot.collectorHeartbeatAt.map {
            now.timeIntervalSince($0) <= snapshot.heartbeatGraceSeconds
        } ?? false
        guard heartbeatFresh else {
            Self.log.info("snapshot_read_succeeded state=stale")
            return .stale(snapshot)
        }
        guard snapshot.fourState.totalSeconds > 0 else {
            Self.log.info("snapshot_read_succeeded state=collecting")
            return .collecting(snapshot)
        }
        let quality = snapshot.quality
        if quality.fourStateCoveragePercent < 95
            || quality.focusCoveragePercent < 95
            || quality.historySyncCoveragePercent < 95 {
            Self.log.info("snapshot_read_succeeded state=partial")
            return .partial(snapshot)
        }
        Self.log.info("snapshot_read_succeeded state=ready")
        return .ready(snapshot)
    }

    private static func isValid(_ snapshot: ActivityInsightsChartSnapshot, at now: Date) -> Bool {
        let durations = [
            snapshot.fourState.activeCodexWorkingSeconds,
            snapshot.fourState.activeCodexIdleSeconds,
            snapshot.fourState.inactiveCodexWorkingSeconds,
            snapshot.fourState.inactiveCodexIdleSeconds,
            snapshot.fourState.activeCodexUnknownSeconds,
            snapshot.fourState.inactiveCodexUnknownSeconds,
            snapshot.fourState.unknownUserCodexWorkingSeconds,
            snapshot.fourState.unknownUserCodexIdleSeconds,
            snapshot.fourState.unknownUserCodexUnknownSeconds,
            snapshot.workingFocus.focusedSeconds,
            snapshot.workingFocus.notFocusedSeconds,
            snapshot.workingFocus.unknownSeconds,
            snapshot.heartbeatGraceSeconds
        ]
        let percentages = [
            snapshot.quality.fourStateCoveragePercent,
            snapshot.quality.focusCoveragePercent,
            snapshot.quality.historySyncCoveragePercent
        ]
        return snapshot.windowStart < snapshot.windowEnd
            && snapshot.windowEnd <= snapshot.generatedAt.addingTimeInterval(5 * 60)
            && snapshot.generatedAt <= now.addingTimeInterval(5 * 60)
            && snapshot.sourceUpdatedAt <= snapshot.generatedAt.addingTimeInterval(5 * 60)
            && (snapshot.collectorHeartbeatAt.map {
                $0 <= now.addingTimeInterval(5 * 60)
            } ?? true)
            && durations.allSatisfy { $0.isFinite && $0 >= 0 }
            && snapshot.heartbeatGraceSeconds > 0
            && percentages.allSatisfy { $0.isFinite && (0...100).contains($0) }
            && snapshot.quality.provisionalTurnCount >= 0
    }
}
