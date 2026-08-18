import Foundation

public struct ActivityValidationManifest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let cases: [ActivityValidationCase]
    public let stateCases: [ActivityStateValidationCase]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        cases: [ActivityValidationCase],
        stateCases: [ActivityStateValidationCase] = []
    ) {
        self.schemaVersion = schemaVersion
        self.cases = cases
        self.stateCases = stateCases
    }
}

public enum ActivityCodexWorkState: String, Codable, Sendable {
    case working
    case idle
    case unknown
}

public struct ActivityStateValidationCase: Codable, Equatable, Sendable {
    public let caseID: String
    public let workDate: String
    public let intervalStart: Date
    public let intervalEnd: Date
    public let expectedUserState: ActivityUserState
    public let expectedCodexState: ActivityCodexWorkState
    public let expectedFocusState: ActivityCodexFocusState
    public let toleranceSeconds: TimeInterval

    public init(
        caseID: String,
        workDate: String,
        intervalStart: Date,
        intervalEnd: Date,
        expectedUserState: ActivityUserState,
        expectedCodexState: ActivityCodexWorkState,
        expectedFocusState: ActivityCodexFocusState,
        toleranceSeconds: TimeInterval = 5
    ) {
        self.caseID = caseID
        self.workDate = workDate
        self.intervalStart = intervalStart
        self.intervalEnd = intervalEnd
        self.expectedUserState = expectedUserState
        self.expectedCodexState = expectedCodexState
        self.expectedFocusState = expectedFocusState
        self.toleranceSeconds = toleranceSeconds
    }
}

public struct ActivityValidationCase: Codable, Equatable, Sendable {
    public let caseID: String
    public let workDate: String
    public let threadID: String
    public let turnID: String
    public let inputItemID: String?
    public let inputOrdinal: Int
    public let expectedActor: ActivityThreadActor
    public let expectedMechanism: ActivityCreationMechanism
    public let expectedInputKind: ActivityInputKind
    public let expectedSubmittedAt: Date
    public let timestampToleranceSeconds: TimeInterval
    public let expectedTextCharacters: Int
    public let expectedUTF8Bytes: Int
    public let expectedAttachmentCount: Int?
    public let expectedSkillCount: Int?
    public let expectedMentionCount: Int?

    public init(
        caseID: String,
        workDate: String,
        threadID: String,
        turnID: String,
        inputItemID: String? = nil,
        inputOrdinal: Int = 0,
        expectedActor: ActivityThreadActor,
        expectedMechanism: ActivityCreationMechanism,
        expectedInputKind: ActivityInputKind,
        expectedSubmittedAt: Date,
        timestampToleranceSeconds: TimeInterval = 5,
        expectedTextCharacters: Int,
        expectedUTF8Bytes: Int,
        expectedAttachmentCount: Int? = nil,
        expectedSkillCount: Int? = nil,
        expectedMentionCount: Int? = nil
    ) {
        self.caseID = caseID
        self.workDate = workDate
        self.threadID = threadID
        self.turnID = turnID
        self.inputItemID = inputItemID
        self.inputOrdinal = inputOrdinal
        self.expectedActor = expectedActor
        self.expectedMechanism = expectedMechanism
        self.expectedInputKind = expectedInputKind
        self.expectedSubmittedAt = expectedSubmittedAt
        self.timestampToleranceSeconds = timestampToleranceSeconds
        self.expectedTextCharacters = expectedTextCharacters
        self.expectedUTF8Bytes = expectedUTF8Bytes
        self.expectedAttachmentCount = expectedAttachmentCount
        self.expectedSkillCount = expectedSkillCount
        self.expectedMentionCount = expectedMentionCount
    }
}

public struct ActivityValidationRequirements: Equatable, Sendable {
    public let minimumCases: Int
    public let minimumDistinctWorkDays: Int
    public let minimumOriginCoveragePercent: Double
    public let minimumHistorySyncCoveragePercent: Double
    public let minimumCodexFocusCoveragePercent: Double
    public let minimumFourStateCoveragePercent: Double
    public let requireFreshHeartbeat: Bool
    public let minimumStateCases: Int
    public let minimumStateWorkDays: Int
    public let minimumStateIntervalCoveragePercent: Double

