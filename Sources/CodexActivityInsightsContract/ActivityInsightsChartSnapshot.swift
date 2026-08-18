import Foundation

public struct ActivityInsightsFourStateDurations: Codable, Equatable, Sendable {
    public let activeCodexWorkingSeconds: TimeInterval
    public let activeCodexIdleSeconds: TimeInterval
    public let inactiveCodexWorkingSeconds: TimeInterval
    public let inactiveCodexIdleSeconds: TimeInterval
    public let activeCodexUnknownSeconds: TimeInterval
    public let inactiveCodexUnknownSeconds: TimeInterval
    public let unknownUserCodexWorkingSeconds: TimeInterval
    public let unknownUserCodexIdleSeconds: TimeInterval
    public let unknownUserCodexUnknownSeconds: TimeInterval

    public init(
        activeCodexWorkingSeconds: TimeInterval,
        activeCodexIdleSeconds: TimeInterval,
        inactiveCodexWorkingSeconds: TimeInterval,
        inactiveCodexIdleSeconds: TimeInterval,
        activeCodexUnknownSeconds: TimeInterval,
        inactiveCodexUnknownSeconds: TimeInterval,
        unknownUserCodexWorkingSeconds: TimeInterval,
        unknownUserCodexIdleSeconds: TimeInterval,
        unknownUserCodexUnknownSeconds: TimeInterval
    ) {
        self.activeCodexWorkingSeconds = activeCodexWorkingSeconds
        self.activeCodexIdleSeconds = activeCodexIdleSeconds
        self.inactiveCodexWorkingSeconds = inactiveCodexWorkingSeconds
        self.inactiveCodexIdleSeconds = inactiveCodexIdleSeconds
        self.activeCodexUnknownSeconds = activeCodexUnknownSeconds
        self.inactiveCodexUnknownSeconds = inactiveCodexUnknownSeconds
        self.unknownUserCodexWorkingSeconds = unknownUserCodexWorkingSeconds
        self.unknownUserCodexIdleSeconds = unknownUserCodexIdleSeconds
        self.unknownUserCodexUnknownSeconds = unknownUserCodexUnknownSeconds
    }

    public var unknownUserStateSeconds: TimeInterval {
        unknownUserCodexWorkingSeconds
            + unknownUserCodexIdleSeconds
            + unknownUserCodexUnknownSeconds
    }

    public var unknownSeconds: TimeInterval {
        activeCodexUnknownSeconds + inactiveCodexUnknownSeconds + unknownUserStateSeconds
    }

    public var knownSeconds: TimeInterval {
        activeCodexWorkingSeconds
            + activeCodexIdleSeconds
            + inactiveCodexWorkingSeconds
            + inactiveCodexIdleSeconds
    }

    public var totalSeconds: TimeInterval { knownSeconds + unknownSeconds }

    public var activeSeconds: TimeInterval {
        activeCodexWorkingSeconds + activeCodexIdleSeconds + activeCodexUnknownSeconds
    }

    public var codexWorkingSeconds: TimeInterval {
        activeCodexWorkingSeconds + inactiveCodexWorkingSeconds
    }

    public var handsOnCodexSharePercent: Double? {
        guard codexWorkingSeconds > 0 else { return nil }
        return activeCodexWorkingSeconds / codexWorkingSeconds * 100
    }

    public var handsOffCodexSharePercent: Double? {
        guard codexWorkingSeconds > 0 else { return nil }
        return inactiveCodexWorkingSeconds / codexWorkingSeconds * 100
    }

    public var confirmedActiveCodexSharePercent: Double? {
        guard activeSeconds > 0 else { return nil }
        return activeCodexWorkingSeconds / activeSeconds * 100
    }

    public var possibleActiveCodexSharePercent: Double? {
        guard activeSeconds > 0 else { return nil }
        return (activeCodexWorkingSeconds + activeCodexUnknownSeconds) / activeSeconds * 100
    }
}

public struct ActivityInsightsWorkingFocusDurations: Codable, Equatable, Sendable {
    public let focusedSeconds: TimeInterval
    public let notFocusedSeconds: TimeInterval
    public let unknownSeconds: TimeInterval

    public init(
        focusedSeconds: TimeInterval,
        notFocusedSeconds: TimeInterval,
        unknownSeconds: TimeInterval
    ) {
        self.focusedSeconds = focusedSeconds
        self.notFocusedSeconds = notFocusedSeconds
        self.unknownSeconds = unknownSeconds
    }

    public var totalSeconds: TimeInterval { focusedSeconds + notFocusedSeconds + unknownSeconds }

    public var focusedSharePercent: Double? {
        let known = focusedSeconds + notFocusedSeconds
        guard known > 0 else { return nil }
        return focusedSeconds / known * 100
    }
}

public struct ActivityInsightsChartQuality: Codable, Equatable, Sendable {
    public let fourStateCoveragePercent: Double
    public let focusCoveragePercent: Double
    public let historySyncCoveragePercent: Double
    public let provisionalTurnCount: Int

    public init(
        fourStateCoveragePercent: Double,
        focusCoveragePercent: Double,
        historySyncCoveragePercent: Double,
        provisionalTurnCount: Int
    ) {
        self.fourStateCoveragePercent = fourStateCoveragePercent
        self.focusCoveragePercent = focusCoveragePercent
        self.historySyncCoveragePercent = historySyncCoveragePercent
        self.provisionalTurnCount = provisionalTurnCount
    }
}

public struct ActivityInsightsChartSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2
    public static let defaultLookbackDays = 7.0

    public let schemaVersion: Int
    public let generatedAt: Date
    public let sourceUpdatedAt: Date
    public let windowStart: Date
    public let windowEnd: Date
    public let collectionEnabled: Bool
    public let collectorHeartbeatAt: Date?
    public let heartbeatGraceSeconds: TimeInterval
    public let fourState: ActivityInsightsFourStateDurations
    public let workingFocus: ActivityInsightsWorkingFocusDurations
    public let quality: ActivityInsightsChartQuality

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        generatedAt: Date,
        sourceUpdatedAt: Date,
        windowStart: Date,
        windowEnd: Date,
        collectionEnabled: Bool,
        collectorHeartbeatAt: Date?,
        heartbeatGraceSeconds: TimeInterval,
        fourState: ActivityInsightsFourStateDurations,
        workingFocus: ActivityInsightsWorkingFocusDurations,
        quality: ActivityInsightsChartQuality
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.sourceUpdatedAt = sourceUpdatedAt
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.collectionEnabled = collectionEnabled
        self.collectorHeartbeatAt = collectorHeartbeatAt
        self.heartbeatGraceSeconds = heartbeatGraceSeconds
        self.fourState = fourState
        self.workingFocus = workingFocus
        self.quality = quality
    }
}

public enum ActivityInsightsChartSnapshotLocation {
    public static func defaultDirectoryURL(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return applicationSupport
            .appendingPathComponent("CodexPaceBar", isDirectory: true)
            .appendingPathComponent("ActivityInsights", isDirectory: true)
    }

    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        defaultDirectoryURL(fileManager: fileManager).appendingPathComponent("chart-summary.json")
    }
}
