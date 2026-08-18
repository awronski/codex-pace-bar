import Foundation

public enum ActivityThreadActor: String, Codable, CaseIterable, Sendable {
    case user
    case codex
    case automation
    case unknown
}

public enum ActivityCreationMechanism: String, Codable, Sendable {
    case interactive
    case subagentSpawn
    case internalAgent
    case automation
    case fork
    case realtimeVoice
    case unknown
}

public enum ActivityProvenanceConfidence: String, Codable, Sendable {
    case explicit
    case inferred
    case unknown
}

public struct ActivityThreadFact: Codable, Equatable, Sendable {
    public let threadID: String
    public let createdAt: Date
    public let sourceUpdatedAt: Date
    public let sourceRecencyAt: Date
    public let sessionSource: String
    public let threadSource: String?
    public let parentThreadID: String?
    public let forkedFromID: String?
    public let actor: ActivityThreadActor
    public let mechanism: ActivityCreationMechanism
    public let confidence: ActivityProvenanceConfidence
    public let archived: Bool

    public init(
        threadID: String,
        createdAt: Date,
        sourceUpdatedAt: Date,
        sourceRecencyAt: Date,
        sessionSource: String,
        threadSource: String?,
        parentThreadID: String?,
        forkedFromID: String?,
        actor: ActivityThreadActor,
        mechanism: ActivityCreationMechanism,
        confidence: ActivityProvenanceConfidence,
        archived: Bool
    ) {
        self.threadID = threadID
        self.createdAt = createdAt
        self.sourceUpdatedAt = sourceUpdatedAt
        self.sourceRecencyAt = sourceRecencyAt
        self.sessionSource = sessionSource
        self.threadSource = threadSource
        self.parentThreadID = parentThreadID
        self.forkedFromID = forkedFromID
        self.actor = actor
        self.mechanism = mechanism
        self.confidence = confidence
        self.archived = archived
    }
}

public struct ActivityTurnFact: Codable, Equatable, Sendable {
    public let key: String
    public let threadID: String
    public let turnID: String
    public let startedAt: Date?
    public let completedAt: Date?
    public let durationMilliseconds: Int?
    public let status: String

    public var isProvisional: Bool { completedAt == nil }

    public init(
        threadID: String,
        turnID: String,
        startedAt: Date?,
        completedAt: Date?,
        durationMilliseconds: Int?,
        status: String
    ) {
        self.key = Self.key(threadID: threadID, turnID: turnID)
        self.threadID = threadID
        self.turnID = turnID
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationMilliseconds = durationMilliseconds
        self.status = status
    }

    public static func key(threadID: String, turnID: String) -> String {
        "\(threadID):\(turnID)"
    }
}

public enum ActivityInputKind: String, Codable, Sendable {
    case initialTask
    case followUp
    case additionalInputSameTurn
}

public struct ActivityInputFact: Codable, Equatable, Sendable {
    public let key: String
    public let threadID: String
    public let turnID: String
    public let itemID: String
    public let ordinal: Int
    public let actor: ActivityThreadActor
    public let kind: ActivityInputKind
    public let submittedAtEstimate: Date?
    public let textCharacters: Int
    public let utf8Bytes: Int
    public let attachmentCount: Int
    public let skillCount: Int
    public let mentionCount: Int

    public init(
        threadID: String,
        turnID: String,
        itemID: String,
        ordinal: Int,
        actor: ActivityThreadActor,
        kind: ActivityInputKind,
        submittedAtEstimate: Date?,
        textCharacters: Int,
        utf8Bytes: Int,
        attachmentCount: Int,
        skillCount: Int,
        mentionCount: Int
    ) {
        self.key = Self.key(threadID: threadID, turnID: turnID, itemID: itemID, ordinal: ordinal)
        self.threadID = threadID
        self.turnID = turnID
        self.itemID = itemID
        self.ordinal = ordinal
        self.actor = actor
        self.kind = kind
        self.submittedAtEstimate = submittedAtEstimate
        self.textCharacters = textCharacters
        self.utf8Bytes = utf8Bytes
        self.attachmentCount = attachmentCount
        self.skillCount = skillCount
        self.mentionCount = mentionCount
    }