    public init(
        minimumCases: Int = 20,
        minimumDistinctWorkDays: Int = 7,
        minimumOriginCoveragePercent: Double = 95,
        minimumHistorySyncCoveragePercent: Double = 95,
        minimumCodexFocusCoveragePercent: Double = 95,
        minimumFourStateCoveragePercent: Double = 95,
        requireFreshHeartbeat: Bool = true,
        minimumStateCases: Int = 20,
        minimumStateWorkDays: Int = 7,
        minimumStateIntervalCoveragePercent: Double = 95
    ) {
        self.minimumCases = minimumCases
        self.minimumDistinctWorkDays = minimumDistinctWorkDays
        self.minimumOriginCoveragePercent = minimumOriginCoveragePercent
        self.minimumHistorySyncCoveragePercent = minimumHistorySyncCoveragePercent
        self.minimumCodexFocusCoveragePercent = minimumCodexFocusCoveragePercent
        self.minimumFourStateCoveragePercent = minimumFourStateCoveragePercent
        self.requireFreshHeartbeat = requireFreshHeartbeat
        self.minimumStateCases = minimumStateCases
        self.minimumStateWorkDays = minimumStateWorkDays
        self.minimumStateIntervalCoveragePercent = minimumStateIntervalCoveragePercent
    }
}

public struct ActivityValidationGate: Codable, Equatable, Sendable {
    public let code: String
    public let passed: Bool
    public let actual: Double
    public let required: Double
    public let message: String
}

public struct ActivityValidationCaseResult: Codable, Equatable, Sendable {
    public let caseID: String
    public let passed: Bool
    public let mismatches: [String]
}

public struct ActivityStateValidationCaseResult: Codable, Equatable, Sendable {
    public let caseID: String
    public let passed: Bool
    public let observedCoveragePercent: Double
    public let mismatches: [String]

    public init(
        caseID: String,
        passed: Bool,
        observedCoveragePercent: Double,
        mismatches: [String]
    ) {
        self.caseID = caseID
        self.passed = passed
        self.observedCoveragePercent = observedCoveragePercent
        self.mismatches = mismatches
    }
}

public struct ActivityValidationReport: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let windowStart: Date?
    public let audit: ActivityAuditReport
    public let gates: [ActivityValidationGate]
    public let cases: [ActivityValidationCaseResult]
    public let stateCases: [ActivityStateValidationCaseResult]

    public var isReady: Bool { gates.allSatisfy(\.passed) }
}

public struct ActivityValidationCandidate: Codable, Equatable, Sendable {
    public let threadID: String
    public let turnID: String
    public let inputItemID: String
    public let inputOrdinal: Int
    public let actor: ActivityThreadActor
    public let mechanism: ActivityCreationMechanism
    public let inputKind: ActivityInputKind
    public let submittedAtEstimate: Date?
    public let textCharacters: Int
    public let utf8Bytes: Int
    public let attachmentCount: Int
    public let skillCount: Int
    public let mentionCount: Int
}

public struct ActivityHistoryFailureCandidate: Codable, Equatable, Sendable {
    public let threadID: String
    public let actor: ActivityThreadActor
    public let mechanism: ActivityCreationMechanism
    public let sourceRecencyAt: Date
    public let sourceUpdatedAt: Date
}

public enum ActivityInsightsValidator {
    public static func candidates(
        archive: ActivityInsightsArchive,
        windowStart: Date? = nil
    ) -> [ActivityValidationCandidate] {
        archive.inputs.values.compactMap { input in
            guard let thread = archive.threads[input.threadID] else { return nil }
            if let windowStart {
                guard let submittedAt = input.submittedAtEstimate,
                      submittedAt >= windowStart
                else {
                    return nil
                }
            }
            return ActivityValidationCandidate(
                threadID: input.threadID,
                turnID: input.turnID,
                inputItemID: input.itemID,
                inputOrdinal: input.ordinal,
                actor: thread.actor,
                mechanism: thread.mechanism,
                inputKind: input.kind,
                submittedAtEstimate: input.submittedAtEstimate,
                textCharacters: input.textCharacters,
                utf8Bytes: input.utf8Bytes,
                attachmentCount: input.attachmentCount,
                skillCount: input.skillCount,
                mentionCount: input.mentionCount
            )
        }.sorted {
            if $0.submittedAtEstimate == $1.submittedAtEstimate {
                return $0.threadID < $1.threadID
            }
            return ($0.submittedAtEstimate ?? .distantPast)
                > ($1.submittedAtEstimate ?? .distantPast)
        }
    }

