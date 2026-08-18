import CodexActivityInsightsCore
import Foundation
import Testing

@Suite
struct ActivityHistoryParserTests {
    @Test
    func explicitThreadSourcesDistinguishUserCodexAndAutomation() throws {
        let user = try ActivityHistoryParser.thread(from: testJSON(#"""
        {
          "id":"user", "createdAt":1000, "updatedAt":1010, "recencyAt":1020,
          "source":"vscode", "threadSource":"user"
        }
        """#), archived: false)
        let codex = try ActivityHistoryParser.thread(from: testJSON(#"""
        {
          "id":"codex", "createdAt":1000,
          "source":{"subAgent":{"thread_spawn":{"parent_thread_id":"parent-1"}}},
          "threadSource":"subagent"
        }
        """#), archived: false)
        let automation = try ActivityHistoryParser.thread(from: testJSON(#"""
        {
          "id":"automation", "createdAt":1000, "source":"exec", "threadSource":"automation"
        }
        """#), archived: true)
        let voice = try ActivityHistoryParser.thread(from: testJSON(#"""
        {
          "id":"voice", "createdAt":1000, "source":"vscode", "threadSource":"realtime_voice"
        }
        """#), archived: false)

        #expect(user.actor == .user)
        #expect(user.mechanism == .interactive)
        #expect(user.confidence == .explicit)
        #expect(user.sourceUpdatedAt == testDate(1_010))
        #expect(user.sourceRecencyAt == testDate(1_020))

        #expect(codex.actor == .codex)
        #expect(codex.mechanism == .subagentSpawn)
        #expect(codex.parentThreadID == "parent-1")
        #expect(codex.sessionSource == "subAgentThreadSpawn")
        #expect(codex.confidence == .explicit)

        #expect(automation.actor == .automation)
        #expect(automation.mechanism == .automation)
        #expect(automation.archived)

        #expect(voice.actor == .user)
        #expect(voice.mechanism == .realtimeVoice)
    }

    @Test
    func forkAndLegacySourcesPreserveUncertainty() throws {
        let userFork = try ActivityHistoryParser.thread(from: testJSON(#"""
        {
          "id":"fork", "createdAt":1000, "source":"vscode", "threadSource":"user",
          "forkedFromId":"origin"
        }
        """#), archived: false)
        let inferredSubagent = try ActivityHistoryParser.thread(from: testJSON(#"""
        {
          "id":"legacy-agent", "createdAt":1000,
          "source":{"subAgent":"review"}, "parentThreadId":"parent"
        }
        """#), archived: false)
        let legacyInteractive = try ActivityHistoryParser.thread(from: testJSON(#"""
        {
          "id":"legacy-user", "createdAt":1000, "source":"cli"
        }
        """#), archived: false)
        let unrecognizedExplicit = try ActivityHistoryParser.thread(from: testJSON(#"""
        {
          "id":"future-source", "createdAt":1000, "source":"vscode", "threadSource":"new_kind"
        }
        """#), archived: false)

        #expect(userFork.actor == .user)
        #expect(userFork.mechanism == .fork)
        #expect(userFork.forkedFromID == "origin")

        #expect(inferredSubagent.actor == .codex)
        #expect(inferredSubagent.mechanism == .internalAgent)
        #expect(inferredSubagent.confidence == .inferred)
        #expect(inferredSubagent.sessionSource == "subAgentReview")

        #expect(legacyInteractive.actor == .user)
        #expect(legacyInteractive.mechanism == .interactive)
        #expect(legacyInteractive.confidence == .inferred)

        #expect(unrecognizedExplicit.actor == .unknown)
        #expect(unrecognizedExplicit.mechanism == .unknown)
        #expect(unrecognizedExplicit.confidence == .unknown)
    }

    @Test
    func normalizedUserMessagesProduceInputMetricsWithoutPromptText() throws {
        let text = "Zażółć 👨‍👩‍👧‍👦"
        let firstTurn = try testJSON(#"""
        {
          "id":"turn-1", "startedAt":1200, "completedAt":1202, "durationMs":2000,
          "status":"completed",
          "items":[
            {"id":"input-1", "type":"userMessage", "content":[
              {"type":"text", "text":"Zażółć 👨‍👩‍👧‍👦"},
              {"type":"image"}, {"type":"localAudio"}, {"type":"skill"}, {"type":"mention"}
            ]},
            {"id":"raw-user-role", "type":"message", "role":"user", "content":[
              {"type":"text", "text":"must not count"}
            ]},
            {"id":"agent-1", "type":"agentMessage", "content":[{"type":"text", "text":"answer"}]}
          ]
        }
        """#)
        let secondTurn = try testJSON(#"""
        {
          "id":"turn-2", "startedAt":1300, "status":{"type":"inProgress"},
          "items":[
            {"id":"input-2a", "type":"userMessage", "content":[{"type":"text", "text":"follow up"}]},
            {"id":"input-2b", "type":"userMessage", "content":[{"type":"text", "text":"steer"}]}
          ]
        }
        """#)

        let facts = try ActivityHistoryParser.turnFacts(
            from: [secondTurn, firstTurn],
            thread: testThread()
        )

        #expect(facts.turns.map(\.turnID) == ["turn-1", "turn-2"])
        #expect(facts.turns[0].durationMilliseconds == 2_000)
        #expect(!facts.turns[0].isProvisional)
        #expect(facts.turns[1].status == "inProgress")
        #expect(facts.turns[1].isProvisional)
        #expect(facts.inputs.count == 3)

        let initial = facts.inputs[0]
        #expect(initial.kind == .initialTask)
        #expect(initial.submittedAtEstimate == testDate(1_200))
        #expect(initial.textCharacters == text.count)
        #expect(initial.utf8Bytes == text.utf8.count)
        #expect(initial.attachmentCount == 2)
        #expect(initial.skillCount == 1)
        #expect(initial.mentionCount == 1)

        #expect(facts.inputs[1].kind == .followUp)
        #expect(facts.inputs[2].kind == .additionalInputSameTurn)
        #expect(facts.inputs[2].ordinal == 1)
    }

    @Test
    func malformedThreadAndTurnFailClosed() throws {
        #expect(throws: ActivityInsightsError.self) {
            _ = try ActivityHistoryParser.thread(from: testJSON(#"{"createdAt":1000}"#), archived: false)
        }
        #expect(throws: ActivityInsightsError.self) {
            _ = try ActivityHistoryParser.turnFacts(
                from: [testJSON(#"{"startedAt":1000}"#)],
                thread: testThread()
            )
        }
    }
}