    public static func key(threadID: String, turnID: String, itemID: String, ordinal: Int) -> String {
        "\(threadID):\(turnID):\(itemID):\(ordinal)"
    }

    public func reclassified(as actor: ActivityThreadActor) -> ActivityInputFact {
        ActivityInputFact(
            threadID: threadID,
            turnID: turnID,
            itemID: itemID,
            ordinal: ordinal,
            actor: actor,
            kind: kind,
            submittedAtEstimate: submittedAtEstimate,
            textCharacters: textCharacters,
            utf8Bytes: utf8Bytes,
            attachmentCount: attachmentCount,
            skillCount: skillCount,
            mentionCount: mentionCount
        )
    }
}

public struct ActivityMinuteFact: Codable, Equatable, Sendable {
    public let minuteStart: Date
    public var observedSeconds: Double
    public var activeWithinTwoMinutesSeconds: Double
    public var activeWithinFiveMinutesSeconds: Double
    public var activeWithinTenMinutesSeconds: Double
    public var unavailableSeconds: Double

    public init(
        minuteStart: Date,
        observedSeconds: Double = 0,
        activeWithinTwoMinutesSeconds: Double = 0,
        activeWithinFiveMinutesSeconds: Double = 0,
        activeWithinTenMinutesSeconds: Double = 0,
        unavailableSeconds: Double = 0
    ) {
        self.minuteStart = minuteStart
        self.observedSeconds = observedSeconds
        self.activeWithinTwoMinutesSeconds = activeWithinTwoMinutesSeconds
        self.activeWithinFiveMinutesSeconds = activeWithinFiveMinutesSeconds
        self.activeWithinTenMinutesSeconds = activeWithinTenMinutesSeconds
        self.unavailableSeconds = unavailableSeconds
    }

    public var key: String { String(Int(minuteStart.timeIntervalSince1970)) }
}

public enum ActivityUserState: String, Codable, Sendable {
    case active
    case inactive
    case unknown
}

public enum ActivityCodexFocusState: String, Codable, Sendable {
    case focused
    case notFocused
    case unknown
}

public struct ActivityObservationFact: Codable, Equatable, Sendable {
    public let key: String
    public let intervalStart: Date
    public let intervalEnd: Date
    public let userState: ActivityUserState
    public let codexFocus: ActivityCodexFocusState

    public init(
        intervalStart: Date,
        intervalEnd: Date,
        userState: ActivityUserState,
        codexFocus: ActivityCodexFocusState
    ) {
        self.key = Self.key(intervalEnd: intervalEnd)
        self.intervalStart = intervalStart
        self.intervalEnd = intervalEnd
        self.userState = userState
        self.codexFocus = codexFocus
    }

    public var durationSeconds: TimeInterval {
        intervalEnd.timeIntervalSince(intervalStart)
    }

    public static func key(intervalEnd: Date) -> String {
        String(Int64((intervalEnd.timeIntervalSince1970 * 1_000).rounded()))
    }
}

public enum ActivityCollectorStopReason: String, Codable, Sendable {
    case disabled
    case durationEnded
    case requested
    case interrupted
}

public struct ActivityCollectorState: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let startedAt: Date
    public var lastHeartbeatAt: Date
    public let expectedHeartbeatIntervalSeconds: TimeInterval
    public var stoppedAt: Date?
    public var stopReason: ActivityCollectorStopReason?

    public init(
        sessionID: UUID = UUID(),
        startedAt: Date,
        lastHeartbeatAt: Date,
        expectedHeartbeatIntervalSeconds: TimeInterval,
        stoppedAt: Date? = nil,
        stopReason: ActivityCollectorStopReason? = nil
    ) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.lastHeartbeatAt = lastHeartbeatAt
        self.expectedHeartbeatIntervalSeconds = expectedHeartbeatIntervalSeconds
        self.stoppedAt = stoppedAt
        self.stopReason = stopReason
    }

    public var isRunning: Bool { stoppedAt == nil }
}