    public static func failureCandidates(
        archive: ActivityInsightsArchive,
        windowStart: Date? = nil
    ) -> [ActivityHistoryFailureCandidate] {
        archive.threads.values.compactMap { thread in
            guard archive.historyFailureVersions[thread.threadID] == thread.sourceUpdatedAt,
                  windowStart.map({ thread.sourceRecencyAt >= $0 }) ?? true
            else {
                return nil
            }
            return ActivityHistoryFailureCandidate(
                threadID: thread.threadID,
                actor: thread.actor,
                mechanism: thread.mechanism,
                sourceRecencyAt: thread.sourceRecencyAt,
                sourceUpdatedAt: thread.sourceUpdatedAt
            )
        }.sorted {
            if $0.sourceRecencyAt == $1.sourceRecencyAt { return $0.threadID < $1.threadID }
            return $0.sourceRecencyAt > $1.sourceRecencyAt
        }
    }

    public static func validate(
        archive: ActivityInsightsArchive,
        manifest: ActivityValidationManifest,
        requirements: ActivityValidationRequirements = .init(),
        now: Date = Date(),
        windowStart: Date? = nil,
        collectorExpectedSince: Date? = nil
    ) throws -> ActivityValidationReport {
        guard manifest.schemaVersion == ActivityValidationManifest.currentSchemaVersion else {
            throw ActivityInsightsError.persistence(
                "Unsupported validation manifest schema \(manifest.schemaVersion)."
            )
        }
        guard requirements.minimumCases >= 1,
              requirements.minimumDistinctWorkDays >= 1,
              requirements.minimumStateCases >= 0,
              requirements.minimumStateWorkDays >= 0,
              (0...100).contains(requirements.minimumOriginCoveragePercent),
              (0...100).contains(requirements.minimumHistorySyncCoveragePercent),
              (0...100).contains(requirements.minimumCodexFocusCoveragePercent),
              (0...100).contains(requirements.minimumFourStateCoveragePercent),
              (0...100).contains(requirements.minimumStateIntervalCoveragePercent)
        else {
            throw ActivityInsightsError.persistence("Validation requirements are invalid.")
        }
        guard manifest.cases.allSatisfy(isValid), manifest.stateCases.allSatisfy(isValid) else {
            throw ActivityInsightsError.persistence("Validation manifest contains invalid measurements.")
        }

        let audit = ActivityInsightsAuditor.audit(
            archive,
            now: now,
            windowStart: windowStart,
            collectorExpectedSince: collectorExpectedSince
        )
        let results = manifest.cases.map { validate(case: $0, archive: archive) }
        let stateResults = manifest.stateCases.map { validate(stateCase: $0, archive: archive) }
        let passedCaseIDs = Set(results.filter(\.passed).map(\.caseID))
        let passedDays = Set(manifest.cases.compactMap {
            passedCaseIDs.contains($0.caseID) ? $0.workDate : nil
        })
        let uniqueCaseIDs = Set(manifest.cases.map(\.caseID)).count == manifest.cases.count
        let targets = manifest.cases.map { item in
            "\(item.threadID):\(item.turnID):\(item.inputItemID ?? "#\(item.inputOrdinal)")"
        }
        let uniqueTargets = Set(targets).count == targets.count
        let allCasesPassed = results.allSatisfy(\.passed)
        let passedStateCaseIDs = Set(stateResults.filter(\.passed).map(\.caseID))
        let passedStateDays = Set(manifest.stateCases.compactMap {
            passedStateCaseIDs.contains($0.caseID) ? $0.workDate : nil
        })
        let uniqueStateCaseIDs = Set(manifest.stateCases.map(\.caseID)).count == manifest.stateCases.count
        let stateTargets = manifest.stateCases.map {
            "\($0.intervalStart.timeIntervalSince1970):\($0.intervalEnd.timeIntervalSince1970)"
        }
        let uniqueStateTargets = Set(stateTargets).count == stateTargets.count
        let allStateCasesPassed = stateResults.allSatisfy(\.passed)
        let passedStateCases = zip(manifest.stateCases, stateResults).compactMap { item, result in
            result.passed ? item : nil
        }
        let stateValidationRequired = requirements.minimumStateCases > 0
            || requirements.minimumStateWorkDays > 0
            || requirements.minimumStateIntervalCoveragePercent > 0
        let requiredStateCombinations: Set<String> = [
            "active:working",
            "active:idle",
            "inactive:working",
            "inactive:idle"
        ]
        let passedStateCombinations = Set(passedStateCases.map {
            "\($0.expectedUserState.rawValue):\($0.expectedCodexState.rawValue)"
        })
        let coversAllStateCombinations = !stateValidationRequired
            || requiredStateCombinations.isSubset(of: passedStateCombinations)
        let requiredWorkingFocusStates: Set<String> = [
            ActivityCodexFocusState.focused.rawValue,
            ActivityCodexFocusState.notFocused.rawValue
        ]
        let passedWorkingFocusStates = Set(passedStateCases.compactMap {
            $0.expectedCodexState == .working ? $0.expectedFocusState.rawValue : nil
        })
        let coversWorkingFocusStates = !stateValidationRequired
            || requiredWorkingFocusStates.isSubset(of: passedWorkingFocusStates)
        let stateCoverage = stateResults.isEmpty
            ? 0
            : stateResults.reduce(0) { $0 + $1.observedCoveragePercent } / Double(stateResults.count)

        let gates = [
            gate(
                code: "structural_integrity",
                actual: audit.isHealthy ? 1 : 0,
                required: 1,
                message: "The archive has no structural audit errors."
            ),
            gate(
                code: "origin_coverage",
                actual: audit.originCoveragePercent,
                required: requirements.minimumOriginCoveragePercent,
                message: "Recent task origin coverage meets the acceptance threshold."
            ),
            gate(
                code: "history_sync_coverage",
                actual: audit.historySyncCoveragePercent,
                required: requirements.minimumHistorySyncCoveragePercent,
                message: "Recent task histories are synchronized."
            ),
            gate(
                code: "codex_focus_coverage",
                actual: audit.codexFocusCoveragePercent,
                required: requirements.minimumCodexFocusCoveragePercent,
                message: "Codex Desktop focus coverage meets the acceptance threshold."
            ),
            gate(
                code: "four_state_coverage",
                actual: audit.fourStateCoveragePercent,
                required: requirements.minimumFourStateCoveragePercent,
                message: "User-active and Codex-working state coverage meets the acceptance threshold."
            ),
            gate(
                code: "fresh_heartbeat",
                actual: requirements.requireFreshHeartbeat
                    ? (audit.collectorHeartbeatFresh == true ? 1 : 0)
                    : 1,
                required: 1,
                message: "The enabled collector has a fresh heartbeat."
            ),
            gate(
                code: "controlled_sample_size",
                actual: Double(manifest.cases.count),
                required: Double(requirements.minimumCases),
                message: "The controlled truth set has enough cases."
            ),
            gate(
                code: "controlled_work_days",
                actual: Double(passedDays.count),
                required: Double(requirements.minimumDistinctWorkDays),
                message: "Passing controlled cases span enough declared work days."
            ),
            gate(
                code: "unique_controlled_cases",
                actual: uniqueCaseIDs && uniqueTargets ? 1 : 0,
                required: 1,
                message: "Controlled case IDs and archive targets are unique."
            ),
            gate(
                code: "controlled_case_accuracy",
                actual: allCasesPassed ? 1 : 0,
                required: 1,
                message: "Every controlled origin, time, and input measurement matches."
            ),
            gate(
                code: "controlled_state_sample_size",
                actual: Double(manifest.stateCases.count),
                required: Double(requirements.minimumStateCases),
                message: "The controlled four-state truth set has enough cases."
            ),
            gate(
                code: "controlled_state_work_days",
                actual: Double(passedStateDays.count),
                required: Double(requirements.minimumStateWorkDays),
                message: "Passing controlled state cases span enough declared work days."
            ),
            gate(
                code: "unique_controlled_state_cases",
                actual: uniqueStateCaseIDs && uniqueStateTargets ? 1 : 0,
                required: 1,
                message: "Controlled state case IDs and intervals are unique."
            ),
            gate(
                code: "controlled_four_state_combinations",
                actual: coversAllStateCombinations ? 1 : 0,
                required: 1,
                message: "Passing controlled cases cover all four user and Codex state combinations."
            ),
            gate(
                code: "controlled_working_focus_states",
                actual: coversWorkingFocusStates ? 1 : 0,
                required: 1,
                message: "Passing Codex-working cases cover foreground and background focus."
            ),
            gate(
                code: "controlled_state_interval_coverage",
                actual: stateCoverage,
                required: requirements.minimumStateIntervalCoveragePercent,
                message: "Declared controlled intervals have enough observed coverage."
            ),
            gate(
                code: "controlled_state_accuracy",
                actual: allStateCasesPassed ? 1 : 0,
                required: 1,
                message: "Every controlled user, Codex, and focus state matches."
            )
        ]

        return ActivityValidationReport(
            generatedAt: now,
            windowStart: windowStart,
            audit: audit,
            gates: gates,
            cases: results,
            stateCases: stateResults
        )
    }

