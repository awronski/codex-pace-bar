import CodexActivityInsightsCore
import Foundation
import Testing

@Suite
struct ActivityInsightsValidatorTests {
    @Test
    func controlledTruthSetPassesOnlyWhenOriginTimeAndLengthMatch() throws {
        let thread = testThread()
        let turn = testTurn()
        let input = testInput(characters: 12, bytes: 14)
        let archive = ActivityInsightsArchive(
            threads: [thread.threadID: thread],
            turns: [turn.key: turn],
            inputs: [input.key: input],
            historyAttemptVersions: [thread.threadID: thread.sourceUpdatedAt],
            historySyncVersions: [thread.threadID: thread.sourceUpdatedAt],
            observationFacts: [
                ActivityObservationFact.key(intervalEnd: testDate(1_210)): ActivityObservationFact(
                    intervalStart: testDate(1_190),
                    intervalEnd: testDate(1_210),
                    userState: .active,
                    codexFocus: .focused
                )
            ],
            collectorCoverageMinutes: [
                "1200": ActivityCollectorCoverageMinuteFact(
                    minuteStart: testDate(1_200),
                    runningSeconds: 60
                )
            ],
            collectorState: ActivityCollectorState(
                startedAt: testDate(1_190),
                lastHeartbeatAt: testDate(1_300),
                expectedHeartbeatIntervalSeconds: 10
            ),
            collectorSessionCount: 1
        )
        let manifest = ActivityValidationManifest(cases: [validationCase()])

        let report = try ActivityInsightsValidator.validate(
            archive: archive,
            manifest: manifest,
            requirements: .init(
                minimumCases: 1,
                minimumDistinctWorkDays: 1,
                minimumOriginCoveragePercent: 100,
                minimumHistorySyncCoveragePercent: 100,
                minimumCodexFocusCoveragePercent: 100,
                minimumFourStateCoveragePercent: 100,
                minimumStateCases: 0,
                minimumStateWorkDays: 0,
                minimumStateIntervalCoveragePercent: 0
            ),
            now: testDate(1_300),
            windowStart: testDate(900),
            collectorExpectedSince: testDate(1_190)
        )

        #expect(report.isReady)
        #expect(report.cases.count == 1)
        #expect(report.cases[0].caseID == "user-direct-1")
        #expect(report.cases[0].passed)
        #expect(report.cases[0].mismatches.isEmpty)
        #expect(report.gates.allSatisfy { $0.passed })
    }