public struct ActivityCollectorCoverageMinuteFact: Codable, Equatable, Sendable {
    public let minuteStart: Date
    public var runningSeconds: Double
    public var unknownSeconds: Double

    public init(
        minuteStart: Date,
        runningSeconds: Double = 0,
        unknownSeconds: Double = 0
    ) {
        self.minuteStart = minuteStart
        self.runningSeconds = runningSeconds
        self.unknownSeconds = unknownSeconds
    }

    public var key: String { String(Int(minuteStart.timeIntervalSince1970)) }
}

public struct ActivityObservation: Equatable, Sendable {
    public let timestamp: Date
    public let intervalSeconds: TimeInterval
    public let idleSeconds: TimeInterval?
    public let codexFocus: ActivityCodexFocusState

    public init(
        timestamp: Date,
        intervalSeconds: TimeInterval,
        idleSeconds: TimeInterval?,
        codexFocus: ActivityCodexFocusState = .unknown
    ) {
        self.timestamp = timestamp
        self.intervalSeconds = intervalSeconds
        self.idleSeconds = idleSeconds
        self.codexFocus = codexFocus
    }

    public var fact: ActivityObservationFact? {
        let seconds = max(0, min(intervalSeconds, 60))
        guard seconds > 0 else { return nil }
        let userState: ActivityUserState
        if let idleSeconds, idleSeconds.isFinite, idleSeconds >= 0 {
            userState = idleSeconds < 5 * 60 ? .active : .inactive
        } else {
            userState = .unknown
        }
        return ActivityObservationFact(
            intervalStart: timestamp.addingTimeInterval(-seconds),
            intervalEnd: timestamp,
            userState: userState,
            codexFocus: codexFocus
        )
    }

    public var minuteFacts: [ActivityMinuteFact] {
        let seconds = max(0, min(intervalSeconds, 60))
        guard seconds > 0 else { return [] }

        let intervalStart = timestamp.addingTimeInterval(-seconds)
        var cursor = intervalStart
        var facts: [ActivityMinuteFact] = []
        while cursor < timestamp {
            let minute = Date(timeIntervalSince1970: floor(cursor.timeIntervalSince1970 / 60) * 60)
            let minuteEnd = minute.addingTimeInterval(60)
            let segmentEnd = min(minuteEnd, timestamp)
            let segmentSeconds = max(0, segmentEnd.timeIntervalSince(cursor))
            guard segmentSeconds > 0 else { break }

            if let idleSeconds, idleSeconds.isFinite, idleSeconds >= 0 {
                facts.append(ActivityMinuteFact(
                    minuteStart: minute,
                    observedSeconds: segmentSeconds,
                    activeWithinTwoMinutesSeconds: idleSeconds < 2 * 60 ? segmentSeconds : 0,
                    activeWithinFiveMinutesSeconds: idleSeconds < 5 * 60 ? segmentSeconds : 0,
                    activeWithinTenMinutesSeconds: idleSeconds < 10 * 60 ? segmentSeconds : 0
                ))
            } else {
                facts.append(ActivityMinuteFact(
                    minuteStart: minute,
                    unavailableSeconds: segmentSeconds
                ))
            }
            cursor = segmentEnd
        }
        return facts
    }
}

public struct ActivityCollectionRun: Codable, Equatable, Sendable {
    public let runID: UUID
    public let startedAt: Date
    public let finishedAt: Date
    public let pagesRead: Int
    public let threadsSeen: Int
    public let threadsCollected: Int
    public let threadsUnchanged: Int
    public let threadsDeferred: Int
    public let threadsKnownFailed: Int
    public let turnsCollected: Int
    public let inputsCollected: Int
    public let threadFailures: Int
    public let failureCounts: [String: Int]
    public let lookbackSeconds: TimeInterval?