    private static func validate(
        case expected: ActivityValidationCase,
        archive: ActivityInsightsArchive
    ) -> ActivityValidationCaseResult {
        var mismatches: [String] = []
        let thread = archive.threads[expected.threadID]
        if let thread {
            if thread.actor != expected.expectedActor { mismatches.append("thread_actor") }
            if thread.mechanism != expected.expectedMechanism { mismatches.append("creation_mechanism") }
        } else {
            mismatches.append("missing_thread")
        }

        let turnKey = ActivityTurnFact.key(threadID: expected.threadID, turnID: expected.turnID)
        if archive.turns[turnKey] == nil { mismatches.append("missing_turn") }

        let input = archive.inputs.values.first { input in
            guard input.threadID == expected.threadID,
                  input.turnID == expected.turnID,
                  input.ordinal == expected.inputOrdinal
            else {
                return false
            }
            return expected.inputItemID.map { input.itemID == $0 } ?? true
        }
        if let input {
            if input.kind != expected.expectedInputKind { mismatches.append("input_kind") }
            if input.textCharacters != expected.expectedTextCharacters {
                mismatches.append("text_characters")
            }
            if input.utf8Bytes != expected.expectedUTF8Bytes { mismatches.append("utf8_bytes") }
            if let expectedCount = expected.expectedAttachmentCount,
               input.attachmentCount != expectedCount {
                mismatches.append("attachment_count")
            }
            if let expectedCount = expected.expectedSkillCount, input.skillCount != expectedCount {
                mismatches.append("skill_count")
            }
            if let expectedCount = expected.expectedMentionCount,
               input.mentionCount != expectedCount {
                mismatches.append("mention_count")
            }
            if let submittedAt = input.submittedAtEstimate {
                if abs(submittedAt.timeIntervalSince(expected.expectedSubmittedAt))
                    > expected.timestampToleranceSeconds {
                    mismatches.append("submitted_at")
                }
            } else {
                mismatches.append("missing_submitted_at")
            }
        } else {
            mismatches.append("missing_input")
        }

        return ActivityValidationCaseResult(
            caseID: expected.caseID,
            passed: mismatches.isEmpty,
            mismatches: mismatches.sorted()
        )
    }

