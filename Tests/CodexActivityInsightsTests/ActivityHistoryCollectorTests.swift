import CodexActivityInsightsCore
import Foundation
import Testing

@Suite
struct ActivityHistoryCollectorTests {
    @Test
    func collectsAllSourcesPagesArchivedThreadsAndFallsBackToPaginatedTurns() async throws {
        let userThread = try testJSON(#"{"id":"user","createdAt":1700,"updatedAt":1750,"recencyAt":1900,"source":"vscode","threadSource":"user"}"#)
        let oldThread = try testJSON(#"{"id":"old","createdAt":400,"updatedAt":500,"recencyAt":500,"source":"cli"}"#)
        let automationThread = try testJSON(#"{"id":"automation","createdAt":1600,"updatedAt":1650,"recencyAt":1800,"source":"exec","threadSource":"automation"}"#)
        let automationTurn = try testJSON(#"{"id":"a-turn","startedAt":1801,"completedAt":1802,"durationMs":1000,"items":[{"id":"a-input","type":"userMessage","content":[{"type":"text","text":"automated"}]}]}"#)
        let userTurnOne = try testJSON(#"{"id":"u-turn-1","startedAt":1901,"completedAt":1902,"durationMs":1000,"items":[{"id":"u-input-1","type":"userMessage","content":[{"type":"text","text":"initial"}]}]}"#)
        let userTurnTwo = try testJSON(#"{"id":"u-turn-2","startedAt":1903,"completedAt":1905,"durationMs":2000,"items":[{"id":"u-input-2","type":"userMessage","content":[{"type":"text","text":"followup"}]}]}"#)
        let server = ScriptedActivityAppServer(responses: [
            "thread/list": [
                .success(listResponse([userThread], nextCursor: "active-2")),
                .success(listResponse([oldThread], nextCursor: "must-not-be-requested")),
                .success(listResponse([automationThread]))
            ],
            "thread/read": [
                .success(readResponse([automationTurn])),
                .failure(.jsonRPC(code: -32601, message: "not available"))
            ],
            "thread/turns/list": [
                .success(listResponse([userTurnOne], nextCursor: "turn-2")),
                .success(listResponse([userTurnTwo]))
            ]
        ])
        let collector = ActivityHistoryCollector(
            client: server,
            configuration: .init(
                lookbackDuration: 1_000,
                pageLimit: 1,
                requestTimeout: 3,
                maximumThreadsPerRun: 100
            ),
            clock: { testDate(2_000) }
        )

        let batch = try await collector.collect(existing: .init())
        let requests = await server.recordedRequests()

        #expect(batch.threads.map(\.threadID) == ["automation", "user"])
        #expect(batch.turns.map(\.turnID) == ["a-turn", "u-turn-1", "u-turn-2"])
        #expect(batch.inputs.map(\.kind) == [.initialTask, .initialTask, .followUp])
        #expect(batch.refreshedThreadIDs == ["automation", "user"])
        #expect(batch.run.pagesRead == 3)
        #expect(batch.run.threadsSeen == 3)
        #expect(batch.run.threadsCollected == 2)
        #expect(batch.run.turnsCollected == 3)
        #expect(batch.run.inputsCollected == 3)
        #expect(batch.run.threadFailures == 0)

        let listRequests = requests.filter { $0.method == "thread/list" }
        #expect(listRequests.count == 3)
        #expect(listRequests[0].params?["sourceKinds"]?.arrayValue?.map(\.stringValue).compactMap { $0 }
            == ActivityHistoryCollector.allSourceKinds)
        #expect(listRequests[0].params?["archived"] == .bool(false))
        #expect(listRequests[2].params?["archived"] == .bool(true))
        #expect(!requests.contains { $0.params?["cursor"] == .string("must-not-be-requested") })
        #expect(requests.contains { $0.method == "thread/read" && $0.params?["threadId"] == .string("automation") })
        #expect(requests.contains { $0.method == "thread/read" && $0.params?["threadId"] == .string("user") })
        #expect(requests.filter { $0.method == "thread/turns/list" }.allSatisfy {
            $0.params?["itemsView"] == .string("full")
        })
    }

    @Test
    func unchangedThreadKeepsHistoryWithoutRequestingTurns() async throws {
        let threadJSON = try testJSON(#"{"id":"thread-1","createdAt":1000,"updatedAt":1100,"recencyAt":1200,"source":"vscode","threadSource":"user"}"#)
        let server = ScriptedActivityAppServer(responses: [
            "thread/list": [
                .success(listResponse([threadJSON])),
                .success(listResponse([]))
            ]
        ])
        let existingThread = testThread(updatedAt: testDate(1_100), recencyAt: testDate(1_100))
        let turn = testTurn()
        let existing = ActivityInsightsArchive(
            threads: [existingThread.threadID: existingThread],
            turns: [turn.key: turn],
            historySyncVersions: [existingThread.threadID: existingThread.sourceUpdatedAt]
        )
        let collector = ActivityHistoryCollector(
            client: server,
            configuration: .init(lookbackDuration: 1_000),
            clock: { testDate(2_000) }
        )

        let batch = try await collector.collect(existing: existing)
        let requests = await server.recordedRequests()

        #expect(batch.threads.count == 1)
        #expect(batch.turns.isEmpty)
        #expect(batch.inputs.isEmpty)
        #expect(batch.refreshedThreadIDs.isEmpty)
        #expect(batch.run.threadsUnchanged == 1)
        #expect(!requests.contains { $0.method == "thread/read" || $0.method == "thread/turns/list" })
    }

    @Test
    func checkpointPrioritizesNeverAttemptedThreadsAndReportsDeferredWork() async throws {
        let a = try testJSON(#"{"id":"a","createdAt":1000,"updatedAt":1100,"recencyAt":1200,"source":"vscode","threadSource":"user"}"#)
        let b = try testJSON(#"{"id":"b","createdAt":1000,"updatedAt":1100,"recencyAt":1300,"source":"vscode","threadSource":"user"}"#)
        let c = try testJSON(#"{"id":"c","createdAt":1000,"updatedAt":1100,"recencyAt":1400,"source":"vscode","threadSource":"user"}"#)
        let server = ScriptedActivityAppServer(responses: [
            "thread/list": [
                .success(listResponse([a, b, c])),
                .success(listResponse([]))
            ],
            "thread/read": [
                .success(readResponse([])),
                .success(readResponse([]))
            ]
        ])
        let existing = ActivityInsightsArchive(
            historyAttemptVersions: ["a": testDate(1_100)]
        )
        let collector = ActivityHistoryCollector(
            client: server,
            configuration: .init(
                lookbackDuration: 1_000,
                maximumThreadsPerRun: 2
            ),
            clock: { testDate(2_000) }
        )

        let batch = try await collector.collect(existing: existing)
        let requestedThreadIDs = await server.recordedRequests()
            .filter { $0.method == "thread/read" }
            .compactMap { $0.params?["threadId"]?.stringValue }

        #expect(requestedThreadIDs == ["c", "b"])
        #expect(batch.attemptedThreadIDs == ["b", "c"])
        #expect(batch.refreshedThreadIDs == ["b", "c"])
        #expect(batch.run.threadsCollected == 2)
        #expect(batch.run.threadsDeferred == 1)
    }

    @Test
    func timeoutEndsCheckpointSoNextHistoryUsesFreshServerProcess() async throws {
        let first = try testJSON(#"{"id":"first","createdAt":1000,"updatedAt":1100,"recencyAt":1200,"source":"vscode","threadSource":"user"}"#)
        let second = try testJSON(#"{"id":"second","createdAt":1000,"updatedAt":1100,"recencyAt":1300,"source":"vscode","threadSource":"user"}"#)
        let server = ScriptedActivityAppServer(responses: [
            "thread/list": [
                .success(listResponse([first, second])),
                .success(listResponse([]))
            ],
            "thread/read": [
                .failure(.appServerTimeout("thread/turns/list")),
                .success(readResponse([]))
            ]
        ])
        let collector = ActivityHistoryCollector(
            client: server,
            configuration: .init(lookbackDuration: 1_000, maximumThreadsPerRun: 2),
            clock: { testDate(2_000) }
        )

        let batch = try await collector.collect(existing: .init())
        let requestedThreadIDs = await server.recordedRequests()
            .filter { $0.method == "thread/read" }
            .compactMap { $0.params?["threadId"]?.stringValue }

        #expect(requestedThreadIDs == ["second"])
        #expect(batch.attemptedThreadIDs == ["second"])
        #expect(batch.run.threadsCollected == 1)
        #expect(batch.run.threadsDeferred == 1)
        #expect(batch.run.failureCounts == ["history_timeout": 1])
    }

    @Test
    func knownFailedVersionDoesNotBlockUnattemptedHistory() async throws {
        let failed = try testJSON(#"{"id":"failed","createdAt":1000,"updatedAt":1100,"recencyAt":1200,"source":"vscode","threadSource":"user"}"#)
        let unattempted = try testJSON(#"{"id":"unattempted","createdAt":1000,"updatedAt":1100,"recencyAt":1300,"source":"vscode","threadSource":"user"}"#)
        let server = ScriptedActivityAppServer(responses: [
            "thread/list": [
                .success(listResponse([failed, unattempted])),
                .success(listResponse([]))
            ],
            "thread/read": [.success(readResponse([]))]
        ])
        let collector = ActivityHistoryCollector(
            client: server,
            configuration: .init(lookbackDuration: 1_000, maximumThreadsPerRun: 1),
            clock: { testDate(2_000) }
        )
        let existing = ActivityInsightsArchive(
            historyFailureVersions: ["failed": testDate(1_100)]
        )

        let batch = try await collector.collect(existing: existing)

        #expect(batch.attemptedThreadIDs == ["unattempted"])
        #expect(batch.run.threadsKnownFailed == 1)
        #expect(batch.run.threadsDeferred == 1)
    }

    @Test
    func freshWorkUsesRemainingCheckpointCapacityForKnownFailures() async throws {
        let fresh = try testJSON(#"{"id":"fresh","createdAt":1000,"updatedAt":1100,"recencyAt":1300,"source":"vscode","threadSource":"user"}"#)
        let failed = try testJSON(#"{"id":"failed","createdAt":1000,"updatedAt":1100,"recencyAt":1200,"source":"vscode","threadSource":"user"}"#)
        let server = ScriptedActivityAppServer(responses: [
            "thread/list": [
                .success(listResponse([fresh, failed])),
                .success(listResponse([]))
            ],
            "thread/read": [.success(readResponse([]))],
            "thread/turns/list": [.success(listResponse([]))]
        ])
        let collector = ActivityHistoryCollector(
            client: server,
            configuration: .init(lookbackDuration: 1_000, maximumThreadsPerRun: 2),
            clock: { testDate(2_000) }
        )
        let existing = ActivityInsightsArchive(
            historyFailureVersions: ["failed": testDate(1_100)]
        )

        let batch = try await collector.collect(existing: existing)
        let requestedThreadIDs = await server.recordedRequests()
            .filter { $0.method == "thread/read" || $0.method == "thread/turns/list" }
            .compactMap { $0.params?["threadId"]?.stringValue }

        #expect(requestedThreadIDs == ["fresh", "failed"])
        #expect(batch.refreshedThreadIDs == ["fresh", "failed"])
        #expect(batch.run.threadsDeferred == 0)
    }

    @Test
    func leastRetriedKnownFailureRunsFirst() async throws {
        let heavilyRetried = try testJSON(#"{"id":"heavy","createdAt":1000,"updatedAt":1100,"recencyAt":1100,"source":"vscode","threadSource":"user"}"#)
        let lightlyRetried = try testJSON(#"{"id":"light","createdAt":1000,"updatedAt":1100,"recencyAt":1200,"source":"vscode","threadSource":"user"}"#)
        let server = ScriptedActivityAppServer(responses: [
            "thread/list": [
                .success(listResponse([heavilyRetried, lightlyRetried])),
                .success(listResponse([]))
            ],
            "thread/turns/list": [.success(listResponse([]))]
        ])
        let collector = ActivityHistoryCollector(
            client: server,
            configuration: .init(lookbackDuration: 1_000, maximumThreadsPerRun: 1),
            clock: { testDate(2_000) }
        )
        let existing = ActivityInsightsArchive(
            historyFailureVersions: [
                "heavy": testDate(1_100),
                "light": testDate(1_100)
            ],
            historyFailureAttemptCounts: ["heavy": 4, "light": 1]
        )

        let batch = try await collector.collect(existing: existing)
        let requestedThreadIDs = await server.recordedRequests()
            .filter { $0.method == "thread/turns/list" }
            .compactMap { $0.params?["threadId"]?.stringValue }

        #expect(requestedThreadIDs == ["light"])
        #expect(batch.refreshedThreadIDs == ["light"])
        #expect(batch.run.threadsDeferred == 1)
    }

    @Test
    func knownFailedVersionRetriesWithPaginationAfterBacklogIsEmpty() async throws {
        let failed = try testJSON(#"{"id":"failed","createdAt":1000,"updatedAt":1100,"recencyAt":1200,"source":"vscode","threadSource":"user"}"#)
        let turn = try testJSON(#"{"id":"turn-1","startedAt":1201,"completedAt":1202,"items":[]}"#)
        let server = ScriptedActivityAppServer(responses: [
            "thread/list": [
                .success(listResponse([failed])),
                .success(listResponse([]))
            ],
            "thread/turns/list": [.success(listResponse([turn]))]
        ])
        let collector = ActivityHistoryCollector(
            client: server,
            configuration: .init(lookbackDuration: 1_000),
            clock: { testDate(2_000) }
        )
        let existing = ActivityInsightsArchive(
            historyFailureVersions: ["failed": testDate(1_100)]
        )

        let batch = try await collector.collect(existing: existing)
        let requests = await server.recordedRequests()

        #expect(batch.refreshedThreadIDs == ["failed"])
        #expect(batch.turns.map(\.turnID) == ["turn-1"])
        #expect(batch.run.threadsKnownFailed == 1)
        #expect(!requests.contains { $0.method == "thread/read" })
        #expect(requests.filter { $0.method == "thread/turns/list" }.count == 1)
    }

    @Test
    func changedVersionOfPreviouslyFailingThreadDoesNotStarveBacklog() async throws {
        let failing = try testJSON(#"{"id":"failing","createdAt":1000,"updatedAt":1150,"recencyAt":1500,"source":"vscode","threadSource":"user"}"#)
        let backlog = try testJSON(#"{"id":"backlog","createdAt":1000,"updatedAt":1100,"recencyAt":1200,"source":"vscode","threadSource":"user"}"#)
        let server = ScriptedActivityAppServer(responses: [
            "thread/list": [
                .success(listResponse([failing, backlog])),
                .success(listResponse([]))
            ],
            "thread/read": [.success(readResponse([]))]
        ])
        let collector = ActivityHistoryCollector(
            client: server,
            configuration: .init(lookbackDuration: 1_000, maximumThreadsPerRun: 1),
            clock: { testDate(2_000) }
        )
        let existing = ActivityInsightsArchive(
            historyFailureVersions: ["failing": testDate(1_100)]
        )

        let batch = try await collector.collect(existing: existing)
        let requestedThreadIDs = await server.recordedRequests()
            .filter { $0.method == "thread/read" }
            .compactMap { $0.params?["threadId"]?.stringValue }

        #expect(requestedThreadIDs == ["backlog"])
        #expect(batch.refreshedThreadIDs == ["backlog"])
        #expect(batch.run.threadsDeferred == 1)
    }

    @Test
    func oldestChangedVersionWinsAmongPreviouslyFailingThreads() async throws {
        let active = try testJSON(#"{"id":"active","createdAt":1000,"updatedAt":1190,"recencyAt":1500,"source":"vscode","threadSource":"user"}"#)
        let older = try testJSON(#"{"id":"older","createdAt":1000,"updatedAt":1150,"recencyAt":1200,"source":"vscode","threadSource":"user"}"#)
        let server = ScriptedActivityAppServer(responses: [
            "thread/list": [
                .success(listResponse([active, older])),
                .success(listResponse([]))
            ],
            "thread/turns/list": [.success(listResponse([]))]
        ])
        let collector = ActivityHistoryCollector(
            client: server,
            configuration: .init(lookbackDuration: 1_000, maximumThreadsPerRun: 1),
            clock: { testDate(2_000) }
        )
        let existing = ActivityInsightsArchive(
            historyFailureVersions: [
                "active": testDate(1_100),
                "older": testDate(1_150)
            ]
        )

        let batch = try await collector.collect(existing: existing)
        let requestedThreadIDs = await server.recordedRequests()
            .filter { $0.method == "thread/turns/list" }
            .compactMap { $0.params?["threadId"]?.stringValue }

        #expect(requestedThreadIDs == ["older"])
        #expect(batch.refreshedThreadIDs == ["older"])
        #expect(batch.run.threadsDeferred == 1)
    }

    @Test
    func changedVersionOfPreviouslyFailingThreadUsesPaginatedHistory() async throws {
        let changed = try testJSON(#"{"id":"changed","createdAt":1000,"updatedAt":1150,"recencyAt":1500,"source":"vscode","threadSource":"user"}"#)
        let turn = try testJSON(#"{"id":"turn-1","startedAt":1201,"completedAt":1202,"items":[]}"#)
        let server = ScriptedActivityAppServer(responses: [
            "thread/list": [
                .success(listResponse([changed])),
                .success(listResponse([]))
            ],
            "thread/turns/list": [.success(listResponse([turn]))]
        ])
        let collector = ActivityHistoryCollector(
            client: server,
            configuration: .init(lookbackDuration: 1_000),
            clock: { testDate(2_000) }
        )
        let existing = ActivityInsightsArchive(
            historyFailureVersions: ["changed": testDate(1_100)]
        )

        let batch = try await collector.collect(existing: existing)
        let requests = await server.recordedRequests()

        #expect(batch.refreshedThreadIDs == ["changed"])
        #expect(batch.turns.map(\.turnID) == ["turn-1"])
        #expect(!requests.contains { $0.method == "thread/read" })
        #expect(requests.filter { $0.method == "thread/turns/list" }.count == 1)
    }

    @Test
    func explicitRetryRevalidatesKnownFailedVersionWithoutChangingDefaultQuarantine() async throws {
        let failed = try testJSON(#"{"id":"failed","createdAt":1000,"updatedAt":1100,"recencyAt":1200,"source":"vscode","threadSource":"user"}"#)
        let unattempted = try testJSON(#"{"id":"unattempted","createdAt":1000,"updatedAt":1100,"recencyAt":1300,"source":"vscode","threadSource":"user"}"#)
        let server = ScriptedActivityAppServer(responses: [
            "thread/list": [
                .success(listResponse([failed, unattempted])),
                .success(listResponse([]))
            ],
            "thread/read": [.success(readResponse([]))]
        ])
        let collector = ActivityHistoryCollector(
            client: server,
            configuration: .init(
                lookbackDuration: 1_000,
                maximumThreadsPerRun: 1,
                retryKnownFailures: true
            ),
            clock: { testDate(2_000) }
        )
        let existing = ActivityInsightsArchive(
            historyFailureVersions: ["failed": testDate(1_100)]
        )

        let batch = try await collector.collect(existing: existing)

        #expect(batch.attemptedThreadIDs == ["failed"])
        #expect(batch.refreshedThreadIDs == ["failed"])
        #expect(batch.run.threadsKnownFailed == 1)
        #expect(batch.run.threadFailures == 0)
        let requestedThreadIDs = await server.recordedRequests()
            .filter { $0.method == "thread/read" }
            .compactMap { $0.params?["threadId"]?.stringValue }
        #expect(requestedThreadIDs == ["failed"])
    }

    @Test
    func targetedRetryDoesNotGetStuckOnAnotherKnownFailure() async throws {
        let first = try testJSON(#"{"id":"first","createdAt":1000,"updatedAt":1100,"recencyAt":1400,"source":"vscode","threadSource":"user"}"#)
        let target = try testJSON(#"{"id":"target","createdAt":1000,"updatedAt":1100,"recencyAt":1200,"source":"vscode","threadSource":"user"}"#)
        let server = ScriptedActivityAppServer(responses: [
            "thread/list": [
                .success(listResponse([first, target])),
                .success(listResponse([]))
            ],
            "thread/read": [.success(readResponse([]))]
        ])
        let collector = ActivityHistoryCollector(
            client: server,
            configuration: .init(
                lookbackDuration: 1_000,
                maximumThreadsPerRun: 1,
                retryKnownFailures: true,
                retryKnownFailureThreadID: "target"
            ),
            clock: { testDate(2_000) }
        )
        let existing = ActivityInsightsArchive(
            historyFailureVersions: [
                "first": testDate(1_100),
                "target": testDate(1_100)
            ]
        )

        let batch = try await collector.collect(existing: existing)
        let requestedThreadIDs = await server.recordedRequests()
            .filter { $0.method == "thread/read" }
            .compactMap { $0.params?["threadId"]?.stringValue }

        #expect(requestedThreadIDs == ["target"])
        #expect(batch.refreshedThreadIDs == ["target"])
        #expect(batch.run.threadsKnownFailed == 2)
    }

    @Test
    func oversizedRetryCanBypassFullReadAndUsePaginatedTurns() async throws {
        let target = try testJSON(#"{"id":"target","createdAt":1000,"updatedAt":1100,"recencyAt":1200,"source":"vscode","threadSource":"user"}"#)
        let firstTurn = try testJSON(#"{"id":"turn-1","startedAt":1201,"items":[]}"#)
        let secondTurn = try testJSON(#"{"id":"turn-2","startedAt":1202,"items":[]}"#)
        let server = ScriptedActivityAppServer(responses: [
            "thread/list": [
                .success(listResponse([target])),
                .success(listResponse([]))
            ],
            "thread/turns/list": [
                .success(listResponse([firstTurn], nextCursor: "next")),
                .success(listResponse([secondTurn]))
            ]
        ])
        let collector = ActivityHistoryCollector(
            client: server,
            configuration: .init(
                lookbackDuration: 1_000,
                pageLimit: 1,
                retryKnownFailures: true,
                retryKnownFailureThreadID: "target",
                preferPaginatedTurns: true
            ),
            clock: { testDate(2_000) }
        )
        let existing = ActivityInsightsArchive(
            historyFailureVersions: ["target": testDate(1_100)]
        )

        let batch = try await collector.collect(existing: existing)
        let requests = await server.recordedRequests()

        #expect(batch.turns.map(\.turnID) == ["turn-1", "turn-2"])
        #expect(!requests.contains { $0.method == "thread/read" })
        #expect(requests.filter { $0.method == "thread/turns/list" }.count == 2)
        #expect(requests.filter { $0.method == "thread/turns/list" }.allSatisfy {
            $0.params?["itemsView"] == .string("full")
        })
    }

    @Test
    func malformedThreadsAndFailedHistoriesAreCountedWithoutAbortingRun() async throws {
        let malformed = try testJSON(#"{"createdAt":1000,"source":"vscode"}"#)
        let valid = try testJSON(#"{"id":"valid","createdAt":1000,"updatedAt":1100,"recencyAt":1200,"source":"vscode","threadSource":"user"}"#)
        let server = ScriptedActivityAppServer(responses: [
            "thread/list": [
                .success(listResponse([malformed, valid])),
                .success(listResponse([]))
            ],
            "thread/read": [
                .failure(.invalidResponse("broken history"))
            ]
        ])
        let collector = ActivityHistoryCollector(
            client: server,
            configuration: .init(lookbackDuration: 1_000),
            clock: { testDate(2_000) }
        )

        let batch = try await collector.collect(existing: .init())

        #expect(batch.threads.map(\.threadID) == ["valid"])
        #expect(batch.turns.isEmpty)
        #expect(batch.refreshedThreadIDs.isEmpty)
        #expect(batch.run.threadsSeen == 2)
        #expect(batch.run.threadFailures == 2)
        #expect(batch.run.failureCounts == [
            "metadata_parse": 1,
            "history_protocol": 1
        ])
    }
}

private struct RecordedActivityRequest: Equatable, Sendable {
    let method: String
    let params: ActivityJSONValue?
    let timeoutSeconds: TimeInterval
}

private actor ScriptedActivityAppServer: ActivityAppServerRequesting {
    private var responses: [String: [Result<ActivityJSONValue, ActivityInsightsError>]]
    private var requests: [RecordedActivityRequest] = []

    init(responses: [String: [Result<ActivityJSONValue, ActivityInsightsError>]]) {
        self.responses = responses
    }

    func request(
        method: String,
        params: ActivityJSONValue?,
        timeoutSeconds: TimeInterval
    ) async throws -> ActivityJSONValue {
        requests.append(.init(method: method, params: params, timeoutSeconds: timeoutSeconds))
        guard var queue = responses[method], !queue.isEmpty else {
            throw ActivityInsightsError.invalidResponse("No scripted response for \(method).")
        }
        let result = queue.removeFirst()
        responses[method] = queue
        return try result.get()
    }

    func shutdown() {}

    func recordedRequests() -> [RecordedActivityRequest] {
        requests
    }
}

private func listResponse(
    _ data: [ActivityJSONValue],
    nextCursor: String? = nil
) -> ActivityJSONValue {
    var object: [String: ActivityJSONValue] = ["data": .array(data)]
    if let nextCursor { object["nextCursor"] = .string(nextCursor) }
    return .object(object)
}

private func readResponse(_ turns: [ActivityJSONValue]) -> ActivityJSONValue {
    .object(["thread": .object(["turns": .array(turns)])])
}