    public init(
        runID: UUID = UUID(),
        startedAt: Date,
        finishedAt: Date,
        pagesRead: Int,
        threadsSeen: Int,
        threadsCollected: Int,
        threadsUnchanged: Int,
        threadsDeferred: Int = 0,
        threadsKnownFailed: Int = 0,
        turnsCollected: Int,
        inputsCollected: Int,
        threadFailures: Int,
        failureCounts: [String: Int] = [:],
        lookbackSeconds: TimeInterval? = nil
    ) {
        self.runID = runID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.pagesRead = pagesRead
        self.threadsSeen = threadsSeen
        self.threadsCollected = threadsCollected
        self.threadsUnchanged = threadsUnchanged
        self.threadsDeferred = threadsDeferred
        self.threadsKnownFailed = threadsKnownFailed
        self.turnsCollected = turnsCollected
        self.inputsCollected = inputsCollected
        self.threadFailures = threadFailures
        self.failureCounts = failureCounts
        self.lookbackSeconds = lookbackSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case runID
        case startedAt
        case finishedAt
        case pagesRead
        case threadsSeen
        case threadsCollected
        case threadsUnchanged
        case threadsDeferred
        case threadsKnownFailed
        case turnsCollected
        case inputsCollected
        case threadFailures
        case failureCounts
        case lookbackSeconds
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        runID = try values.decode(UUID.self, forKey: .runID)
        startedAt = try values.decode(Date.self, forKey: .startedAt)
        finishedAt = try values.decode(Date.self, forKey: .finishedAt)
        pagesRead = try values.decode(Int.self, forKey: .pagesRead)
        threadsSeen = try values.decode(Int.self, forKey: .threadsSeen)
        threadsCollected = try values.decode(Int.self, forKey: .threadsCollected)
        threadsUnchanged = try values.decode(Int.self, forKey: .threadsUnchanged)
        threadsDeferred = try values.decodeIfPresent(Int.self, forKey: .threadsDeferred) ?? 0
        threadsKnownFailed = try values.decodeIfPresent(Int.self, forKey: .threadsKnownFailed) ?? 0
        turnsCollected = try values.decode(Int.self, forKey: .turnsCollected)
        inputsCollected = try values.decode(Int.self, forKey: .inputsCollected)
        threadFailures = try values.decode(Int.self, forKey: .threadFailures)
        failureCounts = try values.decodeIfPresent([String: Int].self, forKey: .failureCounts) ?? [:]
        lookbackSeconds = try values.decodeIfPresent(TimeInterval.self, forKey: .lookbackSeconds)
    }
}

public struct ActivityCollectionBatch: Equatable, Sendable {
    public let threads: [ActivityThreadFact]
    public let turns: [ActivityTurnFact]
    public let inputs: [ActivityInputFact]
    public let refreshedThreadIDs: Set<String>
    public let attemptedThreadIDs: Set<String>
    public let run: ActivityCollectionRun

    public init(
        threads: [ActivityThreadFact],
        turns: [ActivityTurnFact],
        inputs: [ActivityInputFact],
        refreshedThreadIDs: Set<String>,
        attemptedThreadIDs: Set<String>? = nil,
        run: ActivityCollectionRun
    ) {
        self.threads = threads
        self.turns = turns
        self.inputs = inputs
        self.refreshedThreadIDs = refreshedThreadIDs
        self.attemptedThreadIDs = attemptedThreadIDs ?? refreshedThreadIDs
        self.run = run
    }
}

