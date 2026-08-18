import Foundation

public enum ActivityAuditSeverity: String, Codable, Sendable {
    case warning
    case error
}

public struct ActivityAuditIssue: Codable, Equatable, Sendable {
    public let severity: ActivityAuditSeverity
    public let code: String
    public let count: Int
    public let message: String

    public init(severity: ActivityAuditSeverity, code: String, count: Int, message: String) {
        self.severity = severity
        self.code = code
        self.count = count
        self.message = message
    }
}

public struct ActivityAuditReport: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let windowStart: Date?
    public let schemaVersion: Int
    public let threadCount: Int
    public let turnCount: Int
    public let inputCount: Int
    public let activityMinuteCount: Int
    public let observationFactCount: Int
    public let collectorCoverageMinuteCount: Int
    public let collectorSessionCount: Int
    public let collectionRunCount: Int
    public let collectionFailureAttempts: Int
    public let knownOriginThreads: Int
    public let originCoveragePercent: Double
    public let historySyncedThreads: Int
    public let historySyncCoveragePercent: Double
    public let knownFailedThreadVersions: Int
    public let actorCounts: [String: Int]
    public let inputKindCounts: [String: Int]
    public let inputActorCounts: [String: Int]
    public let averageInputCharacters: Double
    public let inputCharacterTotalsByActor: [String: Int]
    public let averageInputCharactersByActor: [String: Double]
    public let completedTurnDurationSeconds: Double
    public let activityObservedSeconds: Double
    public let activityUnavailableSeconds: Double
    public let activeWithinTwoMinutesSeconds: Double
    public let activeWithinFiveMinutesSeconds: Double
    public let activeWithinTenMinutesSeconds: Double
    public let observationSeconds: Double
    public let codexFocusedSeconds: Double
    public let codexNotFocusedSeconds: Double
    public let codexFocusUnknownSeconds: Double
    public let codexFocusCoveragePercent: Double
    public let activeCodexWorkingSeconds: Double
    public let activeCodexIdleSeconds: Double
    public let inactiveCodexWorkingSeconds: Double
    public let inactiveCodexIdleSeconds: Double
    public let activeCodexUnknownSeconds: Double
    public let inactiveCodexUnknownSeconds: Double
    public let unknownUserCodexWorkingSeconds: Double
    public let unknownUserCodexIdleSeconds: Double
    public let unknownUserCodexUnknownSeconds: Double
    public let unknownUserStateSeconds: Double
    public let fourStateUnknownSeconds: Double
    public let fourStateCoveragePercent: Double
    public let codexWorkingFocusedSeconds: Double
    public let codexWorkingNotFocusedSeconds: Double
    public let codexWorkingFocusUnknownSeconds: Double
    public let collectorRunningSeconds: Double
    public let collectorUnknownSeconds: Double
    public let collectorCoveragePercent: Double
    public let collectorLastHeartbeatAt: Date?
    public let collectorHeartbeatAgeSeconds: Double?
    public let collectorHeartbeatFresh: Bool?
    public let provisionalTurns: Int
    public let issues: [ActivityAuditIssue]

    public var isHealthy: Bool { !issues.contains { $0.severity == .error } }

    public init(
        generatedAt: Date,
        windowStart: Date?,
        schemaVersion: Int,
        threadCount: Int,
        turnCount: Int,
        inputCount: Int,
        activityMinuteCount: Int,
        observationFactCount: Int,
        collectorCoverageMinuteCount: Int,
        collectorSessionCount: Int,
        collectionRunCount: Int,
        collectionFailureAttempts: Int,
        knownOriginThreads: Int,
        originCoveragePercent: Double,
        historySyncedThreads: Int,
        historySyncCoveragePercent: Double,
        knownFailedThreadVersions: Int,
        actorCounts: [String: Int],
        inputKindCounts: [String: Int],
        inputActorCounts: [String: Int],
        averageInputCharacters: Double,
        inputCharacterTotalsByActor: [String: Int],
        averageInputCharactersByActor: [String: Double],
        completedTurnDurationSeconds: Double,
        activityObservedSeconds: Double,
        activityUnavailableSeconds: Double,
        activeWithinTwoMinutesSeconds: Double,
        activeWithinFiveMinutesSeconds: Double,
        activeWithinTenMinutesSeconds: Double,
        observationSeconds: Double,
        codexFocusedSeconds: Double,
        codexNotFocusedSeconds: Double,
        codexFocusUnknownSeconds: Double,
        codexFocusCoveragePercent: Double,
        activeCodexWorkingSeconds: Double,
        activeCodexIdleSeconds: Double,
        inactiveCodexWorkingSeconds: Double,
        inactiveCodexIdleSeconds: Double,
        activeCodexUnknownSeconds: Double,
        inactiveCodexUnknownSeconds: Double,
        unknownUserCodexWorkingSeconds: Double,
        unknownUserCodexIdleSeconds: Double,
        unknownUserCodexUnknownSeconds: Double,
        unknownUserStateSeconds: Double,
        fourStateUnknownSeconds: Double,
        fourStateCoveragePercent: Double,
        codexWorkingFocusedSeconds: Double,
        codexWorkingNotFocusedSeconds: Double,
        codexWorkingFocusUnknownSeconds: Double,
        collectorRunningSeconds: Double,
        collectorUnknownSeconds: Double,
        collectorCoveragePercent: Double,
        collectorLastHeartbeatAt: Date?,
        collectorHeartbeatAgeSeconds: Double?,
        collectorHeartbeatFresh: Bool?,
        provisionalTurns: Int,
        issues: [ActivityAuditIssue]
    ) {
        self.generatedAt = generatedAt
        self.windowStart = windowStart
        self.schemaVersion = schemaVersion
        self.threadCount = threadCount
        self.turnCount = turnCount
        self.inputCount = inputCount
        self.activityMinuteCount = activityMinuteCount
        self.observationFactCount = observationFactCount
        self.collectorCoverageMinuteCount = collectorCoverageMinuteCount
        self.collectorSessionCount = collectorSessionCount
        self.collectionRunCount = collectionRunCount
        self.collectionFailureAttempts = collectionFailureAttempts
        self.knownOriginThreads = knownOriginThreads
        self.originCoveragePercent = originCoveragePercent
        self.historySyncedThreads = historySyncedThreads
        self.historySyncCoveragePercent = historySyncCoveragePercent
        self.knownFailedThreadVersions = knownFailedThreadVersions
        self.actorCounts = actorCounts
        self.inputKindCounts = inputKindCounts
        self.inputActorCounts = inputActorCounts
        self.averageInputCharacters = averageInputCharacters
        self.inputCharacterTotalsByActor = inputCharacterTotalsByActor
        self.averageInputCharactersByActor = averageInputCharactersByActor
        self.completedTurnDurationSeconds = completedTurnDurationSeconds
        self.activityObservedSeconds = activityObservedSeconds
        self.activityUnavailableSeconds = activityUnavailableSeconds
        self.activeWithinTwoMinutesSeconds = activeWithinTwoMinutesSeconds
        self.activeWithinFiveMinutesSeconds = activeWithinFiveMinutesSeconds
        self.activeWithinTenMinutesSeconds = activeWithinTenMinutesSeconds
        self.observationSeconds = observationSeconds
        self.codexFocusedSeconds = codexFocusedSeconds
        self.codexNotFocusedSeconds = codexNotFocusedSeconds
        self.codexFocusUnknownSeconds = codexFocusUnknownSeconds
        self.codexFocusCoveragePercent = codexFocusCoveragePercent
        self.activeCodexWorkingSeconds = activeCodexWorkingSeconds
        self.activeCodexIdleSeconds = activeCodexIdleSeconds
        self.inactiveCodexWorkingSeconds = inactiveCodexWorkingSeconds
        self.inactiveCodexIdleSeconds = inactiveCodexIdleSeconds
        self.activeCodexUnknownSeconds = activeCodexUnknownSeconds
        self.inactiveCodexUnknownSeconds = inactiveCodexUnknownSeconds
        self.unknownUserCodexWorkingSeconds = unknownUserCodexWorkingSeconds
        self.unknownUserCodexIdleSeconds = unknownUserCodexIdleSeconds
        self.unknownUserCodexUnknownSeconds = unknownUserCodexUnknownSeconds
        self.unknownUserStateSeconds = unknownUserStateSeconds
        self.fourStateUnknownSeconds = fourStateUnknownSeconds
        self.fourStateCoveragePercent = fourStateCoveragePercent
        self.codexWorkingFocusedSeconds = codexWorkingFocusedSeconds
        self.codexWorkingNotFocusedSeconds = codexWorkingNotFocusedSeconds
        self.codexWorkingFocusUnknownSeconds = codexWorkingFocusUnknownSeconds
        self.collectorRunningSeconds = collectorRunningSeconds
        self.collectorUnknownSeconds = collectorUnknownSeconds
        self.collectorCoveragePercent = collectorCoveragePercent
        self.collectorLastHeartbeatAt = collectorLastHeartbeatAt
        self.collectorHeartbeatAgeSeconds = collectorHeartbeatAgeSeconds
        self.collectorHeartbeatFresh = collectorHeartbeatFresh
        self.provisionalTurns = provisionalTurns
        self.issues = issues
    }
}

