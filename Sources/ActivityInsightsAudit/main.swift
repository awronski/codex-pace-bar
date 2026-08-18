import CodexActivityInsightsCore
import CodexActivityInsightsMac
import Darwin
import Foundation

@main
@MainActor
struct ActivityInsightsAuditCommand {
    static func main() async {
        do {
            try await run()
        } catch {
            FileHandle.standardError.write(Data("ActivityInsightsAudit failed: \(error.localizedDescription)\n".utf8))
            Darwin.exit(1)
        }
    }

    private static func run() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            printUsage()
            return
        }

        let storeURL = option("--store", in: arguments).map(URL.init(fileURLWithPath:))
            ?? ActivityInsightsRepository.defaultFileURL()
        let repository = ActivityInsightsRepository(fileURL: storeURL)
        let configurationURL = option("--configuration", in: arguments).map(URL.init(fileURLWithPath:))
            ?? storeURL.deletingLastPathComponent().appendingPathComponent("configuration.json")
        let configurationStore = ActivityInsightsConfigurationStore(fileURL: configurationURL)
        let chartSnapshotWriter = ActivityInsightsChartSnapshotWriter(
            fileURL: storeURL.deletingLastPathComponent().appendingPathComponent("chart-summary.json")
        )
        let launchAgent = ActivityInsightsLaunchAgentManager(
            activityDirectory: storeURL.deletingLastPathComponent()
        )

        switch command {
        case "enable":
            do {
                let configuration = try await configurationStore.setShadowEnabled(true)
                if let archive = try? await repository.load() {
                    _ = try? await chartSnapshotWriter.publish(
                        archive: archive,
                        configuration: configuration
                    )
                }
                let launcherStatus = try launchAgent.status()
                guard launcherStatus.installed else {
                    throw ActivityInsightsError.persistence(
                        "Install the Activity Insights LaunchAgent before enabling collection."
                    )
                }
                if !launcherStatus.running { try launchAgent.start() }
                try printJSON(ControlOutput(
                    configuration: configuration,
                    launcher: try launchAgent.status()
                ))
            } catch {
                if let configuration = try? await configurationStore.setShadowEnabled(false),
                   let archive = try? await repository.load() {
                    _ = try? await chartSnapshotWriter.publish(
                        archive: archive,
                        configuration: configuration
                    )
                }
                throw error
            }
        case "disable":
            let configuration = try await configurationStore.setShadowEnabled(false)
            if let archive = try? await repository.load() {
                _ = try? await chartSnapshotWriter.publish(
                    archive: archive,
                    configuration: configuration
                )
            }
            try printJSON(ControlOutput(
                configuration: configuration,
                launcher: try launchAgent.status()
            ))
        case "launcher-install":
            let existingConfiguration = try await configurationStore.load()
            if existingConfiguration.shadowEnabled,
               existingConfiguration.shadowEnabledSince == nil {
                _ = try await configurationStore.setShadowEnabled(true)
            }
            let collectorURL = option("--collector", in: arguments).map(URL.init(fileURLWithPath:))
                ?? URL(fileURLWithPath: CommandLine.arguments[0])
                    .deletingLastPathComponent()
                    .appendingPathComponent("ActivityInsightsCollector")
            let codexURL = try ActivityCodexExecutableResolver().resolve(
                configuredPath: option("--codex", in: arguments)
            )
            try printJSON(try launchAgent.install(
                collectorExecutableURL: collectorURL,
                codexExecutableURL: codexURL
            ))
        case "launcher-uninstall":
            let configuration = try await configurationStore.setShadowEnabled(false)
            if let archive = try? await repository.load() {
                _ = try? await chartSnapshotWriter.publish(
                    archive: archive,
                    configuration: configuration
                )
            }
            try printJSON(try launchAgent.uninstall())
        case "control-status":
            try printJSON(ControlOutput(
                configuration: try await configurationStore.load(),
                launcher: try launchAgent.status()
            ))
        case "status":
            let configuration = try await configurationStore.load()
            let archive = try await repository.load()
            let health = ActivityInsightsAuditor.audit(
                archive,
                collectorExpectedSince: configuration.shadowEnabled
                    ? configuration.shadowEnabledSince
                    : nil
            )
            try printJSON(StatusOutput(
                shadowEnabled: configuration.shadowEnabled,
                shadowEnabledSince: configuration.shadowEnabledSince,
                launcher: try launchAgent.status(),
                storedThreads: archive.threads.count,
                storedTurns: archive.turns.count,
                storedInputs: archive.inputs.count,
                storedActivityMinutes: archive.activityMinutes.count,
                storedObservationFacts: archive.observationFacts.count,
                lastCollectionAt: archive.collectionRuns.last?.finishedAt,
                lastThreadsDeferred: archive.collectionRuns.last?.threadsDeferred,
                lastThreadsKnownFailed: archive.collectionRuns.last?.threadsKnownFailed,
                lastThreadFailures: archive.collectionRuns.last?.threadFailures,
                lastFailureCounts: archive.collectionRuns.last?.failureCounts,
                collectorLastHeartbeatAt: health.collectorLastHeartbeatAt,
                collectorHeartbeatFresh: health.collectorHeartbeatFresh,
                collectorCoveragePercent: health.collectorCoveragePercent,
                collectorUnknownSeconds: health.collectorUnknownSeconds
            ))
        case "collect":
            let configuration = try await configurationStore.load()
            let batch = try await collect(arguments: arguments, existing: try await repository.load())
            let archive = try await repository.apply(batch)
            _ = try? await chartSnapshotWriter.publish(
                archive: archive,
                configuration: configuration
            )
            try printJSON(ActivityInsightsAuditor.audit(
                archive,
                windowStart: try reportWindowStart(arguments: arguments, defaultDays: 30),
                collectorExpectedSince: configuration.shadowEnabled
                    ? configuration.shadowEnabledSince
                    : nil
            ))
        case "audit":
            let configuration = try await configurationStore.load()
            let archive = try await repository.load()
            let report = ActivityInsightsAuditor.audit(
                archive,
                windowStart: try reportWindowStart(arguments: arguments),
                collectorExpectedSince: configuration.shadowEnabled
                    ? configuration.shadowEnabledSince
                    : nil
            )
            try printJSON(report)
            if !report.isHealthy { Darwin.exit(2) }
        case "validate":
            guard let manifestPath = option("--manifest", in: arguments) else {
                throw ActivityInsightsError.persistence("Validation requires --manifest PATH.")
            }
            let configuration = try await configurationStore.load()
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let manifest = try decoder.decode(
                ActivityValidationManifest.self,
                from: Data(contentsOf: URL(fileURLWithPath: manifestPath))
            )
            let report = try ActivityInsightsValidator.validate(
                archive: try await repository.load(),
                manifest: manifest,
                requirements: try validationRequirements(arguments: arguments),
                windowStart: try reportWindowStart(arguments: arguments, defaultDays: 7),
                collectorExpectedSince: configuration.shadowEnabled
                    ? configuration.shadowEnabledSince
                    : nil
            )
            try printJSON(report)
            if !report.isReady { Darwin.exit(3) }
        case "validation-candidates":
            try printJSON(ActivityInsightsValidator.candidates(
                archive: try await repository.load(),
                windowStart: try reportWindowStart(arguments: arguments, defaultDays: 1)
            ))
        case "failure-candidates":
            try printJSON(ActivityInsightsValidator.failureCandidates(
                archive: try await repository.load(),
                windowStart: try reportWindowStart(arguments: arguments, defaultDays: 7)
            ))
        case "audit-live":
            let batch = try await collect(
                arguments: arguments,
                existing: .init(),
                maximumThreadsPerRun: .max
            )
            var archive = ActivityInsightsArchive(generatedAt: batch.run.finishedAt)
            archive.threads = Dictionary(uniqueKeysWithValues: batch.threads.map { ($0.threadID, $0) })
            archive.turns = Dictionary(uniqueKeysWithValues: batch.turns.map { ($0.key, $0) })
            archive.inputs = Dictionary(uniqueKeysWithValues: batch.inputs.map { ($0.key, $0) })
            archive.collectionRuns = [batch.run]
            let report = ActivityInsightsAuditor.audit(
                archive,
                windowStart: try reportWindowStart(arguments: arguments, defaultDays: 30)
            )
            try printJSON(report)
            if !report.isHealthy { Darwin.exit(2) }
        case "shadow":
            var archive = try await repository.load()
            var batch: ActivityCollectionBatch
            repeat {
                batch = try await collect(arguments: arguments, existing: archive)
                archive = try await repository.apply(batch)
                printCheckpoint(batch.run)
            } while batch.run.threadsDeferred > 0
            let duration = numberOption("--duration", in: arguments) ?? 30
            let interval = numberOption("--sample-interval", in: arguments) ?? 5
            guard duration >= 0, interval > 0 else {
                throw ActivityInsightsError.persistence("Shadow duration must be non-negative and interval positive.")
            }
            let sampler = MacActivitySampler()
            sampler.start()
            defer { sampler.stop() }
            let end = Date().addingTimeInterval(duration)
            while Date() < end {
                let wait = min(interval, max(0, end.timeIntervalSinceNow))
                if wait > 0 {
                    try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                }
                _ = try await repository.record(
                    observation: sampler.observation(at: Date(), intervalSeconds: wait)
                )
            }
            let report = ActivityInsightsAuditor.audit(
                try await repository.load(),
                windowStart: try reportWindowStart(arguments: arguments, defaultDays: 30)
            )
            if let archive = try? await repository.load() {
                let configuration = try await configurationStore.load()
                _ = try? await chartSnapshotWriter.publish(
                    archive: archive,
                    configuration: configuration
                )
            }
            try printJSON(report)
            if !report.isHealthy { Darwin.exit(2) }
        case "help", "--help", "-h":
            printUsage()
        default:
            printUsage()
            throw ActivityInsightsError.persistence("Unknown command \(command).")
        }
    }

    private static func collect(
        arguments: [String],
        existing: ActivityInsightsArchive,
        maximumThreadsPerRun: Int = 100
    ) async throws -> ActivityCollectionBatch {
        let configuredPath = option("--codex", in: arguments)
        let executable = try ActivityCodexExecutableResolver().resolve(configuredPath: configuredPath)
        let lookbackDays = numberOption("--lookback-days", in: arguments) ?? 30
        let requestTimeout = numberOption("--request-timeout", in: arguments) ?? 10
        let checkpointSize = integerOption("--checkpoint-size", in: arguments) ?? maximumThreadsPerRun
        let retryKnownFailures = arguments.contains("--retry-known-failures")
        let retryThreadID = option("--thread-id", in: arguments)
        let preferPaginatedTurns = arguments.contains("--prefer-paginated-turns")
        guard lookbackDays >= 1 else {
            throw ActivityInsightsError.persistence("Lookback must be at least one day.")
        }
        guard requestTimeout > 0, checkpointSize > 0 else {
            throw ActivityInsightsError.persistence("Request timeout and checkpoint size must be positive.")
        }
        guard retryThreadID == nil || retryKnownFailures else {
            throw ActivityInsightsError.persistence("--thread-id requires --retry-known-failures.")
        }
        guard !preferPaginatedTurns || retryKnownFailures else {
            throw ActivityInsightsError.persistence(
                "--prefer-paginated-turns requires --retry-known-failures."
            )
        }
        let client = ActivityAppServerClient(executableURL: executable)
        let collector = ActivityHistoryCollector(
            client: client,
            configuration: .init(
                lookbackDuration: lookbackDays * 24 * 60 * 60,
                requestTimeout: requestTimeout,
                maximumThreadsPerRun: checkpointSize,
                retryKnownFailures: retryKnownFailures,
                retryKnownFailureThreadID: retryThreadID,
                preferPaginatedTurns: preferPaginatedTurns
            )
        )
        do {
            let result = try await collector.collect(existing: existing)
            await collector.shutdown()
            return result
        } catch {
            await collector.shutdown()
            throw error
        }
    }

    private static func option(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func numberOption(_ name: String, in arguments: [String]) -> TimeInterval? {
        option(name, in: arguments).flatMap(Double.init)
    }

    private static func integerOption(_ name: String, in arguments: [String]) -> Int? {
        option(name, in: arguments).flatMap(Int.init)
    }

    private static func reportWindowStart(
        arguments: [String],
        defaultDays: TimeInterval? = nil
    ) throws -> Date? {
        guard let days = numberOption("--lookback-days", in: arguments) ?? defaultDays else {
            return nil
        }
        guard days >= 1 else {
            throw ActivityInsightsError.persistence("Lookback must be at least one day.")
        }
        return Date().addingTimeInterval(-days * 24 * 60 * 60)
    }

    private static func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func printCheckpoint(_ run: ActivityCollectionRun) {
        let categories = run.failureCounts.keys.sorted().map {
            "\($0)=\(run.failureCounts[$0, default: 0])"
        }.joined(separator: ",")
        FileHandle.standardError.write(Data(
            "Checkpoint: \(run.threadsCollected) histories attempted, \(run.turnsCollected) turns, \(run.threadsDeferred) deferred, \(run.threadsKnownFailed) known failed, \(run.threadFailures) failures [\(categories)].\n".utf8
        ))
    }

    private static func printUsage() {
        print("""
        Usage: ActivityInsightsAudit <command> [options]

          enable                         Enable the independent shadow collector.
          disable                        Disable the independent shadow collector.
          launcher-install               Install and load the independent user LaunchAgent.
          launcher-uninstall             Disable and remove the independent user LaunchAgent.
          control-status                 Show collector configuration and launcher status.
          status                         Show sanitized local collection status.
          collect                        Collect Codex history into the independent store.
          audit                          Audit the independent store without writing it.
          audit-live                     Audit live Codex history without writing it.
          shadow                         Collect history and sample Mac activity for a bounded duration.
          validate                       Evaluate a controlled truth-set manifest and readiness gates.
          validation-candidates          List sanitized recent inputs for truth-set matching.
          failure-candidates             List sanitized quarantined versions for targeted retry.

        Options:
          --store PATH                   Override the independent archive path.
          --configuration PATH           Override the independent configuration path.
          --codex PATH                   Override the Codex executable.
          --collector PATH               Collector binary to install with launcher-install.
          --manifest PATH                Controlled validation manifest for validate.
          --lookback-days DAYS           History lookback, default 30.
          --checkpoint-size COUNT        Histories per durable checkpoint, default 20.
          --request-timeout SECONDS      Per-request timeout, default 10.
          --retry-known-failures         Revalidate quarantined versions in bounded checkpoints.
          --thread-id ID                 Target one quarantined task; requires explicit retry.
          --prefer-paginated-turns       Bypass full thread/read for a known oversized task.
          --duration SECONDS             Shadow activity duration, default 30.
          --sample-interval SECONDS      Shadow sample interval, default 5.
          --minimum-cases COUNT          Validation sample size, default 20.
          --minimum-days COUNT           Validation work-day count, default 7.
          --minimum-origin-percent N     Origin coverage gate, default 95.
          --minimum-history-percent N    History sync gate, default 95.
          --minimum-focus-percent N      Codex focus coverage gate, default 95.
          --minimum-four-state-percent N Four-state coverage gate, default 95.
          --minimum-state-cases COUNT    Controlled four-state cases, default 20.
          --minimum-state-days COUNT     Controlled four-state work days, default 7.
          --minimum-state-coverage N     Controlled interval coverage, default 95.
        """)
    }

    private static func validationRequirements(
        arguments: [String]
    ) throws -> ActivityValidationRequirements {
        let requirements = ActivityValidationRequirements(
            minimumCases: integerOption("--minimum-cases", in: arguments) ?? 20,
            minimumDistinctWorkDays: integerOption("--minimum-days", in: arguments) ?? 7,
            minimumOriginCoveragePercent: numberOption(
                "--minimum-origin-percent",
                in: arguments
            ) ?? 95,
            minimumHistorySyncCoveragePercent: numberOption(
                "--minimum-history-percent",
                in: arguments
            ) ?? 95,
            minimumCodexFocusCoveragePercent: numberOption(
                "--minimum-focus-percent",
                in: arguments
            ) ?? 95,
            minimumFourStateCoveragePercent: numberOption(
                "--minimum-four-state-percent",
                in: arguments
            ) ?? 95,
            minimumStateCases: integerOption("--minimum-state-cases", in: arguments) ?? 20,
            minimumStateWorkDays: integerOption("--minimum-state-days", in: arguments) ?? 7,
            minimumStateIntervalCoveragePercent: numberOption(
                "--minimum-state-coverage",
                in: arguments
            ) ?? 95
        )
        guard requirements.minimumCases >= 1,
              requirements.minimumDistinctWorkDays >= 1,
              requirements.minimumStateCases >= 1,
              requirements.minimumStateWorkDays >= 1
        else {
            throw ActivityInsightsError.persistence("Validation counts must be positive.")
        }
        return requirements
    }
}

private struct StatusOutput: Encodable {
    let shadowEnabled: Bool
    let shadowEnabledSince: Date?
    let launcher: ActivityInsightsLaunchAgentStatus
    let storedThreads: Int
    let storedTurns: Int
    let storedInputs: Int
    let storedActivityMinutes: Int
    let storedObservationFacts: Int
    let lastCollectionAt: Date?
    let lastThreadsDeferred: Int?
    let lastThreadsKnownFailed: Int?
    let lastThreadFailures: Int?
    let lastFailureCounts: [String: Int]?
    let collectorLastHeartbeatAt: Date?
    let collectorHeartbeatFresh: Bool?
    let collectorCoveragePercent: Double
    let collectorUnknownSeconds: Double
}

private struct ControlOutput: Encodable {
    let configuration: ActivityInsightsConfiguration
    let launcher: ActivityInsightsLaunchAgentStatus
}