    private static func validate(
        stateCase expected: ActivityStateValidationCase,
        archive: ActivityInsightsArchive
    ) -> ActivityStateValidationCaseResult {
        let observations = archive.observationFacts.values.filter {
            $0.intervalEnd > expected.intervalStart && $0.intervalStart < expected.intervalEnd
        }
        let metrics = ActivityCollaborationAnalyzer.analyze(
            observations: Array(observations),
            turns: Array(archive.turns.values),
            threads: archive.threads,
            now: expected.intervalEnd,
            windowStart: expected.intervalStart
        )
        let observedSeconds = metrics.codexFocusedSeconds
            + metrics.codexNotFocusedSeconds
            + metrics.codexFocusUnknownSeconds
        let expectedSeconds = expected.intervalEnd.timeIntervalSince(expected.intervalStart)
        let coverage = expectedSeconds > 0 ? min(100, observedSeconds / expectedSeconds * 100) : 0
        var mismatches: [String] = []
        if expectedSeconds - observedSeconds > expected.toleranceSeconds {
            mismatches.append("interval_coverage")
        }

        let userStateSeconds: TimeInterval
        switch expected.expectedUserState {
        case .active:
            userStateSeconds = metrics.activeCodexWorkingSeconds
                + metrics.activeCodexIdleSeconds
                + metrics.activeCodexUnknownSeconds
        case .inactive:
            userStateSeconds = metrics.inactiveCodexWorkingSeconds
                + metrics.inactiveCodexIdleSeconds
                + metrics.inactiveCodexUnknownSeconds
        case .unknown:
            userStateSeconds = metrics.unknownUserStateSeconds
        }
        if observedSeconds - userStateSeconds > expected.toleranceSeconds {
            mismatches.append("user_state")
        }

        let codexStateSeconds: TimeInterval
        switch expected.expectedCodexState {
        case .working:
            codexStateSeconds = metrics.activeCodexWorkingSeconds
                + metrics.inactiveCodexWorkingSeconds
                + metrics.unknownUserCodexWorkingSeconds
        case .idle:
            codexStateSeconds = metrics.activeCodexIdleSeconds
                + metrics.inactiveCodexIdleSeconds
                + metrics.unknownUserCodexIdleSeconds
        case .unknown:
            codexStateSeconds = metrics.activeCodexUnknownSeconds
                + metrics.inactiveCodexUnknownSeconds
                + metrics.unknownUserCodexUnknownSeconds
        }
        if observedSeconds - codexStateSeconds > expected.toleranceSeconds {
            mismatches.append("codex_state")
        }

        let focusStateSeconds: TimeInterval
        switch expected.expectedFocusState {
        case .focused:
            focusStateSeconds = metrics.codexFocusedSeconds
        case .notFocused:
            focusStateSeconds = metrics.codexNotFocusedSeconds
        case .unknown:
            focusStateSeconds = metrics.codexFocusUnknownSeconds
        }
        if observedSeconds - focusStateSeconds > expected.toleranceSeconds {
            mismatches.append("focus_state")
        }

        return ActivityStateValidationCaseResult(
            caseID: expected.caseID,
            passed: mismatches.isEmpty,
            observedCoveragePercent: coverage,
            mismatches: mismatches.sorted()
        )
    }

