import CodexActivityInsightsCore
import Foundation

public typealias ActivityHistoryCollectorFactory = @MainActor (
    URL,
    ActivityHistoryCollectionConfiguration
) -> any ActivityHistoryCollecting

/// Runs one durable history checkpoint with a collector that is always shut down. The caller
/// creates a new runner invocation for every deferred or scheduled checkpoint, preventing a
/// timed-out App Server process from being reused.
@MainActor
public struct ActivityHistoryCheckpointRunner {
    private let factory: ActivityHistoryCollectorFactory

    public init(factory: @escaping ActivityHistoryCollectorFactory = { executable, configuration in
        ActivityHistoryCollector(
            client: ActivityAppServerClient(executableURL: executable),
            configuration: configuration
        )
    }) {
        self.factory = factory
    }

    public func run(
        executable: URL,
        configuration: ActivityHistoryCollectionConfiguration,
        repository: ActivityInsightsRepository
    ) async throws -> (batch: ActivityCollectionBatch, archive: ActivityInsightsArchive) {
        let collector = factory(executable, configuration)
        do {
            let existing = try await repository.load()
            let batch = try await collector.collect(existing: existing)
            let archive = try await repository.apply(batch)
            await collector.shutdown()
            return (batch, archive)
        } catch {
            await collector.shutdown()
            throw error
        }
    }
}