public struct ActivityInsightsArchive: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 4

    public var schemaVersion: Int
    public var generatedAt: Date
    public var threads: [String: ActivityThreadFact]
    public var turns: [String: ActivityTurnFact]
    public var inputs: [String: ActivityInputFact]
    public var historyAttemptVersions: [String: Date]
    public var historySyncVersions: [String: Date]
    public var historyFailureVersions: [String: Date]
    public var historyFailureAttemptCounts: [String: Int]
    public var activityMinutes: [String: ActivityMinuteFact]
    public var observationFacts: [String: ActivityObservationFact]
    public var collectorCoverageMinutes: [String: ActivityCollectorCoverageMinuteFact]
    public var collectorState: ActivityCollectorState?
    public var collectorSessionCount: Int
    public var collectionRuns: [ActivityCollectionRun]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        generatedAt: Date = Date(timeIntervalSince1970: 0),
        threads: [String: ActivityThreadFact] = [:],
        turns: [String: ActivityTurnFact] = [:],
        inputs: [String: ActivityInputFact] = [:],
        historyAttemptVersions: [String: Date] = [:],
        historySyncVersions: [String: Date] = [:],
        historyFailureVersions: [String: Date] = [:],
        historyFailureAttemptCounts: [String: Int] = [:],
        activityMinutes: [String: ActivityMinuteFact] = [:],
        observationFacts: [String: ActivityObservationFact] = [:],
        collectorCoverageMinutes: [String: ActivityCollectorCoverageMinuteFact] = [:],
        collectorState: ActivityCollectorState? = nil,
        collectorSessionCount: Int = 0,
        collectionRuns: [ActivityCollectionRun] = []
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.threads = threads
        self.turns = turns
        self.inputs = inputs
        self.historyAttemptVersions = historyAttemptVersions
        self.historySyncVersions = historySyncVersions
        self.historyFailureVersions = historyFailureVersions
        self.historyFailureAttemptCounts = historyFailureAttemptCounts
        self.activityMinutes = activityMinutes
        self.observationFacts = observationFacts
        self.collectorCoverageMinutes = collectorCoverageMinutes
        self.collectorState = collectorState
        self.collectorSessionCount = collectorSessionCount
        self.collectionRuns = collectionRuns
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case generatedAt
        case threads
        case turns
        case inputs
        case historyAttemptVersions
        case historySyncVersions
        case historyFailureVersions
        case historyFailureAttemptCounts
        case activityMinutes
        case observationFacts
        case collectorCoverageMinutes
        case collectorState
        case collectorSessionCount
        case collectionRuns
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let storedSchemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        guard [2, 3, Self.currentSchemaVersion].contains(storedSchemaVersion) else {
            throw ActivityInsightsError.unsupportedSchema(storedSchemaVersion)
        }
        schemaVersion = Self.currentSchemaVersion
        generatedAt = try values.decode(Date.self, forKey: .generatedAt)
        threads = try values.decode([String: ActivityThreadFact].self, forKey: .threads)
        turns = try values.decode([String: ActivityTurnFact].self, forKey: .turns)
        inputs = try values.decode([String: ActivityInputFact].self, forKey: .inputs)
        historyAttemptVersions = try values.decodeIfPresent([String: Date].self, forKey: .historyAttemptVersions) ?? [:]
        historySyncVersions = try values.decodeIfPresent([String: Date].self, forKey: .historySyncVersions) ?? [:]
        historyFailureVersions = try values.decodeIfPresent([String: Date].self, forKey: .historyFailureVersions) ?? [:]
        historyFailureAttemptCounts = try values.decodeIfPresent(
            [String: Int].self,
            forKey: .historyFailureAttemptCounts
        ) ?? [:]
        activityMinutes = try values.decode([String: ActivityMinuteFact].self, forKey: .activityMinutes)
        observationFacts = try values.decodeIfPresent(
            [String: ActivityObservationFact].self,
            forKey: .observationFacts
        ) ?? [:]
        collectorCoverageMinutes = try values.decodeIfPresent(
            [String: ActivityCollectorCoverageMinuteFact].self,
            forKey: .collectorCoverageMinutes
        ) ?? [:]
        collectorState = try values.decodeIfPresent(ActivityCollectorState.self, forKey: .collectorState)
        collectorSessionCount = try values.decodeIfPresent(Int.self, forKey: .collectorSessionCount) ?? 0
        collectionRuns = try values.decode([ActivityCollectionRun].self, forKey: .collectionRuns)
    }
}
