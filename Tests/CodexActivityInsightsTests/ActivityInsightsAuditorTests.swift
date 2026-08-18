import CodexActivityInsightsCore
import Foundation
import Testing

@Suite
struct ActivityInsightsAuditorTests {
    @Test
    func validArchiveIsHealthyAndReportsOriginCoverage() {
        let user = testThread(id: "user")
        let codex = testThread(
            id: "codex",
            actor: .codex,
            mechanism: .subagentSpawn
        )
        let userTurn = testTurn(threadID: "user", turnID: "turn-user")
        let codexTurn = testTurn(threadID: "codex", turnID: "turn-codex", completedAt: nil, durationMilliseconds: nil, status: "inProgress")
        let userInput = testInput(threadID: "user", turnID: "turn-user")
        let archive = ActivityInsightsArchive(
            generatedAt: testDate(1_300),
            threads: [user.threadID: user, codex.threadID: codex],
            turns: [userTurn.key: userTurn, codexTurn.key: codexTurn],
            inputs: [userInput.key: userInput],
            historyAttemptVersions: [
                user.threadID: user.sourceUpdatedAt,
                codex.threadID: codex.sourceUpdatedAt
            ],
            historySyncVersions: [
                user.threadID: user.sourceUpdatedAt,
                codex.threadID: codex.sourceUpdatedAt
            ],
            activityMinutes: [
                "1200": ActivityMinuteFact(
                    minuteStart: testDate(1_200),
                    observedSeconds: 30,
                    activeWithinTwoMinutesSeconds: 10,
                    activeWithinFiveMinutesSeconds: 20,
                    activeWithinTenMinutesSeconds: 30,
                    unavailableSeconds: 30
                )
            ],
            collectionRuns: [testRun()]
        )

        let report = ActivityInsightsAuditor.audit(archive, now: testDate(2_000))

        #expect(report.isHealthy)
        #expect(report.issues.isEmpty)
        #expect(report.knownOriginThreads == 2)
        #expect(report.originCoveragePercent == 100)
        #expect(report.actorCounts == ["user": 1, "codex": 1])
        #expect(report.provisionalTurns == 1)
        #expect(report.historySyncCoveragePercent == 100)
        #expect(report.inputKindCounts == ["initialTask": 1])
        #expect(report.averageInputCharacters == 12)
        #expect(report.inputCharacterTotalsByActor == ["user": 12])
        #expect(report.averageInputCharactersByActor == ["user": 12])
        #expect(report.completedTurnDurationSeconds == 2)
        #expect(report.activityObservedSeconds == 30)
        #expect(report.activityUnavailableSeconds == 30)
    }

    @Test
    func alignedObservationsProduceFourStatesAndUnionConcurrentCodexWork() {
        let thread = testThread(updatedAt: testDate(1_050), recencyAt: testDate(1_050))
        let firstTurn = testTurn(
            turnID: "turn-1",
            startedAt: testDate(1_002),
            completedAt: testDate(1_008),
            durationMilliseconds: 6_000
        )
        let overlappingTurn = testTurn(
            turnID: "turn-2",
            startedAt: testDate(1_005),
            completedAt: testDate(1_015),
            durationMilliseconds: 10_000
        )
        let provisionalTurn = testTurn(
            turnID: "turn-3",
            startedAt: testDate(1_035),
            completedAt: nil,
            durationMilliseconds: nil,
            status: "inProgress"
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
            ),
            ActivityObservationFact(
                intervalStart: testDate(1_030),
                intervalEnd: testDate(1_040),
                userState: .active,
                codexFocus: .focused
            )
        ]
        let archive = ActivityInsightsArchive(
            threads: [thread.threadID: thread],
            turns: Dictionary(uniqueKeysWithValues: [firstTurn, overlappingTurn, provisionalTurn].map {
                ($0.key, $0)
            }),
            historyAttemptVersions: [thread.threadID: thread.sourceUpdatedAt],
            historySyncVersions: [thread.threadID: thread.sourceUpdatedAt],
            observationFacts: Dictionary(uniqueKeysWithValues: observations.map { ($0.key, $0) })
        )

        let report = ActivityInsightsAuditor.audit(archive, now: testDate(1_040))

