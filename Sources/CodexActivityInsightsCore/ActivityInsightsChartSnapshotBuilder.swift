import CodexActivityInsightsContract
import Foundation

public enum ActivityInsightsChartSnapshotBuilder {
    public static func build(
        archive: ActivityInsightsArchive,
        configuration: ActivityInsightsConfiguration,
        now: Date = Date(),
        lookbackDays: Double = ActivityInsightsChartSnapshot.defaultLookbackDays
    ) -> ActivityInsightsChartSnapshot {
        let windowStart = now.addingTimeInterval(-lookbackDays * 24 * 60 * 60)
        let audit = ActivityInsightsAuditor.audit(
            archive,
            now: now,
            windowStart: windowStart,
            collectorExpectedSince: configuration.shadowEnabled
                ? configuration.shadowEnabledSince
                : nil
        )
        return ActivityInsightsChartSnapshot(
            generatedAt: now,
            sourceUpdatedAt: archive.generatedAt,
            windowStart: windowStart,
            windowEnd: now,
            collectionEnabled: configuration.shadowEnabled,
            collectorHeartbeatAt: audit.collectorLastHeartbeatAt,
            // Snapshots are published at most once per minute while sampling. Keep the
            // freshness window above that cadence so a healthy collector does not flicker stale.
            heartbeatGraceSeconds: max(90, configuration.sampleIntervalSeconds * 6),
            fourState: ActivityInsightsFourStateDurations(
                activeCodexWorkingSeconds: audit.activeCodexWorkingSeconds,
                activeCodexIdleSeconds: audit.activeCodexIdleSeconds,
                inactiveCodexWorkingSeconds: audit.inactiveCodexWorkingSeconds,
                inactiveCodexIdleSeconds: audit.inactiveCodexIdleSeconds,
                activeCodexUnknownSeconds: audit.activeCodexUnknownSeconds,
                inactiveCodexUnknownSeconds: audit.inactiveCodexUnknownSeconds,
                unknownUserCodexWorkingSeconds: audit.unknownUserCodexWorkingSeconds,
                unknownUserCodexIdleSeconds: audit.unknownUserCodexIdleSeconds,
                unknownUserCodexUnknownSeconds: audit.unknownUserCodexUnknownSeconds
            ),
            workingFocus: ActivityInsightsWorkingFocusDurations(
                focusedSeconds: audit.codexWorkingFocusedSeconds,
                notFocusedSeconds: audit.codexWorkingNotFocusedSeconds,
                unknownSeconds: audit.codexWorkingFocusUnknownSeconds
            ),
            quality: ActivityInsightsChartQuality(
                fourStateCoveragePercent: audit.fourStateCoveragePercent,
                focusCoveragePercent: audit.codexFocusCoveragePercent,
                historySyncCoveragePercent: audit.historySyncCoveragePercent,
                provisionalTurnCount: audit.provisionalTurns
            )
        )
    }
}