public enum ActivityInsightsAuditor {
    public static func audit(
        _ archive: ActivityInsightsArchive,
        now: Date = Date(),
        windowStart: Date? = nil,
        collectorExpectedSince: Date? = nil
    ) -> ActivityAuditReport {
        var issues: [ActivityAuditIssue] = []
        let threadIDs = Set(archive.threads.keys)
        let turnKeys = Set(archive.turns.keys)
        let metricThreads = archive.threads.values.filter { thread in
            windowStart.map { thread.sourceRecencyAt >= $0 } ?? true
        }
        let metricThreadIDs = Set(metricThreads.map(\.threadID))
        let metricTurns = archive.turns.values.filter { turn in
            metricThreadIDs.contains(turn.threadID)
                && turnIntersectsWindow(
                    turn,
                    thread: archive.threads[turn.threadID],
                    windowStart: windowStart,
                    now: now
                )
        }
        let metricInputs = archive.inputs.values.filter { input in
            guard metricThreadIDs.contains(input.threadID) else { return false }
            guard let windowStart else { return true }
            guard let submittedAt = input.submittedAtEstimate else { return false }
            return submittedAt >= windowStart && submittedAt < now
        }
        let metricMinutes = archive.activityMinutes.values.filter { minute in
            windowStart.map { minute.minuteStart >= $0 } ?? true
        }
        let metricObservationFacts = archive.observationFacts.values.filter { fact in
            (windowStart.map { fact.intervalEnd > $0 } ?? true) && fact.intervalStart < now
        }
        let metricCollectorMinutes = archive.collectorCoverageMinutes.values.filter { minute in
            windowStart.map { minute.minuteStart >= $0 } ?? true
        }
        let recentRuns = archive.collectionRuns.filter { run in
            windowStart.map { run.finishedAt >= $0 } ?? true
        }
        let metricRuns: [ActivityCollectionRun]
        if let windowStart {
            let windowDuration = now.timeIntervalSince(windowStart)
            metricRuns = recentRuns.filter { run in
                guard let lookback = run.lookbackSeconds else { return false }
                return abs(lookback - windowDuration) <= 60
            }
        } else {
            metricRuns = recentRuns
        }

        addIssue(
            count: archive.turns.filter { !threadIDs.contains($0.value.threadID) }.count,
            severity: .error,
            code: "orphan_turn",
            message: "Turns reference threads absent from the archive.",
            to: &issues
        )
        addIssue(
            count: archive.inputs.filter {
                !turnKeys.contains(ActivityTurnFact.key(
                    threadID: $0.value.threadID,
                    turnID: $0.value.turnID
                ))
            }.count,
            severity: .error,
            code: "orphan_input",
            message: "Inputs reference turns absent from the archive.",
            to: &issues
        )
        addIssue(
            count: archive.threads.filter { $0.key != $0.value.threadID }.count,
            severity: .error,
            code: "thread_key_mismatch",
            message: "Thread dictionary keys do not match stored IDs.",
            to: &issues
        )
        addIssue(
            count: archive.turns.filter { $0.key != $0.value.key }.count,
            severity: .error,
            code: "turn_key_mismatch",
            message: "Turn dictionary keys do not match composite IDs.",
            to: &issues
        )
        addIssue(
            count: archive.inputs.filter { $0.key != $0.value.key }.count,
            severity: .error,
            code: "input_key_mismatch",
            message: "Input dictionary keys do not match composite IDs.",
            to: &issues
        )
        addIssue(
            count: archive.historyAttemptVersions.keys.filter { !threadIDs.contains($0) }.count
                + archive.historySyncVersions.keys.filter { !threadIDs.contains($0) }.count
                + archive.historyFailureVersions.keys.filter { !threadIDs.contains($0) }.count,
            severity: .error,
            code: "orphan_history_version",
            message: "History attempt, sync, or failure versions reference absent threads.",
            to: &issues
        )

        let negativeOrReversed = archive.turns.values.filter { turn in
            if let duration = turn.durationMilliseconds, duration < 0 { return true }
            if let start = turn.startedAt, let completion = turn.completedAt, completion < start { return true }
            return false
        }.count
        addIssue(
            count: negativeOrReversed,
            severity: .error,
            code: "invalid_turn_time",
            message: "Turns contain a negative duration or complete before they start.",
            to: &issues
        )

        let durationMismatches = archive.turns.values.filter { turn in
            guard let start = turn.startedAt,
                  let completion = turn.completedAt,
                  let duration = turn.durationMilliseconds
            else {
                return false
            }
            let derived = completion.timeIntervalSince(start) * 1_000
            return abs(derived - Double(duration)) > 1_500
        }.count
        addIssue(
            count: durationMismatches,
            severity: .warning,
            code: "turn_duration_mismatch",
            message: "Turn duration differs from rounded start and completion timestamps by more than 1.5 seconds.",
            to: &issues
        )

        let futureFacts = archive.turns.values.filter {
            ($0.startedAt ?? .distantPast) > now.addingTimeInterval(5 * 60)
                || ($0.completedAt ?? .distantPast) > now.addingTimeInterval(5 * 60)
        }.count
        addIssue(
            count: futureFacts,
            severity: .error,
            code: "future_turn",
            message: "Turns are timestamped more than five minutes in the future.",
            to: &issues
        )

        let invalidInputs = archive.inputs.values.filter {
            $0.textCharacters < 0 || $0.utf8Bytes < 0 || $0.attachmentCount < 0
                || $0.skillCount < 0 || $0.mentionCount < 0
                || $0.utf8Bytes < $0.textCharacters
        }.count
        addIssue(
            count: invalidInputs,
            severity: .error,
            code: "invalid_input_measurement",
            message: "Input measurements contain negative values.",
            to: &issues
        )

        let invalidMinutes = archive.activityMinutes.values.filter { minute in
            let total = minute.observedSeconds + minute.unavailableSeconds
            return total < 0 || total > 60.001
                || minute.activeWithinTwoMinutesSeconds < 0
                || minute.activeWithinTwoMinutesSeconds > minute.observedSeconds + 0.001
                || minute.activeWithinFiveMinutesSeconds + 0.001 < minute.activeWithinTwoMinutesSeconds
                || minute.activeWithinTenMinutesSeconds + 0.001 < minute.activeWithinFiveMinutesSeconds
                || minute.activeWithinTenMinutesSeconds > minute.observedSeconds + 0.001
        }.count
        addIssue(
            count: invalidMinutes,
            severity: .error,
            code: "invalid_activity_minute",
            message: "Activity-minute conservation or threshold ordering is invalid.",
            to: &issues
        )

        let invalidObservationFacts = archive.observationFacts.filter { key, fact in
            key != fact.key
                || fact.key != ActivityObservationFact.key(intervalEnd: fact.intervalEnd)
                || fact.durationSeconds <= 0
                || fact.durationSeconds > 60.001
                || fact.intervalEnd > now.addingTimeInterval(5 * 60)
        }.count
        addIssue(
            count: invalidObservationFacts,
            severity: .error,
            code: "invalid_observation_fact",
            message: "Aligned activity and Codex-focus observations are invalid.",
            to: &issues
        )

        let orderedObservationFacts = archive.observationFacts.values.sorted {
            if $0.intervalStart == $1.intervalStart { return $0.intervalEnd < $1.intervalEnd }
            return $0.intervalStart < $1.intervalStart
        }
        let overlappingObservationFacts = zip(
            orderedObservationFacts,
            orderedObservationFacts.dropFirst()
        ).filter { pair in
            pair.1.intervalStart < pair.0.intervalEnd.addingTimeInterval(-0.001)
        }.count
        addIssue(
            count: overlappingObservationFacts,
            severity: .error,
            code: "overlapping_observation_fact",
            message: "Aligned activity observations overlap and would double-count time.",
            to: &issues
        )

        let invalidCollectorMinutes = archive.collectorCoverageMinutes.filter { key, minute in
            let total = minute.runningSeconds + minute.unknownSeconds
            return key != minute.key || total < 0 || total > 60.001
                || minute.runningSeconds < 0 || minute.unknownSeconds < 0
        }.count
        addIssue(
            count: invalidCollectorMinutes,
            severity: .error,
            code: "invalid_collector_coverage_minute",
            message: "Collector runtime coverage is invalid or keyed incorrectly.",
            to: &issues
        )

        let invalidCollectorState: Int
        if let state = archive.collectorState {
            let isInvalid = state.expectedHeartbeatIntervalSeconds < 1
                || state.lastHeartbeatAt < state.startedAt
                || (state.stoppedAt.map { $0 < state.lastHeartbeatAt } ?? false)
                || (state.isRunning && state.stopReason != nil)
                || (!state.isRunning && state.stopReason == nil)
            invalidCollectorState = isInvalid ? 1 : 0
        } else {
            invalidCollectorState = 0
        }
        addIssue(
            count: invalidCollectorState,
            severity: .error,
            code: "invalid_collector_state",
            message: "Collector runtime state has invalid timestamps or lifecycle fields.",
            to: &issues
        )

        let failedAttempts = metricRuns.reduce(0) { $0 + $1.threadFailures }
        addIssue(
            count: metricRuns.last?.threadFailures ?? 0,
            severity: .warning,
            code: "thread_collection_failure",
            message: "One or more thread histories could not be collected.",
            to: &issues
        )
        addIssue(
            count: archive.collectionRuns.filter {
                !$0.failureCounts.isEmpty
                    && $0.failureCounts.values.reduce(0, +) != $0.threadFailures
            }.count,
            severity: .error,
            code: "failure_count_mismatch",
            message: "Collection failure categories do not sum to the stored total.",
            to: &issues
        )
        addIssue(
            count: metricRuns.last?.threadsDeferred ?? 0,
            severity: .warning,
            code: "history_backfill_pending",
            message: "The latest collection run deferred histories to a later checkpoint.",
            to: &issues
        )
        addIssue(
            count: metricThreads.filter {
                archive.historySyncVersions[$0.threadID] != $0.sourceUpdatedAt
            }.count,
            severity: .warning,
            code: "thread_history_not_synced",
            message: "One or more current thread versions do not have a successful history sync.",
            to: &issues
        )

        var actorCounts: [String: Int] = [:]
        for thread in metricThreads {
            actorCounts[thread.actor.rawValue, default: 0] += 1
        }
        let knownOrigins = metricThreads.filter { $0.actor != .unknown }.count
        let coverage = metricThreads.isEmpty
            ? 0
            : Double(knownOrigins) / Double(metricThreads.count) * 100
        let unknownOrigins = metricThreads.count - knownOrigins
        addIssue(
            count: unknownOrigins,
            severity: .warning,
            code: "unknown_thread_origin",
            message: "Threads lack reliable user, Codex, or automation provenance.",
            to: &issues
        )

        let syncedThreads = metricThreads.filter {
            archive.historySyncVersions[$0.threadID] == $0.sourceUpdatedAt
        }.count
        let syncCoverage = metricThreads.isEmpty
            ? 0
            : Double(syncedThreads) / Double(metricThreads.count) * 100
        let knownFailedVersions = metricThreads.filter {
            archive.historyFailureVersions[$0.threadID] == $0.sourceUpdatedAt
        }.count
        var inputKindCounts: [String: Int] = [:]
        var inputActorCounts: [String: Int] = [:]
        var inputCharacterTotalsByActor: [String: Int] = [:]
        for input in metricInputs {
            inputKindCounts[input.kind.rawValue, default: 0] += 1
            inputActorCounts[input.actor.rawValue, default: 0] += 1
            inputCharacterTotalsByActor[input.actor.rawValue, default: 0] += input.textCharacters
        }
        var averageInputCharactersByActor: [String: Double] = [:]
        for (actor, total) in inputCharacterTotalsByActor {
            let count = inputActorCounts[actor, default: 0]
            averageInputCharactersByActor[actor] = count == 0 ? 0 : Double(total) / Double(count)
        }
        let averageInputCharacters = metricInputs.isEmpty
            ? 0
            : Double(metricInputs.reduce(0) { $0 + $1.textCharacters }) / Double(metricInputs.count)
        let turnDuration = metricTurns.reduce(0.0) {
            $0 + completedDuration(of: $1, windowStart: windowStart, now: now)
        }
        let activityObserved = metricMinutes.reduce(0.0) { $0 + $1.observedSeconds }
        let activityUnavailable = metricMinutes.reduce(0.0) { $0 + $1.unavailableSeconds }
        let activeTwo = metricMinutes.reduce(0.0) { $0 + $1.activeWithinTwoMinutesSeconds }
        let activeFive = metricMinutes.reduce(0.0) { $0 + $1.activeWithinFiveMinutesSeconds }
        let activeTen = metricMinutes.reduce(0.0) { $0 + $1.activeWithinTenMinutesSeconds }
        let collaboration = ActivityCollaborationAnalyzer.analyze(
            observations: Array(metricObservationFacts),
            turns: Array(archive.turns.values),
            threads: archive.threads,
            now: now,
            windowStart: windowStart
        )
        let observationSeconds = collaboration.codexFocusedSeconds
            + collaboration.codexNotFocusedSeconds
            + collaboration.codexFocusUnknownSeconds
        let codexWorkingFocusKnownSeconds = collaboration.codexWorkingFocusedSeconds
            + collaboration.codexWorkingNotFocusedSeconds
        let codexWorkingFocusTotalSeconds = codexWorkingFocusKnownSeconds
            + collaboration.codexWorkingFocusUnknownSeconds
        let codexFocusCoveragePercent = codexWorkingFocusTotalSeconds == 0
            ? 0
            : codexWorkingFocusKnownSeconds / codexWorkingFocusTotalSeconds * 100
        let fourStateKnownSeconds = collaboration.activeCodexWorkingSeconds
            + collaboration.activeCodexIdleSeconds
            + collaboration.inactiveCodexWorkingSeconds
            + collaboration.inactiveCodexIdleSeconds
        let fourStateTotalSeconds = fourStateKnownSeconds + collaboration.fourStateUnknownSeconds
        let fourStateCoveragePercent = fourStateTotalSeconds == 0
            ? 0
            : fourStateKnownSeconds / fourStateTotalSeconds * 100
        let collectorRunning = metricCollectorMinutes.reduce(0.0) { $0 + $1.runningSeconds }
        var collectorUnknown = metricCollectorMinutes.reduce(0.0) { $0 + $1.unknownSeconds }
        let collectorLastHeartbeatAt = archive.collectorState?.lastHeartbeatAt
        let collectorHeartbeatAge = collectorLastHeartbeatAt.map {
            max(0, now.timeIntervalSince($0))
        }
        var collectorHeartbeatFresh: Bool?
        if let collectorExpectedSince {
            if let state = archive.collectorState, state.isRunning {
                let age = max(0, now.timeIntervalSince(state.lastHeartbeatAt))
                let grace = state.expectedHeartbeatIntervalSeconds * 3
                collectorHeartbeatFresh = age <= grace
                if age > grace {
                    let gapStart = max(
                        state.lastHeartbeatAt.addingTimeInterval(
                            state.expectedHeartbeatIntervalSeconds
                        ),
                        max(windowStart ?? collectorExpectedSince, collectorExpectedSince)
                    )
                    collectorUnknown += max(0, now.timeIntervalSince(gapStart))
                }
            } else {
                collectorHeartbeatFresh = false
                let gapStart = max(
                    archive.collectorState?.stoppedAt ?? collectorExpectedSince,
                    max(windowStart ?? collectorExpectedSince, collectorExpectedSince)
                )
                collectorUnknown += max(0, now.timeIntervalSince(gapStart))
            }
        }
        addIssue(
            count: collectorHeartbeatFresh == false ? 1 : 0,
            severity: .warning,
            code: "collector_heartbeat_stale",
            message: "Collection is enabled but no fresh independent collector heartbeat is available.",
            to: &issues
        )
        let collectorCoverageTotal = collectorRunning + collectorUnknown
        let collectorCoveragePercent = collectorCoverageTotal == 0
            ? 0
            : collectorRunning / collectorCoverageTotal * 100

        return ActivityAuditReport(
            generatedAt: now,
            windowStart: windowStart,
            schemaVersion: archive.schemaVersion,
            threadCount: metricThreads.count,
            turnCount: metricTurns.count,
            inputCount: metricInputs.count,
            activityMinuteCount: metricMinutes.count,
            observationFactCount: metricObservationFacts.count,
            collectorCoverageMinuteCount: metricCollectorMinutes.count,
            collectorSessionCount: archive.collectorSessionCount,
            collectionRunCount: metricRuns.count,
            collectionFailureAttempts: failedAttempts,
            knownOriginThreads: knownOrigins,
            originCoveragePercent: coverage,
            historySyncedThreads: syncedThreads,
            historySyncCoveragePercent: syncCoverage,
            knownFailedThreadVersions: knownFailedVersions,
            actorCounts: actorCounts,
            inputKindCounts: inputKindCounts,
            inputActorCounts: inputActorCounts,
            averageInputCharacters: averageInputCharacters,
            inputCharacterTotalsByActor: inputCharacterTotalsByActor,
            averageInputCharactersByActor: averageInputCharactersByActor,
            completedTurnDurationSeconds: turnDuration,
            activityObservedSeconds: activityObserved,
            activityUnavailableSeconds: activityUnavailable,
            activeWithinTwoMinutesSeconds: activeTwo,
            activeWithinFiveMinutesSeconds: activeFive,
            activeWithinTenMinutesSeconds: activeTen,
            observationSeconds: observationSeconds,
            codexFocusedSeconds: collaboration.codexFocusedSeconds,
            codexNotFocusedSeconds: collaboration.codexNotFocusedSeconds,
            codexFocusUnknownSeconds: collaboration.codexFocusUnknownSeconds,
            codexFocusCoveragePercent: codexFocusCoveragePercent,
            activeCodexWorkingSeconds: collaboration.activeCodexWorkingSeconds,
            activeCodexIdleSeconds: collaboration.activeCodexIdleSeconds,
            inactiveCodexWorkingSeconds: collaboration.inactiveCodexWorkingSeconds,
            inactiveCodexIdleSeconds: collaboration.inactiveCodexIdleSeconds,
            activeCodexUnknownSeconds: collaboration.activeCodexUnknownSeconds,
            inactiveCodexUnknownSeconds: collaboration.inactiveCodexUnknownSeconds,
            unknownUserCodexWorkingSeconds: collaboration.unknownUserCodexWorkingSeconds,
            unknownUserCodexIdleSeconds: collaboration.unknownUserCodexIdleSeconds,
            unknownUserCodexUnknownSeconds: collaboration.unknownUserCodexUnknownSeconds,
            unknownUserStateSeconds: collaboration.unknownUserStateSeconds,
            fourStateUnknownSeconds: collaboration.fourStateUnknownSeconds,
            fourStateCoveragePercent: fourStateCoveragePercent,
            codexWorkingFocusedSeconds: collaboration.codexWorkingFocusedSeconds,
            codexWorkingNotFocusedSeconds: collaboration.codexWorkingNotFocusedSeconds,
            codexWorkingFocusUnknownSeconds: collaboration.codexWorkingFocusUnknownSeconds,
            collectorRunningSeconds: collectorRunning,
            collectorUnknownSeconds: collectorUnknown,
            collectorCoveragePercent: collectorCoveragePercent,
            collectorLastHeartbeatAt: collectorLastHeartbeatAt,
            collectorHeartbeatAgeSeconds: collectorHeartbeatAge,
            collectorHeartbeatFresh: collectorHeartbeatFresh,
            provisionalTurns: metricTurns.filter(\.isProvisional).count,
            issues: issues.sorted {
                if $0.severity == $1.severity { return $0.code < $1.code }
                return $0.severity == .error
            }
        )
    }