        #expect(report.isHealthy)
        #expect(report.observationFactCount == 4)
        #expect(report.observationSeconds == 40)
        #expect(report.codexFocusedSeconds == 20)
        #expect(report.codexNotFocusedSeconds == 10)
        #expect(report.codexFocusUnknownSeconds == 10)
        #expect(report.codexFocusCoveragePercent == 100)
        #expect(report.activeCodexWorkingSeconds == 8)
        #expect(report.activeCodexIdleSeconds == 7)
        #expect(report.inactiveCodexWorkingSeconds == 5)
        #expect(report.inactiveCodexIdleSeconds == 5)
        #expect(report.activeCodexUnknownSeconds == 5)
        #expect(report.inactiveCodexUnknownSeconds == 0)
        #expect(report.unknownUserStateSeconds == 10)
        #expect(report.fourStateUnknownSeconds == 15)
        #expect(report.fourStateCoveragePercent == 62.5)
        #expect(report.codexWorkingFocusedSeconds == 8)
        #expect(report.codexWorkingNotFocusedSeconds == 5)
        #expect(report.codexWorkingFocusUnknownSeconds == 0)
        #expect(report.provisionalTurns == 1)
    }

    @Test
    func completedCodexWorkDuringSamplingGapIsRetainedWithUnknownUserAndFocusState() {
        let thread = testThread(updatedAt: testDate(1_020), recencyAt: testDate(1_020))
        let turn = testTurn(
            startedAt: testDate(1_002),
            completedAt: testDate(1_012),
            durationMilliseconds: 10_000
        )
        let observation = ActivityObservationFact(
            intervalStart: testDate(1_000),
            intervalEnd: testDate(1_005),
            userState: .active,
            codexFocus: .focused
        )
        let archive = ActivityInsightsArchive(
            threads: [thread.threadID: thread],
            turns: [turn.key: turn],
            historySyncVersions: [thread.threadID: thread.sourceUpdatedAt],
            observationFacts: [observation.key: observation]
        )

        let report = ActivityInsightsAuditor.audit(
            archive,
            now: testDate(1_020),
            windowStart: testDate(1_000)
        )

        #expect(report.activeCodexWorkingSeconds == 3)
        #expect(report.unknownUserCodexWorkingSeconds == 7)
        #expect(report.codexWorkingFocusedSeconds == 3)
        #expect(report.codexWorkingFocusUnknownSeconds == 7)
        #expect(abs(report.fourStateCoveragePercent - (500.0 / 12.0)) < 0.001)
        #expect(report.codexFocusCoveragePercent == 30)
    }

    @Test
    func completedCodexWorkWithoutAnySamplesIsUnknownRatherThanMissing() {
        let thread = testThread(updatedAt: testDate(1_020), recencyAt: testDate(1_020))
        let turn = testTurn(
            startedAt: testDate(1_002),
            completedAt: testDate(1_012),
            durationMilliseconds: 10_000
        )
        let archive = ActivityInsightsArchive(
            threads: [thread.threadID: thread],
            turns: [turn.key: turn],
            historySyncVersions: [thread.threadID: thread.sourceUpdatedAt]
        )

        let report = ActivityInsightsAuditor.audit(
            archive,
            now: testDate(1_020),
            windowStart: testDate(1_000)
        )

        #expect(report.unknownUserCodexWorkingSeconds == 10)
        #expect(report.codexWorkingFocusUnknownSeconds == 10)
        #expect(report.fourStateCoveragePercent == 0)
        #expect(report.codexFocusCoveragePercent == 0)
    }

    @Test
    func interruptedTurnWithoutCompletionStopsBeingUnknownAtThreadUpdate() {
        let thread = testThread(
            updatedAt: testDate(995),
            recencyAt: testDate(1_010)
        )
        let interrupted = testTurn(
            startedAt: testDate(990),
            completedAt: nil,
            durationMilliseconds: nil,
            status: "interrupted"
        )
        let observation = ActivityObservationFact(
            intervalStart: testDate(1_000),
            intervalEnd: testDate(1_010),
            userState: .active,
            codexFocus: .focused
        )
        let archive = ActivityInsightsArchive(
            threads: [thread.threadID: thread],
            turns: [interrupted.key: interrupted],
            historyAttemptVersions: [thread.threadID: thread.sourceUpdatedAt],
            historySyncVersions: [thread.threadID: thread.sourceUpdatedAt],
            observationFacts: [observation.key: observation]
        )

        let report = ActivityInsightsAuditor.audit(archive, now: testDate(1_010))

        #expect(report.isHealthy)
        #expect(report.activeCodexWorkingSeconds == 0)
        #expect(report.activeCodexIdleSeconds == 10)
        #expect(report.fourStateUnknownSeconds == 0)
        #expect(report.fourStateCoveragePercent == 100)
    }

    @Test
    func windowedMetricsExcludeOlderFactsButKeepWholeArchiveIntegrityChecks() {
        let old = testThread(id: "old", updatedAt: testDate(100), recencyAt: testDate(100))
        let recent = testThread(id: "recent", updatedAt: testDate(1_900), recencyAt: testDate(1_900))
        let oldTurn = testTurn(
            threadID: "recent",
            turnID: "old-turn",
            startedAt: testDate(1_000),
            completedAt: testDate(1_002)
        )
        let recentTurn = testTurn(
            threadID: "recent",
            turnID: "recent-turn",
            startedAt: testDate(1_900),
            completedAt: testDate(1_902)
        )
        let oldThreadTurn = testTurn(
            threadID: "old",
            turnID: "recent-event-on-old-thread",
            startedAt: testDate(1_900),
            completedAt: testDate(1_902)
        )
        let oldInput = testInput(
            threadID: "recent",
            turnID: "old-turn",
            itemID: "old-input",
            submittedAtEstimate: testDate(1_000),
            characters: 99,
            bytes: 99
        )
        let recentInput = testInput(
            threadID: "recent",
            turnID: "recent-turn",
            itemID: "recent-input",
            submittedAtEstimate: testDate(1_900)
        )
        let oldThreadInput = testInput(
            threadID: "old",
            turnID: "recent-event-on-old-thread",
            itemID: "recent-input-on-old-thread",
            submittedAtEstimate: testDate(1_900),
            characters: 77,
            bytes: 77
        )
        let archive = ActivityInsightsArchive(
            threads: [old.threadID: old, recent.threadID: recent],
            turns: [
                oldTurn.key: oldTurn,
                recentTurn.key: recentTurn,
                oldThreadTurn.key: oldThreadTurn
            ],
            inputs: [
                oldInput.key: oldInput,
                recentInput.key: recentInput,
                oldThreadInput.key: oldThreadInput
            ],
            historySyncVersions: [recent.threadID: recent.sourceUpdatedAt],
            historyFailureVersions: [old.threadID: old.sourceUpdatedAt]
        )

        let report = ActivityInsightsAuditor.audit(
            archive,
            now: testDate(2_000),
            windowStart: testDate(1_800)
        )

        #expect(report.windowStart == testDate(1_800))
        #expect(report.threadCount == 1)
        #expect(report.turnCount == 1)
        #expect(report.inputCount == 1)
        #expect(report.averageInputCharacters == 12)
        #expect(report.completedTurnDurationSeconds == 2)
        #expect(report.historySyncedThreads == 1)
        #expect(report.knownFailedThreadVersions == 0)
        #expect(report.historySyncCoveragePercent == 100)
        #expect(report.issues.isEmpty)
    }

    @Test
    func windowedCompletedDurationIsClippedAtTheBoundary() {
        let thread = testThread(
            id: "crossing",
            updatedAt: testDate(1_900),
            recencyAt: testDate(1_900)
        )
        let turn = testTurn(
            threadID: thread.threadID,
            turnID: "crossing-turn",
            startedAt: testDate(1_795),
            completedAt: testDate(1_805),
            durationMilliseconds: 10_000
        )
        let archive = ActivityInsightsArchive(
            threads: [thread.threadID: thread],
            turns: [turn.key: turn],
            historySyncVersions: [thread.threadID: thread.sourceUpdatedAt]
        )

        let report = ActivityInsightsAuditor.audit(
            archive,
            now: testDate(2_000),
            windowStart: testDate(1_800)
        )

        #expect(report.turnCount == 1)
        #expect(report.completedTurnDurationSeconds == 5)
    }

    @Test
    func invalidArchiveSurfacesStructuralTimingAndAccountingProblems() {
        let unknown = testThread(id: "unknown", actor: .unknown, mechanism: .unknown, confidence: .unknown)
        let invalidTurn = testTurn(
            threadID: "missing-thread",
            turnID: "bad-turn",
            startedAt: testDate(10_000),
            completedAt: testDate(9_000),
            durationMilliseconds: -10
        )
        let orphanInput = ActivityInputFact(
            threadID: "missing-thread",
            turnID: "missing-turn",
            itemID: "bad-input",
            ordinal: 0,
            actor: .unknown,
            kind: .initialTask,
            submittedAtEstimate: testDate(1_000),
            textCharacters: -1,
            utf8Bytes: 0,
            attachmentCount: 0,
            skillCount: 0,
            mentionCount: 0
        )
        let invalidMinute = ActivityMinuteFact(
            minuteStart: testDate(1_200),
            observedSeconds: 50,
            activeWithinTwoMinutesSeconds: 51,
            activeWithinFiveMinutesSeconds: 40,
            activeWithinTenMinutesSeconds: 30,
            unavailableSeconds: 20
        )
        let invalidObservation = ActivityObservationFact(
            intervalStart: testDate(1_200),
            intervalEnd: testDate(1_261),
            userState: .active,
            codexFocus: .focused
        )
        let archive = ActivityInsightsArchive(
            generatedAt: testDate(2_000),
            threads: ["wrong-thread-key": unknown],
            turns: ["wrong-turn-key": invalidTurn],
            inputs: ["wrong-input-key": orphanInput],
            activityMinutes: ["1200": invalidMinute],
            observationFacts: [invalidObservation.key: invalidObservation],
            collectionRuns: [testRun(failures: 3)]
        )

        let report = ActivityInsightsAuditor.audit(archive, now: testDate(2_000))
        let issues = Dictionary(uniqueKeysWithValues: report.issues.map { ($0.code, $0) })

        #expect(!report.isHealthy)
        #expect(issues["orphan_turn"]?.severity == .error)
        #expect(issues["orphan_input"]?.severity == .error)
        #expect(issues["thread_key_mismatch"]?.severity == .error)
        #expect(issues["turn_key_mismatch"]?.severity == .error)
        #expect(issues["input_key_mismatch"]?.severity == .error)
        #expect(issues["invalid_turn_time"]?.severity == .error)
        #expect(issues["future_turn"]?.severity == .error)
        #expect(issues["invalid_input_measurement"]?.severity == .error)
        #expect(issues["invalid_activity_minute"]?.severity == .error)
        #expect(issues["invalid_observation_fact"]?.severity == .error)
        #expect(issues["thread_collection_failure"]?.count == 3)
        #expect(issues["unknown_thread_origin"]?.severity == .warning)
    }

    @Test
    func roundedTimestampDifferenceIsWarningNotCorruption() {
        let thread = testThread()
        let turn = testTurn(
            startedAt: testDate(1_200),
            completedAt: testDate(1_210),
            durationMilliseconds: 2_000
        )
        let archive = ActivityInsightsArchive(
            threads: [thread.threadID: thread],
            turns: [turn.key: turn],
            historyAttemptVersions: [thread.threadID: thread.sourceUpdatedAt],
            historySyncVersions: [thread.threadID: thread.sourceUpdatedAt]
        )

        let report = ActivityInsightsAuditor.audit(archive, now: testDate(2_000))

        #expect(report.isHealthy)
        #expect(report.issues == [ActivityAuditIssue(
            severity: .warning,
            code: "turn_duration_mismatch",
            count: 1,
            message: "Turn duration differs from rounded start and completion timestamps by more than 1.5 seconds."
        )])
    }

    @Test
    func enabledCollectorWithOldHeartbeatReportsDynamicUnknownCoverage() {
        let state = ActivityCollectorState(
            startedAt: testDate(1_000),
            lastHeartbeatAt: testDate(1_010),
            expectedHeartbeatIntervalSeconds: 10
        )
        let archive = ActivityInsightsArchive(
            collectorCoverageMinutes: [
                "960": ActivityCollectorCoverageMinuteFact(
                    minuteStart: testDate(960),
                    runningSeconds: 10
                )
            ],
            collectorState: state,
            collectorSessionCount: 1
        )

        let report = ActivityInsightsAuditor.audit(
            archive,
            now: testDate(1_100),
            windowStart: testDate(900),
            collectorExpectedSince: testDate(1_000)
        )

        #expect(report.collectorHeartbeatFresh == false)
        #expect(report.collectorHeartbeatAgeSeconds == 90)
        #expect(report.collectorRunningSeconds == 10)
        #expect(report.collectorUnknownSeconds == 80)
        #expect(report.collectorCoveragePercent == 100.0 / 9.0)
        #expect(report.issues.contains { $0.code == "collector_heartbeat_stale" })
    }
}
