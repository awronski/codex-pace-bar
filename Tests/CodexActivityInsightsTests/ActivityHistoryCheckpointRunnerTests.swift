import CodexActivityInsightsCore
import CodexActivityInsightsMac
import Foundation
import Testing

@Suite
@MainActor
struct ActivityHistoryCheckpointRunnerTests {
    @Test
    func failedCheckpointIsShutDownAndNextCheckpointUsesFreshCollector() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ActivityInsightsRepository(
            fileURL: directory.appendingPathComponent("archive.json")
        )
        let factory = CheckpointFactoryState()
        let runner = ActivityHistoryCheckpointRunner { _, _ in factory.makeCollector() }

        do {
            _ = try await runner.run(
                executable: URL(fileURLWithPath: "/tmp/codex"),
                configuration: .init(),
                repository: repository
            )
            Issue.record("Expected the first checkpoint to fail.")
        } catch let error as ActivityInsightsError {
            #expect(error == .invalidResponse("simulated timeout"))
        }

        let successful = try await runner.run(
            executable: URL(fileURLWithPath: "/tmp/codex"),
            configuration: .init(),
            repository: repository
        )

        #expect(factory.createdCollectors == 2)
        #expect(factory.shutdownCollectors == 2)
        #expect(successful.archive.threads.count == 1)
    }
}

@MainActor
private final class CheckpointFactoryState {
    var createdCollectors = 0
    var shutdownCollectors = 0

    func makeCollector() -> any ActivityHistoryCollecting {
        createdCollectors += 1
        return CheckpointCollector(
            shouldFail: createdCollectors == 1,
            factory: self
        )
    }

    func didShutdown() {
        shutdownCollectors += 1
    }
}

private actor CheckpointCollector: ActivityHistoryCollecting {
    let shouldFail: Bool
    let factory: CheckpointFactoryState

    init(shouldFail: Bool, factory: CheckpointFactoryState) {
        self.shouldFail = shouldFail
        self.factory = factory
    }

    func collect(existing: ActivityInsightsArchive) async throws -> ActivityCollectionBatch {
        if shouldFail {
            throw ActivityInsightsError.invalidResponse("simulated timeout")
        }
        let now = Date()
        let thread = testThread(updatedAt: now, recencyAt: now)
        return testBatch(
            thread: thread,
            turn: testTurn(
                startedAt: now.addingTimeInterval(-2),
                completedAt: now.addingTimeInterval(-1)
            ),
            run: testRun(at: now)
        )
    }

    func shutdown() async {
        await factory.didShutdown()
    }
}
