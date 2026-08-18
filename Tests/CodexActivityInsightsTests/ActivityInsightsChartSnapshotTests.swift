import CodexActivityInsightsContract
import CodexActivityInsightsCore
import Foundation
import Testing

@Suite
struct ActivityInsightsChartSnapshotTests {
    @Test
    func builderConservesFourStateAndFocusDurations() {
        let archive = fixtureArchive()
        let snapshot = ActivityInsightsChartSnapshotBuilder.build(
            archive: archive,
            configuration: enabledConfiguration(),
            now: testDate(1_030)
        )

        #expect(snapshot.schemaVersion == ActivityInsightsChartSnapshot.currentSchemaVersion)
        #expect(snapshot.collectionEnabled)
        #expect(snapshot.collectorHeartbeatAt == testDate(1_028))
        #expect(snapshot.heartbeatGraceSeconds == 90)
        #expect(snapshot.fourState.activeCodexWorkingSeconds == 4)
        #expect(snapshot.fourState.activeCodexIdleSeconds == 6)
        #expect(snapshot.fourState.inactiveCodexWorkingSeconds == 0)
        #expect(snapshot.fourState.inactiveCodexIdleSeconds == 10)
        #expect(snapshot.fourState.unknownUserStateSeconds == 10)
        #expect(snapshot.fourState.totalSeconds == 30)
        #expect(snapshot.workingFocus.focusedSeconds == 4)
        #expect(snapshot.workingFocus.notFocusedSeconds == 0)
        #expect(snapshot.workingFocus.unknownSeconds == 0)
        #expect(abs(snapshot.quality.fourStateCoveragePercent - (200.0 / 3.0)) < 0.001)
        #expect(snapshot.quality.focusCoveragePercent == 100)
        #expect(snapshot.quality.historySyncCoveragePercent == 100)
    }

    @Test
    func writerPublishesOnlyAggregateContractAndReplacesItAtomically() async throws {
        let directory = makeTestDirectoryURL()
        let fileURL = directory.appendingPathComponent("chart-summary.json")
        let writer = ActivityInsightsChartSnapshotWriter(fileURL: fileURL)
        let archive = fixtureArchive()

        let enabled = try await writer.publish(
            archive: archive,
            configuration: enabledConfiguration(),
            now: testDate(1_030)
        )
        #expect(enabled.collectionEnabled)

        let firstData = try Data(contentsOf: fileURL)
        let firstJSON = String(decoding: firstData, as: UTF8.self)
        let forbidden = [
            "thread-1", "turn-1", "input-1", "prompt", "content", "title", "cwd",
            "sessionSource", "threadSource", "parentThreadID"
        ]
        #expect(forbidden.allSatisfy { !firstJSON.contains($0) })
        #expect(try decoded(firstData) == enabled)

        let disabledConfiguration = ActivityInsightsConfiguration(
            shadowEnabled: false,
            historyIntervalSeconds: 300,
            sampleIntervalSeconds: 15,
            lookbackDays: 30
        )
        let disabled = try await writer.publish(
            archive: archive,
            configuration: disabledConfiguration,
            now: testDate(1_031)
        )
        #expect(!disabled.collectionEnabled)
        #expect(try decoded(Data(contentsOf: fileURL)) == disabled)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)) == [
            "chart-summary.json", "chart-summary.lock"
        ])

        try FileManager.default.removeItem(at: directory)
    }

    @Test
    func writerDoesNotLetAStaleProcessReplaceNewerSourceData() async throws {
        let directory = makeTestDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("chart-summary.json")
        let writer = ActivityInsightsChartSnapshotWriter(fileURL: fileURL)
        var newerArchive = fixtureArchive()
        newerArchive.generatedAt = testDate(1_029)

        let newer = try await writer.publish(
            archive: newerArchive,
            configuration: enabledConfiguration(),
            now: testDate(1_030)
        )
        let retained = try await writer.publish(
            archive: fixtureArchive(),
            configuration: enabledConfiguration(),
            now: testDate(1_031)
        )

        #expect(retained == newer)
        #expect(try decoded(Data(contentsOf: fileURL)) == newer)
    }

    private func fixtureArchive() -> ActivityInsightsArchive {
        let thread = testThread(
            updatedAt: testDate(1_025),
            recencyAt: testDate(1_025)
        )
        let turn = testTurn(
            startedAt: testDate(1_002),
            completedAt: testDate(1_006),
            durationMilliseconds: 4_000
        )
        let observations = [
            ActivityObservationFact(
                intervalStart: testDate(1_000),
                intervalEnd: testDate(1_010),
                userState: .active,
                codexFocus: .focused
            ),
            ActivityObservationFact(
                intervalStart: testDate(1_010),
                intervalEnd: testDate(1_020),
                userState: .inactive,
                codexFocus: .notFocused
            ),
            ActivityObservationFact(
                intervalStart: testDate(1_020),
                intervalEnd: testDate(1_030),
                userState: .unknown,
                codexFocus: .unknown
            )
        ]
        return ActivityInsightsArchive(
            generatedAt: testDate(1_028),
            threads: [thread.threadID: thread],
            turns: [turn.key: turn],
            historySyncVersions: [thread.threadID: thread.sourceUpdatedAt],
            observationFacts: Dictionary(uniqueKeysWithValues: observations.map { ($0.key, $0) }),
            collectorState: ActivityCollectorState(
                startedAt: testDate(1_000),
                lastHeartbeatAt: testDate(1_028),
                expectedHeartbeatIntervalSeconds: 15
            ),
            collectorSessionCount: 1
        )
    }

    private func enabledConfiguration() -> ActivityInsightsConfiguration {
        ActivityInsightsConfiguration(
            shadowEnabled: true,
            shadowEnabledSince: testDate(1_000),
            historyIntervalSeconds: 300,
            sampleIntervalSeconds: 15,
            lookbackDays: 30
        )
    }

    private func decoded(_ data: Data) throws -> ActivityInsightsChartSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ActivityInsightsChartSnapshot.self, from: data)
    }

    private func makeTestDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivityInsightsChartSnapshotTests-\(UUID().uuidString)")
    }
}