    private static func gate(
        code: String,
        actual: Double,
        required: Double,
        message: String
    ) -> ActivityValidationGate {
        ActivityValidationGate(
            code: code,
            passed: actual >= required,
            actual: actual,
            required: required,
            message: message
        )
    }

    private static func isValid(_ item: ActivityValidationCase) -> Bool {
        let countValues = [
            item.expectedAttachmentCount,
            item.expectedSkillCount,
            item.expectedMentionCount
        ].compactMap { $0 }
        return !item.caseID.isEmpty
            && workDate(item.workDate, matches: item.expectedSubmittedAt)
            && !item.threadID.isEmpty
            && !item.turnID.isEmpty
            && item.inputOrdinal >= 0
            && item.timestampToleranceSeconds.isFinite
            && item.timestampToleranceSeconds >= 0
            && item.expectedTextCharacters >= 0
            && item.expectedUTF8Bytes >= item.expectedTextCharacters
            && countValues.allSatisfy { $0 >= 0 }
    }

    private static func isValid(_ item: ActivityStateValidationCase) -> Bool {
        !item.caseID.isEmpty
            && workDate(item.workDate, matches: item.intervalStart)
            && item.intervalEnd > item.intervalStart
            && item.toleranceSeconds.isFinite
            && item.toleranceSeconds >= 0
    }

    private static func workDate(_ value: String, matches date: Date) -> Bool {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let parsed = formatter.date(from: value),
              formatter.string(from: parsed) == value
        else {
            return false
        }
        return formatter.string(from: date) == value
    }
}
