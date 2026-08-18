import CodexActivityInsightsCore
import Foundation
import Testing

@Suite
struct ActivityInsightsRepositoryTests {
    @Test
    func missingStoreLoadsEmptyArchive() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ActivityInsightsRepository(fileURL: directory.appendingPathComponent("archive.json"))

        let archive = try await repository.load()

        #expect(archive == ActivityInsightsArchive())
    }

    @Test
    func schemaTwoArchiveMigratesWithoutLosingExistingFacts() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("archive.json")
        let legacy = ActivityInsightsArchive(
            schemaVersion: 2,
            threads: ["thread-1": testThread()]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        var object = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(legacy)) as? [String: Any]
        )
        object.removeValue(forKey: "collectorCoverageMinutes")
        object.removeValue(forKey: "collectorState")
        object.removeValue(forKey: "collectorSessionCount")
        object.removeValue(forKey: "observationFacts")
        object.removeValue(forKey: "historyFailureAttemptCounts")
        try JSONSerialization.data(withJSONObject: object).write(to: file)
        let repository = ActivityInsightsRepository(fileURL: file)

        let archive = try await repository.load()

        #expect(archive.schemaVersion == ActivityInsightsArchive.currentSchemaVersion)
        #expect(archive.threads["thread-1"] == testThread())
        #expect(archive.collectorCoverageMinutes.isEmpty)
        #expect(archive.collectorState == nil)
        #expect(archive.collectorSessionCount == 0)
        #expect(archive.observationFacts.isEmpty)
    }

    @Test
    func schemaThreeArchiveMigratesWithEmptyAlignedObservations() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("archive.json")
        let legacy = ActivityInsightsArchive(
            schemaVersion: 3,
            threads: ["thread-1": testThread()]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        var object = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(legacy)) as? [String: Any]
        )
        object.removeValue(forKey: "observationFacts")
        object.removeValue(forKey: "historyFailureAttemptCounts")
        try JSONSerialization.data(withJSONObject: object).write(to: file)

        let archive = try await ActivityInsightsRepository(fileURL: file).load()

        #expect(archive.schemaVersion == ActivityInsightsArchive.currentSchemaVersion)
        #expect(archive.threads["thread-1"] == testThread())
        #expect(archive.observationFacts.isEmpty)
    }

    @Test
    func applyIsIdempotentForFactsAndCollectionRun() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ActivityInsightsRepository(fileURL: directory.appendingPathComponent("archive.json"))
        let runID = UUID()
        let batch = testBatch(run: testRun(id: runID))

        _ = try await repository.apply(batch, now: testDate(1_300))
        let twice = try await repository.apply(batch, now: testDate(1_301))

        #expect(twice.threads.count == 1)
        #expect(twice.turns.count == 1)
        #expect(twice.inputs.count == 1)
        #expect(twice.collectionRuns.map(\.runID) == [runID])
        #expect(twice.historyAttemptVersions["thread-1"] == testDate(1_100))
        #expect(twice.historySyncVersions["thread-1"] == testDate(1_100))
        #expect(twice.historyFailureVersions.isEmpty)
        #expect(twice.historyFailureAttemptCounts.isEmpty)
    }

    @Test
    func failedHistoryAttemptsAdvanceOncePerRunAndClearAfterSuccess() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ActivityInsightsRepository(fileURL: directory.appendingPathComponent("archive.json"))
        let thread = testThread()
        let firstRun = testRun(at: testDate(1_300))
        let failed = ActivityCollectionBatch(
            threads: [thread],
            turns: [],
            inputs: [],
            refreshedThreadIDs: [],
            attemptedThreadIDs: [thread.threadID],
            run: firstRun
        )

        _ = try await repository.apply(failed, now: testDate(1_300))
        let duplicate = try await repository.apply(failed, now: testDate(1_301))
        #expect(duplicate.historyFailureAttemptCounts[thread.threadID] == 1)

        let secondFailure = ActivityCollectionBatch(
            threads: [thread],
            turns: [],
            inputs: [],
            refreshedThreadIDs: [],
            attemptedThreadIDs: [thread.threadID],
            run: testRun(at: testDate(1_400))
        )
        let twiceFailed = try await repository.apply(secondFailure, now: testDate(1_400))
        #expect(twiceFailed.historyFailureAttemptCounts[thread.threadID] == 2)

        let recovered = ActivityCollectionBatch(
            threads: [thread],
            turns: [],
            inputs: [],
            refreshedThreadIDs: [thread.threadID],
            attemptedThreadIDs: [thread.threadID],
            run: testRun(at: testDate(1_500))
        )
        let afterRecovery = try await repository.apply(recovered, now: testDate(1_500))
        #expect(afterRecovery.historyFailureVersions[thread.threadID] == nil)
        #expect(afterRecovery.historyFailureAttemptCounts[thread.threadID] == nil)
    }

    @Test
    func separateRepositoryInstancesSerializeHistoryUpdatesWithoutLosingFacts() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("archive.json")
        let firstRepository = ActivityInsightsRepository(fileURL: file)
        let secondRepository = ActivityInsightsRepository(fileURL: file)
        let firstBatch = testBatch(run: testRun(at: testDate(1_300)))
        let secondThread = testThread(id: "thread-2")
        let secondBatch = testBatch(
            thread: secondThread,
            turn: testTurn(threadID: "thread-2", turnID: "turn-2"),
            input: testInput(threadID: "thread-2", turnID: "turn-2", itemID: "input-2"),
            run: testRun(at: testDate(1_301))
        )

        async let first = firstRepository.apply(firstBatch, now: testDate(1_300))
        async let second = secondRepository.apply(secondBatch, now: testDate(1_301))
        _ = try await (first, second)

        let archive = try await firstRepository.load()
        #expect(Set(archive.threads.keys) == ["thread-1", "thread-2"])
        #expect(archive.turns.count == 2)
        #expect(archive.inputs.count == 2)
        #expect(archive.collectionRuns.count == 2)
    }

    @Test
    func activitySamplesDoNotRewriteTheHistoryArchive() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("archive.json")
        let repository = ActivityInsightsRepository(fileURL: file)
        _ = try await repository.apply(testBatch(), now: testDate(1_300))
        let historyBefore = try Data(contentsOf: file)

        try await repository.record(
            observation: ActivityObservation(
                timestamp: testDate(1_310),
                intervalSeconds: 10,
                idleSeconds: 1,
                codexFocus: .focused
            ),
            now: testDate(1_310)
        )

        #expect(try Data(contentsOf: file) == historyBefore)
        let archive = try await repository.load()
        #expect(archive.observationFacts.count == 1)
        #expect(FileManager.default.fileExists(
            atPath: file.deletingPathExtension().appendingPathExtension("sqlite3").path
        ))
    }

    @Test
    func refreshedThreadAtomicallyReplacesItsTurnsAndInputs() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ActivityInsightsRepository(fileURL: directory.appendingPathComponent("archive.json"))
        _ = try await repository.apply(testBatch(), now: testDate(1_300))

        let updatedThread = testThread(updatedAt: testDate(1_400), recencyAt: testDate(1_400))
        let newTurn = testTurn(turnID: "turn-2", startedAt: testDate(1_410), completedAt: testDate(1_412))
        let newInput = testInput(turnID: "turn-2", itemID: "input-2", kind: .followUp)
        let replacement = ActivityCollectionBatch(
            threads: [updatedThread],
            turns: [newTurn],
            inputs: [newInput],
            refreshedThreadIDs: [updatedThread.threadID],
            run: testRun(at: testDate(1_420))
        )

        let archive = try await repository.apply(replacement, now: testDate(1_420))

        #expect(archive.turns.keys.sorted() == [newTurn.key])
        #expect(archive.inputs.keys.sorted() == [newInput.key])
        #expect(archive.threads[updatedThread.threadID]?.sourceUpdatedAt == testDate(1_400))
    }

    @Test
    func updatedThreadProvenanceReclassifiesExistingInputsWithoutHistoryRefresh() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ActivityInsightsRepository(fileURL: directory.appendingPathComponent("archive.json"))
        let unknownThread = testThread(actor: .unknown, mechanism: .interactive, confidence: .unknown)
        let unknownInput = testInput(actor: .unknown)
        _ = try await repository.apply(
            testBatch(thread: unknownThread, input: unknownInput),
            now: testDate(1_300)
        )
        let userThread = testThread(actor: .user, mechanism: .interactive, confidence: .inferred)
        let metadataOnly = ActivityCollectionBatch(
            threads: [userThread],
            turns: [],
            inputs: [],
            refreshedThreadIDs: [],
            attemptedThreadIDs: [],
            run: testRun(at: testDate(1_400))
        )

        let archive = try await repository.apply(metadataOnly, now: testDate(1_400))

        #expect(archive.inputs[unknownInput.key]?.actor == .user)
        #expect(archive.inputs[unknownInput.key]?.textCharacters == unknownInput.textCharacters)
        #expect(archive.turns.count == 1)
    }

    @Test
    func persistedArchiveContainsMetricsButNotPromptContent() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("archive.json")
        let repository = ActivityInsightsRepository(fileURL: file)
        let marker = "PRIVATE-PROMPT-MARKER-8147"
        let parsed = try ActivityHistoryParser.turnFacts(
            from: [testJSON(#"{"id":"turn-1","startedAt":1200,"items":[{"id":"input-1","type":"userMessage","content":[{"type":"text","text":"PRIVATE-PROMPT-MARKER-8147"}]}]}"#)],
            thread: testThread()
        )
        let batch = ActivityCollectionBatch(
            threads: [testThread()],
            turns: parsed.turns,
            inputs: parsed.inputs,
            refreshedThreadIDs: ["thread-1"],
            run: testRun()
        )

        _ = try await repository.apply(batch, now: testDate(1_300))
        let stored = try String(decoding: Data(contentsOf: file), as: UTF8.self)

        #expect(!stored.contains(marker))
        #expect(stored.contains("textCharacters"))
        #expect(stored.contains("utf8Bytes"))
    }

    @Test
    func submillisecondSourceTimestampsPersistAfterJsonRoundTrip() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ActivityInsightsRepository(fileURL: directory.appendingPathComponent("archive.json"))
        let precise = testDate(1_100.123456789)
        let thread = testThread(updatedAt: precise, recencyAt: precise)

        _ = try await repository.apply(
            testBatch(thread: thread),
            now: testDate(1_300.987654321)
        )
        let loaded = try await repository.load()

        let loadedTimestamp = try #require(loaded.threads[thread.threadID]?.sourceUpdatedAt)
        #expect(abs(loadedTimestamp.timeIntervalSince(precise)) < 0.001)
        #expect(loaded.historySyncVersions[thread.threadID] == loadedTimestamp)
    }

    @Test
    func validBackupRecoversCorruptPrimaryAndBothCorruptFailClosed() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("activity-insights.json")
        let backup = directory.appendingPathComponent("activity-insights.backup.json")
        let repository = ActivityInsightsRepository(fileURL: file)
        let first = try await repository.apply(testBatch(), now: testDate(1_300))
        _ = try await repository.apply(
            testBatch(run: testRun(at: testDate(1_400))),
            now: testDate(1_400)
        )
        #expect(FileManager.default.fileExists(atPath: backup.path))

        try Data("broken-primary".utf8).write(to: file)
        #expect(try await repository.load() == first)

        try Data("broken-backup".utf8).write(to: backup)
        do {
            _ = try await repository.load()
            Issue.record("Expected unreadable primary and backup to fail.")
        } catch let error as ActivityInsightsError {
            #expect(error == .persistence("Both the primary archive and backup are unreadable."))
        }
    }

    @Test
    func retentionDropsExpiredThreadGraphAndActivityMinutes() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ActivityInsightsRepository(fileURL: directory.appendingPathComponent("archive.json"))
        let now = testDate(40 * testDay)
        let expiredDate = now.addingTimeInterval(-ActivityInsightsRepository.retentionDuration - 1)
        let expiredThread = testThread(
            createdAt: expiredDate,
            updatedAt: expiredDate,
            recencyAt: expiredDate
        )
        let expiredTurn = testTurn(startedAt: expiredDate, completedAt: expiredDate)
        let batch = testBatch(
            thread: expiredThread,
            turn: expiredTurn,
            input: testInput(),
            run: testRun(at: now)
        )

        let archive = try await repository.apply(batch, now: now)
        try await repository.record(
            observation: ActivityObservation(
                timestamp: expiredDate,
                intervalSeconds: 15,
                idleSeconds: 1,
                codexFocus: .focused
            ),
            now: now
        )

        #expect(archive.threads.isEmpty)
        #expect(archive.turns.isEmpty)
        #expect(archive.inputs.isEmpty)
        let afterExpiredObservation = try await repository.load()
        #expect(afterExpiredObservation.observationFacts.isEmpty)
    }

    @Test
    func activityObservationSplitsAcrossMinutesAndConservesAtMostSixtySeconds() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ActivityInsightsRepository(fileURL: directory.appendingPathComponent("archive.json"))

        try await repository.record(
            observation: ActivityObservation(
                timestamp: testDate(65),
                intervalSeconds: 10,
                idleSeconds: 30,
                codexFocus: .focused
            ),
            now: testDate(100)
        )

        var archive = try await repository.load()
        #expect(archive.activityMinutes["0"]?.observedSeconds == 5)
        #expect(archive.activityMinutes["60"]?.observedSeconds == 5)
        #expect(archive.activityMinutes["0"]?.activeWithinTwoMinutesSeconds == 5)
        #expect(archive.observationFacts.values.first?.userState == .active)
        #expect(archive.observationFacts.values.first?.codexFocus == .focused)

        try await repository.record(
            observation: ActivityObservation(
                timestamp: testDate(120),
                intervalSeconds: 60,
                idleSeconds: nil
            ),
            now: testDate(121)
        )
        try await repository.record(
            observation: ActivityObservation(
                timestamp: testDate(120),
                intervalSeconds: 60,
                idleSeconds: nil
            ),
            now: testDate(122)
        )

        archive = try await repository.load()
        let secondMinute = try #require(archive.activityMinutes["60"])
        #expect(secondMinute.observedSeconds == 5)
        #expect(secondMinute.unavailableSeconds == 55)
        #expect(secondMinute.observedSeconds + secondMinute.unavailableSeconds == 60)
    }

    @Test
    func persistedObservationContainsOnlyFocusClassification() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("archive.json")
        let repository = ActivityInsightsRepository(fileURL: file)

        _ = try await repository.record(
            observation: ActivityObservation(
                timestamp: testDate(1_200),
                intervalSeconds: 15,
                idleSeconds: 1,
                codexFocus: .notFocused
            ),
            now: testDate(1_200)
        )
        let archive = try await repository.load()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let stored = String(decoding: try encoder.encode(archive), as: UTF8.self)

        #expect(stored.contains("notFocused"))
        #expect(!stored.contains("bundleIdentifier"))
        #expect(!stored.contains("frontmostApplication"))
        #expect(!stored.contains("private.other-application.marker"))
    }

    @Test
    func collectorHeartbeatPersistsRunningCoverageAndGracefulStop() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ActivityInsightsRepository(fileURL: directory.appendingPathComponent("archive.json"))
        let sessionID = try await repository.startCollectorSession(
            expectedHeartbeatIntervalSeconds: 10,
            enabledSince: testDate(995),
            now: testDate(1_000)
        )

        _ = try await repository.record(
            observation: ActivityObservation(
                timestamp: testDate(1_010),
                intervalSeconds: 10,
                idleSeconds: 1
            ),
            heartbeatFor: sessionID,
            now: testDate(1_010)
        )
        let archive = try await repository.stopCollectorSession(
            sessionID: sessionID,
            reason: .disabled,
            now: testDate(1_020)
        )

        #expect(archive.collectorSessionCount == 1)
        #expect(archive.collectorState?.lastHeartbeatAt == testDate(1_020))
        #expect(archive.collectorState?.stoppedAt == testDate(1_020))
        #expect(archive.collectorState?.stopReason == .disabled)
        #expect(archive.collectorCoverageMinutes.values.reduce(0) {
            $0 + $1.runningSeconds
        } == 20)
        #expect(archive.collectorCoverageMinutes.values.reduce(0) {
            $0 + $1.unknownSeconds
        } == 0)
    }

    @Test
    func longHeartbeatGapIsUnknownInsteadOfRunning() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ActivityInsightsRepository(fileURL: directory.appendingPathComponent("archive.json"))
        let sessionID = try await repository.startCollectorSession(
            expectedHeartbeatIntervalSeconds: 10,
            enabledSince: testDate(1_000),
            now: testDate(1_000)
        )
        _ = try await repository.record(
            observation: ActivityObservation(
                timestamp: testDate(1_010),
                intervalSeconds: 10,
                idleSeconds: 1
            ),
            heartbeatFor: sessionID,
            now: testDate(1_010)
        )

        try await repository.record(
            observation: ActivityObservation(
                timestamp: testDate(1_100),
                intervalSeconds: 10,
                idleSeconds: 1
            ),
            heartbeatFor: sessionID,
            now: testDate(1_100)
        )

        let archive = try await repository.load()
        #expect(archive.collectorCoverageMinutes.values.reduce(0) {
            $0 + $1.runningSeconds
        } == 20)
        #expect(archive.collectorCoverageMinutes.values.reduce(0) {
            $0 + $1.unknownSeconds
        } == 80)
        let report = ActivityInsightsAuditor.audit(
            archive,
            now: testDate(1_100),
            collectorExpectedSince: testDate(1_000)
        )
        #expect(report.collectorHeartbeatFresh == true)
        #expect(report.collectorCoveragePercent == 20)
    }

    @Test
    func restartQuarantinesUnobservedTimeFromInterruptedSession() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ActivityInsightsRepository(fileURL: directory.appendingPathComponent("archive.json"))
        let firstSession = try await repository.startCollectorSession(
            expectedHeartbeatIntervalSeconds: 10,
            enabledSince: testDate(1_000),
            now: testDate(1_000)
        )
        _ = try await repository.record(
            observation: ActivityObservation(
                timestamp: testDate(1_010),
                intervalSeconds: 10,
                idleSeconds: 1
            ),
            heartbeatFor: firstSession,
            now: testDate(1_010)
        )

        let secondSession = try await repository.startCollectorSession(
            expectedHeartbeatIntervalSeconds: 10,
            enabledSince: testDate(1_000),
            now: testDate(1_100)
        )
        let archive = try await repository.load()

        #expect(secondSession != firstSession)
        #expect(archive.collectorSessionCount == 2)
        #expect(archive.collectorCoverageMinutes.values.reduce(0) {
            $0 + $1.runningSeconds
        } == 20)
        #expect(archive.collectorCoverageMinutes.values.reduce(0) {
            $0 + $1.unknownSeconds
        } == 80)
    }
}
