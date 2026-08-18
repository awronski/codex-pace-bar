import Foundation

public struct ActivityHistoryCollectionConfiguration: Equatable, Sendable {
    public var lookbackDuration: TimeInterval
    public var pageLimit: Int
    public var requestTimeout: TimeInterval
    public var maximumThreadsPerRun: Int
    public var retryKnownFailures: Bool
    public var retryKnownFailureThreadID: String?
    public var preferPaginatedTurns: Bool

    public init(
        lookbackDuration: TimeInterval = 30 * 24 * 60 * 60,
        pageLimit: Int = 100,
        requestTimeout: TimeInterval = 10,
        maximumThreadsPerRun: Int = 20,
        retryKnownFailures: Bool = false,
        retryKnownFailureThreadID: String? = nil,
        preferPaginatedTurns: Bool = false
    ) {
        self.lookbackDuration = lookbackDuration
        self.pageLimit = pageLimit
        self.requestTimeout = requestTimeout
        self.maximumThreadsPerRun = max(1, maximumThreadsPerRun)
        self.retryKnownFailures = retryKnownFailures
        self.retryKnownFailureThreadID = retryKnownFailureThreadID
        self.preferPaginatedTurns = preferPaginatedTurns
    }
}

public protocol ActivityHistoryCollecting: Sendable {
    func collect(existing: ActivityInsightsArchive) async throws -> ActivityCollectionBatch
    func shutdown() async
}

