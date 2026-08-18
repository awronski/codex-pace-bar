@preconcurrency import AppKit
import CodexActivityInsightsCore
import Foundation
import OSLog

@MainActor
public final class ActivityInsightsShadowController {
    private let configurationStore: ActivityInsightsConfigurationStore
    private let repository: ActivityInsightsRepository
    private let sampler: MacActivitySampler
    private let resolver: ActivityCodexExecutableResolver
    private let chartSnapshotWriter: ActivityInsightsChartSnapshotWriter
    private let historyCheckpointRunner: ActivityHistoryCheckpointRunner
    private let configuredCodexPath: String?
    private var collectorSessionID: UUID?
    private var historyTask: Task<Void, Never>?
    private var activityTask: Task<Void, Never>?
    private var lastChartSnapshotAt = Date.distantPast

    private static let lifecycleLog = Logger(
        subsystem: "app.codexpacebar.activity-insights",
        category: "lifecycle"
    )
    private static let historyLog = Logger(
        subsystem: "app.codexpacebar.activity-insights",
        category: "history"
    )
    private static let activityLog = Logger(
        subsystem: "app.codexpacebar.activity-insights",
        category: "activity"
    )

    public private(set) var isRunning = false

    public init(
        configurationStore: ActivityInsightsConfigurationStore = .init(),
        repository: ActivityInsightsRepository = .init(),
        sampler: MacActivitySampler = .init(),
        resolver: ActivityCodexExecutableResolver = .init(),
        chartSnapshotWriter: ActivityInsightsChartSnapshotWriter = .init(),
        historyCheckpointRunner: ActivityHistoryCheckpointRunner = .init(),
        configuredCodexPath: String? = nil
    ) {
        self.configurationStore = configurationStore
        self.repository = repository
        self.sampler = sampler
        self.resolver = resolver
        self.chartSnapshotWriter = chartSnapshotWriter
        self.historyCheckpointRunner = historyCheckpointRunner
        self.configuredCodexPath = configuredCodexPath
    }

    public func startIfEnabled() async {
        guard !isRunning else { return }

        let configuration: ActivityInsightsConfiguration
        do {
            configuration = try await configurationStore.load()
        } catch {
            Self.lifecycleLog.error("Shadow configuration could not be read.")
            return
        }
        guard configuration.shadowEnabled else {
            Self.lifecycleLog.info("Shadow collection is disabled.")
            return
        }

        let executable: URL
        do {
            executable = try resolver.resolve(configuredPath: configuredCodexPath)
        } catch {
            Self.lifecycleLog.error("Codex executable could not be resolved for shadow collection.")
            return
        }

        let collectorSessionID: UUID
        do {
            collectorSessionID = try await repository.startCollectorSession(
                expectedHeartbeatIntervalSeconds: configuration.sampleIntervalSeconds,
                enabledSince: configuration.shadowEnabledSince
            )
        } catch {
            Self.lifecycleLog.error("Collector runtime session could not be persisted.")
            return
        }
        self.collectorSessionID = collectorSessionID
        sampler.start()
        isRunning = true
        Self.lifecycleLog.info("Shadow collection started.")
        if let archive = try? await repository.load() {
            await publishChartSnapshot(archive: archive, configuration: configuration)
        }

        historyTask = Task { [weak self] in
            guard let self else { return }
            await self.runHistoryLoop(
                executable: executable,
                interval: configuration.historyIntervalSeconds,
                configuration: configuration
            )
        }
        activityTask = Task { [weak self] in
            guard let self else { return }
            await self.runActivityLoop(
                interval: configuration.sampleIntervalSeconds,
                collectorSessionID: collectorSessionID,
                configuration: configuration
            )
        }
    }

    public func stop(reason: ActivityCollectorStopReason = .requested) async {
        guard isRunning else { return }
        historyTask?.cancel()
        activityTask?.cancel()
        await historyTask?.value
        await activityTask?.value
        historyTask = nil
        activityTask = nil
        sampler.stop()
        if let collectorSessionID {
            do {
                let archive = try await repository.stopCollectorSession(
                    sessionID: collectorSessionID,
                    reason: reason
                )
                let configuration = try await configurationStore.load()
                await publishChartSnapshot(archive: archive, configuration: configuration)
            } catch {
                Self.lifecycleLog.error("Collector runtime session could not be closed.")
            }
        }
        collectorSessionID = nil
        isRunning = false
        Self.lifecycleLog.info("Shadow collection stopped.")
    }

    private func runHistoryLoop(
        executable: URL,
        interval: TimeInterval,
        configuration: ActivityInsightsConfiguration
    ) async {
        while !Task.isCancelled {
            do {
                let result = try await historyCheckpointRunner.run(
                    executable: executable,
                    configuration: .init(
                        lookbackDuration: Double(configuration.lookbackDays) * 24 * 60 * 60
                    ),
                    repository: repository
                )
                let batch = result.batch
                let archive = result.archive
                await publishChartSnapshot(archive: archive, configuration: configuration)
                Self.historyLog.info(
                    "History checkpoint completed: \(batch.run.threadsCollected, privacy: .public) threads, \(batch.run.turnsCollected, privacy: .public) turns, \(batch.run.threadsDeferred, privacy: .public) deferred, \(batch.run.threadsKnownFailed, privacy: .public) known failed, \(batch.run.threadFailures, privacy: .public) failures."
                )
                if Self.shouldContinueHistoryBackfillImmediately(after: batch.run) { continue }
            } catch is CancellationError {
                return
            } catch {
                Self.historyLog.error("History collection failed without modifying pace data.")
            }

            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            } catch {
                return
            }
        }
    }

    private func runActivityLoop(
        interval: TimeInterval,
        collectorSessionID: UUID,
        configuration: ActivityInsightsConfiguration
    ) async {
        var lastObservationAt = Date()
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            } catch {
                return
            }
            let now = Date()
            let elapsed = max(0, now.timeIntervalSince(lastObservationAt))
            let observation = sampler.observation(
                at: now,
                intervalSeconds: min(elapsed, interval)
            )
            do {
                try await repository.record(
                    observation: observation,
                    heartbeatFor: collectorSessionID,
                    now: now
                )
                lastObservationAt = now
                if now.timeIntervalSince(lastChartSnapshotAt) >= 60 {
                    let archive = try await repository.load()
                    await publishChartSnapshot(
                        archive: archive,
                        configuration: configuration,
                        now: now
                    )
                }
            } catch {
                Self.activityLog.error(
                    "Activity observation could not be saved: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    /// Drain a clean, finite checkpoint backlog without waiting five minutes between chunks.
    /// A failed checkpoint must use the normal interval so a bad task cannot create an
    /// expensive retry loop that continuously restarts and scans the Codex App Server.
    nonisolated static func shouldContinueHistoryBackfillImmediately(
        after run: ActivityCollectionRun
    ) -> Bool {
        run.threadsDeferred > 0 && run.threadFailures == 0
    }

    private func publishChartSnapshot(
        archive: ActivityInsightsArchive,
        configuration: ActivityInsightsConfiguration,
        now: Date = Date()
    ) async {
        do {
            _ = try await chartSnapshotWriter.publish(
                archive: archive,
                configuration: configuration,
                now: now
            )
            lastChartSnapshotAt = now
        } catch {
            Self.activityLog.error("Chart snapshot could not be updated.")
        }
    }
}