    @Test
    func controlledMismatchNamesFieldsWithoutPersistingPromptContent() throws {
        let thread = testThread(actor: .codex, mechanism: .subagentSpawn)
        let turn = testTurn()
        let input = testInput(actor: .codex, characters: 99, bytes: 99)
        let archive = ActivityInsightsArchive(
            threads: [thread.threadID: thread],
            turns: [turn.key: turn],
            inputs: [input.key: input],
            historySyncVersions: [thread.threadID: thread.sourceUpdatedAt]
        )

        let report = try ActivityInsightsValidator.validate(
            archive: archive,
            manifest: .init(cases: [validationCase()]),
            requirements: .init(
                minimumCases: 1,
                minimumDistinctWorkDays: 1,
                minimumOriginCoveragePercent: 0,
                minimumHistorySyncCoveragePercent: 0,
                minimumCodexFocusCoveragePercent: 0,
                minimumFourStateCoveragePercent: 0,
                requireFreshHeartbeat: false,
                minimumStateCases: 0,
                minimumStateWorkDays: 0,
                minimumStateIntervalCoveragePercent: 0
            ),
            now: testDate(1_300)
        )

        #expect(!report.isReady)
        #expect(report.cases[0].mismatches == [
            "creation_mechanism",
            "text_characters",
            "thread_actor",
            "utf8_bytes"
        ])
        #expect(report.gates.first { $0.code == "controlled_case_accuracy" }?.passed == false)
    }

    @Test
    func controlledStateCaseValidatesUserCodexFocusAndCoverage() throws {
        let thread = testThread(updatedAt: testDate(1_100), recencyAt: testDate(1_100))
        let turn = testTurn(
            startedAt: testDate(1_002),
            completedAt: testDate(1_008),
            durationMilliseconds: 6_000
        )
        let observation = ActivityObservationFact(
            intervalStart: testDate(1_000),
            intervalEnd: testDate(1_010),
            userState: .active,
            codexFocus: .focused
        )
        let stateCase = ActivityStateValidationCase(
            caseID: "active-working-focused",
            workDate: "1970-01-01",
            intervalStart: testDate(1_002),
            intervalEnd: testDate(1_008),
            expectedUserState: .active,
            expectedCodexState: .working,
            expectedFocusState: .focused,
            toleranceSeconds: 0
        )
        let archive = ActivityInsightsArchive(
            threads: [thread.threadID: thread],
            turns: [turn.key: turn],
            inputs: [testInput().key: testInput()],
            historySyncVersions: [thread.threadID: thread.sourceUpdatedAt],
            observationFacts: [observation.key: observation],
            collectorState: ActivityCollectorState(
                startedAt: testDate(1_000),
                lastHeartbeatAt: testDate(1_008),
                expectedHeartbeatIntervalSeconds: 10
            )
        )

        let report = try ActivityInsightsValidator.validate(
            archive: archive,
            manifest: .init(cases: [validationCase()], stateCases: [stateCase]),
            requirements: .init(
                minimumCases: 1,
                minimumDistinctWorkDays: 1,
                minimumOriginCoveragePercent: 0,
                minimumHistorySyncCoveragePercent: 0,
                minimumCodexFocusCoveragePercent: 0,
                minimumFourStateCoveragePercent: 0,
                requireFreshHeartbeat: false,
                minimumStateCases: 1,
                minimumStateWorkDays: 1,
                minimumStateIntervalCoveragePercent: 100
            ),
            now: testDate(1_010)
        )

        #expect(report.stateCases == [ActivityStateValidationCaseResult(
            caseID: "active-working-focused",
            passed: true,
            observedCoveragePercent: 100,
            mismatches: []
        )])
        #expect(report.gates.first { $0.code == "controlled_state_accuracy" }?.passed == true)
        #expect(!report.gates.contains { $0.code == "collector_coverage" })
    }

    @Test
    func controlledStateMismatchNamesOnlyStateDimensions() throws {
        let observation = ActivityObservationFact(
            intervalStart: testDate(1_000),
            intervalEnd: testDate(1_010),
            userState: .active,
            codexFocus: .focused
        )
        let stateCase = ActivityStateValidationCase(
            caseID: "mismatch",
            workDate: "1970-01-01",
            intervalStart: testDate(1_000),
            intervalEnd: testDate(1_010),
            expectedUserState: .inactive,
            expectedCodexState: .working,
            expectedFocusState: .notFocused,
            toleranceSeconds: 0
        )
        let report = try ActivityInsightsValidator.validate(
            archive: .init(observationFacts: [observation.key: observation]),
            manifest: .init(cases: [validationCase()], stateCases: [stateCase]),
            requirements: .init(
                minimumCases: 1,
                minimumDistinctWorkDays: 1,
                minimumOriginCoveragePercent: 0,
                minimumHistorySyncCoveragePercent: 0,
                minimumCodexFocusCoveragePercent: 0,
                minimumFourStateCoveragePercent: 0,
                requireFreshHeartbeat: false,
                minimumStateCases: 1,
                minimumStateWorkDays: 1,
                minimumStateIntervalCoveragePercent: 100
            ),
            now: testDate(1_010)
        )

        #expect(report.stateCases[0].mismatches == ["codex_state", "focus_state", "user_state"])
        #expect(!report.isReady)
    }

    @Test
    func duplicateOrUndersizedManifestCannotPass() throws {
        let sample = validationCase()
        let report = try ActivityInsightsValidator.validate(
            archive: .init(),
            manifest: .init(cases: [sample, sample]),
            requirements: .init(
                minimumCases: 3,
                minimumDistinctWorkDays: 2,
                minimumOriginCoveragePercent: 0,
                minimumHistorySyncCoveragePercent: 0,
                minimumCodexFocusCoveragePercent: 0,
                minimumFourStateCoveragePercent: 0,
                requireFreshHeartbeat: false,
                minimumStateCases: 0,
                minimumStateWorkDays: 0,
                minimumStateIntervalCoveragePercent: 0
            ),
            now: testDate(1_300)
        )

        #expect(report.gates.first { $0.code == "controlled_sample_size" }?.passed == false)
        #expect(report.gates.first { $0.code == "controlled_work_days" }?.passed == false)
        #expect(report.gates.first { $0.code == "unique_controlled_cases" }?.passed == false)
    }

    @Test
    func duplicateStateIntervalsCannotCountAsIndependentControlledCases() throws {
        let first = stateValidationCase(id: "state-1")
        let second = stateValidationCase(id: "state-2")
        let report = try ActivityInsightsValidator.validate(
            archive: .init(),
            manifest: .init(cases: [validationCase()], stateCases: [first, second]),
            requirements: .init(
                minimumCases: 1,
                minimumDistinctWorkDays: 1,
                minimumOriginCoveragePercent: 0,
                minimumHistorySyncCoveragePercent: 0,
                minimumCodexFocusCoveragePercent: 0,
                minimumFourStateCoveragePercent: 0,
                requireFreshHeartbeat: false,
                minimumStateCases: 2,
                minimumStateWorkDays: 1,
                minimumStateIntervalCoveragePercent: 0
            ),
            now: testDate(1_300)
        )

        #expect(report.gates.first { $0.code == "unique_controlled_state_cases" }?.passed == false)
    }

    @Test
    func repetitiveStateCasesCannotSatisfyFourStateOrWorkingFocusCoverage() throws {
        let observations = (0..<4).map { index in
            ActivityObservationFact(
                intervalStart: testDate(1_000 + Double(index * 20)),
                intervalEnd: testDate(1_010 + Double(index * 20)),
                userState: .active,
                codexFocus: .focused
            )
        }
        let stateCases = observations.enumerated().map { index, observation in
            ActivityStateValidationCase(
                caseID: "repeated-\(index)",
                workDate: "1970-01-01",
                intervalStart: observation.intervalStart,
                intervalEnd: observation.intervalEnd,
                expectedUserState: .active,
                expectedCodexState: .idle,
                expectedFocusState: .focused,
                toleranceSeconds: 0
            )
        }
        let archive = ActivityInsightsArchive(
            observationFacts: Dictionary(uniqueKeysWithValues: observations.map { ($0.key, $0) })
        )

        let report = try ActivityInsightsValidator.validate(
            archive: archive,
            manifest: .init(cases: [validationCase()], stateCases: stateCases),
            requirements: stateRequirements(minimumCases: 4),
            now: testDate(1_100)
        )

        #expect(report.stateCases.allSatisfy { $0.passed })
        #expect(report.gates.first { $0.code == "controlled_four_state_combinations" }?.passed == false)
        #expect(report.gates.first { $0.code == "controlled_working_focus_states" }?.passed == false)
    }

    @Test
    func diversePassingStateCasesCoverFourStatesAndWorkingFocus() throws {
        let definitions: [(ActivityUserState, ActivityCodexWorkState, ActivityCodexFocusState)] = [
            (.active, .working, .focused),
            (.active, .idle, .notFocused),
            (.inactive, .working, .notFocused),
            (.inactive, .idle, .focused)
        ]
        let observations = definitions.enumerated().map { index, definition in
            ActivityObservationFact(
                intervalStart: testDate(1_000 + Double(index * 20)),
                intervalEnd: testDate(1_010 + Double(index * 20)),
                userState: definition.0,
                codexFocus: definition.2
            )
        }
        let thread = testThread(updatedAt: testDate(1_100), recencyAt: testDate(1_100))
        let firstTurn = testTurn(
            turnID: "working-1",
            startedAt: observations[0].intervalStart,
            completedAt: observations[0].intervalEnd,
            durationMilliseconds: 10_000
        )
        let secondTurn = testTurn(
            turnID: "working-2",
            startedAt: observations[2].intervalStart,
            completedAt: observations[2].intervalEnd,
            durationMilliseconds: 10_000
        )
        let stateCases = zip(observations, definitions).enumerated().map { index, item in
            ActivityStateValidationCase(
                caseID: "diverse-\(index)",
                workDate: "1970-01-01",
                intervalStart: item.0.intervalStart,
                intervalEnd: item.0.intervalEnd,
                expectedUserState: item.1.0,
                expectedCodexState: item.1.1,
                expectedFocusState: item.1.2,
                toleranceSeconds: 0
            )
        }
        let archive = ActivityInsightsArchive(
            threads: [thread.threadID: thread],
            turns: [firstTurn.key: firstTurn, secondTurn.key: secondTurn],
            observationFacts: Dictionary(uniqueKeysWithValues: observations.map { ($0.key, $0) })
        )

        let report = try ActivityInsightsValidator.validate(
            archive: archive,
            manifest: .init(cases: [validationCase()], stateCases: stateCases),
            requirements: stateRequirements(minimumCases: 4),
            now: testDate(1_100)
        )

        #expect(report.stateCases.allSatisfy { $0.passed })
        #expect(report.gates.first { $0.code == "controlled_four_state_combinations" }?.passed == true)
        #expect(report.gates.first { $0.code == "controlled_working_focus_states" }?.passed == true)
    }

    @Test
    func declaredWorkDateMustBeUtcDateOfMeasuredTimestamp() {
        let invalid = ActivityValidationCase(
            caseID: "wrong-date",
            workDate: "2026-08-18",
            threadID: "thread-1",
            turnID: "turn-1",
            inputItemID: "input-1",
            expectedActor: .user,
            expectedMechanism: .interactive,
            expectedInputKind: .initialTask,
            expectedSubmittedAt: testDate(1_200),
            expectedTextCharacters: 12,
            expectedUTF8Bytes: 14
        )

        #expect(throws: ActivityInsightsError.self) {
            _ = try ActivityInsightsValidator.validate(
                archive: .init(),
                manifest: .init(cases: [invalid]),
                requirements: .init(
                    minimumCases: 1,
                    minimumDistinctWorkDays: 1,
                    minimumOriginCoveragePercent: 0,
                    minimumHistorySyncCoveragePercent: 0,
                    minimumCodexFocusCoveragePercent: 0,
                    minimumFourStateCoveragePercent: 0,
                    requireFreshHeartbeat: false,
                    minimumStateCases: 0,
                    minimumStateWorkDays: 0,
                    minimumStateIntervalCoveragePercent: 0
                )
            )
        }
    }

    @Test
    func validationCandidatesContainOnlySanitizedIdsAndMeasurements() throws {
        let thread = testThread()
        let input = testInput(
            itemID: "recent-input",
            submittedAtEstimate: testDate(1_200),
            characters: 17,
            bytes: 19
        )
        let oldInput = testInput(
            itemID: "old-input",
            submittedAtEstimate: testDate(800),
            characters: 99,
            bytes: 99
        )
        let archive = ActivityInsightsArchive(
            threads: [thread.threadID: thread],
            turns: [testTurn().key: testTurn()],
            inputs: [input.key: input, oldInput.key: oldInput]
        )

        let candidates = ActivityInsightsValidator.candidates(
            archive: archive,
            windowStart: testDate(900)
        )
        let encoded = String(decoding: try JSONEncoder().encode(candidates), as: UTF8.self)

        #expect(candidates.count == 1)
        #expect(candidates[0].actor == .user)
        #expect(candidates[0].textCharacters == 17)
        #expect(candidates[0].utf8Bytes == 19)
        #expect(!encoded.contains("content"))
        #expect(!encoded.contains("prompt"))
        #expect(!encoded.contains("text\""))
    }

    @Test
    func failureCandidatesExposeOnlyCurrentQuarantinedVersions() {
        let failed = testThread(id: "failed", updatedAt: testDate(1_100), recencyAt: testDate(1_200))
        let recovered = testThread(id: "recovered", updatedAt: testDate(1_200), recencyAt: testDate(1_300))
        let archive = ActivityInsightsArchive(
            threads: [failed.threadID: failed, recovered.threadID: recovered],
            historyFailureVersions: [
                failed.threadID: failed.sourceUpdatedAt,
                recovered.threadID: testDate(1_100)
            ]
        )

        let candidates = ActivityInsightsValidator.failureCandidates(
            archive: archive,
            windowStart: testDate(1_000)
        )

        #expect(candidates.count == 1)
        #expect(candidates[0].threadID == "failed")
        #expect(candidates[0].actor == .user)
        #expect(candidates[0].sourceUpdatedAt == testDate(1_100))
    }

    @Test
    func invalidControlledMeasurementsFailClosed() {
        let invalid = ActivityValidationCase(
            caseID: "invalid",
            workDate: "2026-08-08",
            threadID: "thread-1",
            turnID: "turn-1",
            expectedActor: .user,
            expectedMechanism: .interactive,
            expectedInputKind: .initialTask,
            expectedSubmittedAt: testDate(1_200),
            timestampToleranceSeconds: -1,
            expectedTextCharacters: 10,
            expectedUTF8Bytes: 9
        )

        #expect(throws: ActivityInsightsError.self) {
            _ = try ActivityInsightsValidator.validate(
                archive: .init(),
                manifest: .init(cases: [invalid]),
                requirements: .init(
                    minimumCases: 1,
                    minimumDistinctWorkDays: 1,
                    minimumOriginCoveragePercent: 0,
                    minimumHistorySyncCoveragePercent: 0,
                    minimumCodexFocusCoveragePercent: 0,
                    minimumFourStateCoveragePercent: 0,
                    requireFreshHeartbeat: false,
                    minimumStateCases: 0,
                    minimumStateWorkDays: 0,
                    minimumStateIntervalCoveragePercent: 0
                )
            )
        }
    }

    private func validationCase() -> ActivityValidationCase {
        ActivityValidationCase(
            caseID: "user-direct-1",
            workDate: "1970-01-01",
            threadID: "thread-1",
            turnID: "turn-1",
            inputItemID: "input-1",
            expectedActor: .user,
            expectedMechanism: .interactive,
            expectedInputKind: .initialTask,
            expectedSubmittedAt: testDate(1_200),
            expectedTextCharacters: 12,
            expectedUTF8Bytes: 14,
            expectedAttachmentCount: 0,
            expectedSkillCount: 0,
            expectedMentionCount: 0
        )
    }

    private func stateValidationCase(id: String) -> ActivityStateValidationCase {
        ActivityStateValidationCase(
            caseID: id,
            workDate: "1970-01-01",
            intervalStart: testDate(1_000),
            intervalEnd: testDate(1_010),
            expectedUserState: .active,
            expectedCodexState: .idle,
            expectedFocusState: .focused,
            toleranceSeconds: 0
        )
    }

    private func stateRequirements(minimumCases: Int) -> ActivityValidationRequirements {
        ActivityValidationRequirements(
            minimumCases: 1,
            minimumDistinctWorkDays: 1,
            minimumOriginCoveragePercent: 0,
            minimumHistorySyncCoveragePercent: 0,
            minimumCodexFocusCoveragePercent: 0,
            minimumFourStateCoveragePercent: 0,
            requireFreshHeartbeat: false,
            minimumStateCases: minimumCases,
            minimumStateWorkDays: 1,
            minimumStateIntervalCoveragePercent: 100
        )
    }
}