public actor ActivityHistoryCollector: ActivityHistoryCollecting {
    public enum FailureKind: String, Sendable {
        case metadataParse = "metadata_parse"
        case historyTimeout = "history_timeout"
        case historyProtocol = "history_protocol"
        case historyParse = "history_parse"
    }

    public static let allSourceKinds = [
        "cli",
        "vscode",
        "exec",
        "appServer",
        "subAgent",
        "subAgentReview",
        "subAgentCompact",
        "subAgentThreadSpawn",
        "subAgentOther",
        "unknown"
    ]

    private let client: any ActivityAppServerRequesting
    private let configuration: ActivityHistoryCollectionConfiguration
    private let clock: @Sendable () -> Date

    public init(
        client: any ActivityAppServerRequesting,
        configuration: ActivityHistoryCollectionConfiguration = .init(),
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.client = client
        self.configuration = configuration
        self.clock = clock
    }

    public func collect(existing: ActivityInsightsArchive = .init()) async throws -> ActivityCollectionBatch {
        let startedAt = clock()
        let cutoff = startedAt.addingTimeInterval(-configuration.lookbackDuration)
        var pageCount = 0
        var threadsSeen = 0
        var failures = 0
        var failureCounts: [String: Int] = [:]
        var collectedThreads: [String: ActivityThreadFact] = [:]

        for archived in [false, true] {
            var cursor: String?
            repeat {
                let response = try await listThreads(archived: archived, cursor: cursor)
                pageCount += 1
                guard let object = response.objectValue,
                      let values = object["data"]?.arrayValue
                else {
                    throw ActivityInsightsError.invalidResponse("thread/list did not return data.")
                }
                threadsSeen += values.count

                var parsedPage: [ActivityThreadFact] = []
                for value in values {
                    let fact: ActivityThreadFact
                    do {
                        fact = try ActivityHistoryParser.thread(from: value, archived: archived)
                    } catch {
                        failures += 1
                        failureCounts[FailureKind.metadataParse.rawValue, default: 0] += 1
                        continue
                    }
                    parsedPage.append(fact)
                    if fact.sourceRecencyAt >= cutoff {
                        collectedThreads[fact.threadID] = fact
                    }
                }

                cursor = object["nextCursor"]?.stringValue
                if !parsedPage.isEmpty, parsedPage.allSatisfy({ $0.sourceRecencyAt < cutoff }) {
                    cursor = nil
                }
            } while cursor != nil
        }

        let threads = collectedThreads.values.sorted {
            if $0.sourceRecencyAt == $1.sourceRecencyAt { return $0.threadID < $1.threadID }
            return $0.sourceRecencyAt < $1.sourceRecencyAt
        }
        var changedThreads: [ActivityThreadFact] = []
        var quarantinedThreads: [ActivityThreadFact] = []
        var refreshedThreadIDs: Set<String> = []
        var unchanged = 0
        var knownFailed = 0

        for thread in threads {
            if existing.historySyncVersions[thread.threadID] == thread.sourceUpdatedAt {
                unchanged += 1
                continue
            }
            let isKnownFailure = existing.historyFailureVersions[thread.threadID]
                == thread.sourceUpdatedAt
            if isKnownFailure {
                knownFailed += 1
                if configuration.retryKnownFailures,
                   configuration.retryKnownFailureThreadID.map({ $0 == thread.threadID }) ?? true {
                    changedThreads.append(thread)
                } else if !configuration.retryKnownFailures {
                    quarantinedThreads.append(thread)
                }
                continue
            }
            if configuration.retryKnownFailures { continue }
            changedThreads.append(thread)
        }

        // Keep fresh work first, but always leave the remaining checkpoint capacity available to
        // quarantined histories. A continuously changing task must not keep every known failure
        // quarantined forever.
        if !configuration.retryKnownFailures {
            changedThreads.append(contentsOf: quarantinedThreads)
        }

        changedThreads.sort { left, right in
            // A large task can keep changing while every full-history read times out. Prefer
            // tasks that have never failed so that one hot task ID cannot starve the backlog
            // merely by presenting a new source version at every checkpoint.
            let leftPreviouslyFailed = existing.historyFailureVersions[left.threadID] != nil
            let rightPreviouslyFailed = existing.historyFailureVersions[right.threadID] != nil
            if leftPreviouslyFailed != rightPreviouslyFailed { return !leftPreviouslyFailed }
            if leftPreviouslyFailed {
                let leftFailureAttempts = existing.historyFailureAttemptCounts[left.threadID, default: 0]
                let rightFailureAttempts = existing.historyFailureAttemptCounts[right.threadID, default: 0]
                if leftFailureAttempts != rightFailureAttempts {
                    return leftFailureAttempts < rightFailureAttempts
                }
                if left.sourceRecencyAt != right.sourceRecencyAt {
                    return left.sourceRecencyAt < right.sourceRecencyAt
                }
            }
            let leftAttempted = existing.historyAttemptVersions[left.threadID] == left.sourceUpdatedAt
            let rightAttempted = existing.historyAttemptVersions[right.threadID] == right.sourceUpdatedAt
            if leftAttempted != rightAttempted { return !leftAttempted }
            if left.sourceRecencyAt != right.sourceRecencyAt {
                return left.sourceRecencyAt > right.sourceRecencyAt
            }
            return left.threadID < right.threadID
        }
        let selectedThreads = Array(changedThreads.prefix(configuration.maximumThreadsPerRun))

        var histories: [String: CollectedThreadHistory] = [:]
        var processedThreads: [ActivityThreadFact] = []
        for thread in selectedThreads {
            let history = await collectHistory(
                for: thread,
                preferPaginatedTurns: configuration.preferPaginatedTurns
                    || (!configuration.retryKnownFailures
                        && existing.historyFailureVersions[thread.threadID] != nil)
            )
            histories[thread.threadID] = history
            processedThreads.append(thread)
            if history.failureKind == .historyTimeout || history.failureKind == .historyProtocol {
                break
            }
        }
        let attemptedThreadIDs = Set(processedThreads.map(\.threadID))
        let deferred = max(0, changedThreads.count - processedThreads.count)

        var turns: [ActivityTurnFact] = []
        var inputs: [ActivityInputFact] = []
        for thread in processedThreads {
            guard let history = histories[thread.threadID], history.failureKind == nil else {
                failures += 1
                if let kind = histories[thread.threadID]?.failureKind {
                    failureCounts[kind.rawValue, default: 0] += 1
                }
                continue
            }
            refreshedThreadIDs.insert(thread.threadID)
            turns.append(contentsOf: history.turns)
            inputs.append(contentsOf: history.inputs)
        }

        let run = ActivityCollectionRun(
            startedAt: startedAt,
            finishedAt: clock(),
            pagesRead: pageCount,
            threadsSeen: threadsSeen,
            threadsCollected: processedThreads.count,
            threadsUnchanged: unchanged,
            threadsDeferred: deferred,
            threadsKnownFailed: knownFailed,
            turnsCollected: turns.count,
            inputsCollected: inputs.count,
            threadFailures: failures,
            failureCounts: failureCounts,
            lookbackSeconds: configuration.lookbackDuration
        )
        return ActivityCollectionBatch(
            threads: threads,
            turns: turns,
            inputs: inputs,
            refreshedThreadIDs: refreshedThreadIDs,
            attemptedThreadIDs: attemptedThreadIDs,
            run: run
        )
    }

    public func shutdown() async {
        await client.shutdown()
    }

    private func collectHistory(
        for thread: ActivityThreadFact,
        preferPaginatedTurns: Bool
    ) async -> CollectedThreadHistory {
        let values: [ActivityJSONValue]
        do {
            values = try await listTurns(
                threadID: thread.threadID,
                preferPaginatedTurns: preferPaginatedTurns
            )
        } catch let error as ActivityInsightsError {
            let kind: FailureKind
            if case .appServerTimeout = error {
                kind = .historyTimeout
            } else {
                kind = .historyProtocol
            }
            return CollectedThreadHistory(
                threadID: thread.threadID,
                turns: [],
                inputs: [],
                failureKind: kind
            )
        } catch {
            return CollectedThreadHistory(
                threadID: thread.threadID,
                turns: [],
                inputs: [],
                failureKind: .historyProtocol
            )
        }

        do {
            let parsed = try ActivityHistoryParser.turnFacts(from: values, thread: thread)
            return CollectedThreadHistory(
                threadID: thread.threadID,
                turns: parsed.turns,
                inputs: parsed.inputs,
                failureKind: nil
            )
        } catch {
            return CollectedThreadHistory(
                threadID: thread.threadID,
                turns: [],
                inputs: [],
                failureKind: .historyParse
            )
        }
    }

    private func listThreads(archived: Bool, cursor: String?) async throws -> ActivityJSONValue {
        var params: [String: ActivityJSONValue] = [
            "limit": .number(Double(configuration.pageLimit)),
            "sortKey": .string("recency_at"),
            "sortDirection": .string("desc"),
            "sourceKinds": .array(Self.allSourceKinds.map(ActivityJSONValue.string)),
            "archived": .bool(archived)
        ]
        if let cursor { params["cursor"] = .string(cursor) }
        return try await client.request(
            method: "thread/list",
            params: .object(params),
            timeoutSeconds: configuration.requestTimeout
        )
    }

    private func listTurns(
        threadID: String,
        preferPaginatedTurns: Bool
    ) async throws -> [ActivityJSONValue] {
        if preferPaginatedTurns {
            return try await listTurnsPaginated(threadID: threadID)
        }
        do {
            return try await readTurns(threadID: threadID)
        } catch let error as ActivityInsightsError {
            guard case let .jsonRPC(code, _) = error, code == -32601 || code == -32602 else {
                throw error
            }
            return try await listTurnsPaginated(threadID: threadID)
        }
    }

    private func listTurnsPaginated(threadID: String) async throws -> [ActivityJSONValue] {
        var cursor: String?
        var turns: [ActivityJSONValue] = []
        repeat {
            var params: [String: ActivityJSONValue] = [
                "threadId": .string(threadID),
                "limit": .number(Double(configuration.pageLimit)),
                "sortDirection": .string("asc"),
                "itemsView": .string("full")
            ]
            if let cursor { params["cursor"] = .string(cursor) }
            let response = try await client.request(
                method: "thread/turns/list",
                params: .object(params),
                timeoutSeconds: configuration.requestTimeout
            )
            guard let object = response.objectValue,
                  let values = object["data"]?.arrayValue
            else {
                throw ActivityInsightsError.invalidResponse("thread/turns/list did not return data.")
            }
            turns.append(contentsOf: values)
            cursor = object["nextCursor"]?.stringValue
        } while cursor != nil
        return turns
    }

    private func readTurns(threadID: String) async throws -> [ActivityJSONValue] {
        let response = try await client.request(
            method: "thread/read",
            params: .object([
                "threadId": .string(threadID),
                "includeTurns": .bool(true)
            ]),
            timeoutSeconds: configuration.requestTimeout
        )
        guard let turns = response["thread"]?["turns"]?.arrayValue else {
            throw ActivityInsightsError.invalidResponse("thread/read did not return turns.")
        }
        return turns
    }
}

private struct CollectedThreadHistory: Sendable {
    let threadID: String
    let turns: [ActivityTurnFact]
    let inputs: [ActivityInputFact]
    let failureKind: ActivityHistoryCollector.FailureKind?
}