    private static func turnIntersectsWindow(
        _ turn: ActivityTurnFact,
        thread: ActivityThreadFact?,
        windowStart: Date?,
        now: Date
    ) -> Bool {
        guard let windowStart else { return true }
        guard let start = turn.startedAt else {
            return turn.completedAt.map { $0 >= windowStart && $0 < now } ?? false
        }
        let end: Date
        if let completedAt = turn.completedAt {
            end = completedAt
        } else if isTerminalTurnStatus(turn.status) {
            end = min(thread?.sourceUpdatedAt ?? start, now)
        } else {
            end = now
        }
        return start < now && end > windowStart
    }

    private static func completedDuration(
        of turn: ActivityTurnFact,
        windowStart: Date?,
        now: Date
    ) -> TimeInterval {
        guard let durationMilliseconds = turn.durationMilliseconds else { return 0 }
        guard let windowStart,
              let start = turn.startedAt,
              let completedAt = turn.completedAt,
              completedAt > start
        else {
            return max(0, Double(durationMilliseconds) / 1_000)
        }
        let clippedStart = max(start, windowStart)
        let clippedEnd = min(completedAt, now)
        return max(0, clippedEnd.timeIntervalSince(clippedStart))
    }

    private static func isTerminalTurnStatus(_ status: String) -> Bool {
        switch status.lowercased() {
        case "completed", "cancelled", "canceled", "failed", "interrupted": true
        default: false
        }
    }

    private static func addIssue(
        count: Int,
        severity: ActivityAuditSeverity,
        code: String,
        message: String,
        to issues: inout [ActivityAuditIssue]
    ) {
        guard count > 0 else { return }
        issues.append(ActivityAuditIssue(severity: severity, code: code, count: count, message: message))
    }
}
