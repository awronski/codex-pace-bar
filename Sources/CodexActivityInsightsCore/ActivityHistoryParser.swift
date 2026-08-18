import Foundation

public enum ActivityHistoryParser {
    public static func thread(
        from value: ActivityJSONValue,
        archived: Bool
    ) throws -> ActivityThreadFact {
        guard let object = value.objectValue,
              let threadID = object["id"]?.stringValue,
              let createdAt = date(seconds: object["createdAt"])
        else {
            throw ActivityInsightsError.invalidResponse("Thread was missing id or createdAt.")
        }

        let sessionSource = normalizedSessionSource(object["source"])
        let threadSource = object["threadSource"]?.stringValue
        let nestedParent = nestedSpawnParent(object["source"])
        let parent = object["parentThreadId"]?.stringValue ?? nestedParent
        let fork = object["forkedFromId"]?.stringValue
        let provenance = classify(
            threadSource: threadSource,
            sessionSource: sessionSource,
            parentThreadID: parent,
            forkedFromID: fork
        )
        let updatedAt = date(seconds: object["updatedAt"]) ?? createdAt
        let recencyAt = date(seconds: object["recencyAt"]) ?? updatedAt

        return ActivityThreadFact(
            threadID: threadID,
            createdAt: createdAt,
            sourceUpdatedAt: updatedAt,
            sourceRecencyAt: recencyAt,
            sessionSource: sessionSource,
            threadSource: threadSource,
            parentThreadID: parent,
            forkedFromID: fork,
            actor: provenance.actor,
            mechanism: provenance.mechanism,
            confidence: provenance.confidence,
            archived: archived
        )
    }

    public static func turnFacts(
        from values: [ActivityJSONValue],
        thread: ActivityThreadFact
    ) throws -> (turns: [ActivityTurnFact], inputs: [ActivityInputFact]) {
        let sorted = values.sorted {
            (date(seconds: $0["startedAt"]) ?? .distantPast)
                < (date(seconds: $1["startedAt"]) ?? .distantPast)
        }
        var turns: [ActivityTurnFact] = []
        var inputs: [ActivityInputFact] = []

        for (turnIndex, value) in sorted.enumerated() {
            guard let object = value.objectValue,
                  let turnID = object["id"]?.stringValue
            else {
                throw ActivityInsightsError.invalidResponse("Turn was missing id.")
            }

            let startedAt = date(seconds: object["startedAt"])
            let completedAt = date(seconds: object["completedAt"])
            let duration = object["durationMs"]?.intValue
            let status = object["status"]?.stringValue
                ?? object["status"]?.objectValue?["type"]?.stringValue
                ?? (completedAt == nil ? "inProgress" : "completed")
            turns.append(ActivityTurnFact(
                threadID: thread.threadID,
                turnID: turnID,
                startedAt: startedAt,
                completedAt: completedAt,
                durationMilliseconds: duration,
                status: status
            ))

            let userItems = (object["items"]?.arrayValue ?? []).filter {
                $0["type"]?.stringValue == "userMessage"
            }
            for (ordinal, item) in userItems.enumerated() {
                let metrics = inputMetrics(item["content"]?.arrayValue ?? [])
                let itemID = item["id"]?.stringValue ?? "missing-item"
                let kind: ActivityInputKind
                if ordinal > 0 {
                    kind = .additionalInputSameTurn
                } else if turnIndex == 0 {
                    kind = .initialTask
                } else {
                    kind = .followUp
                }
                inputs.append(ActivityInputFact(
                    threadID: thread.threadID,
                    turnID: turnID,
                    itemID: itemID,
                    ordinal: ordinal,
                    actor: thread.actor,
                    kind: kind,
                    submittedAtEstimate: startedAt,
                    textCharacters: metrics.characters,
                    utf8Bytes: metrics.utf8Bytes,
                    attachmentCount: metrics.attachments,
                    skillCount: metrics.skills,
                    mentionCount: metrics.mentions
                ))
            }
        }

        return (turns, inputs)
    }

    public static func classify(
        threadSource: String?,
        sessionSource: String,
        parentThreadID: String?,
        forkedFromID: String?
    ) -> (
        actor: ActivityThreadActor,
        mechanism: ActivityCreationMechanism,
        confidence: ActivityProvenanceConfidence
    ) {
        let normalizedThreadSource = threadSource?.lowercased()
        switch normalizedThreadSource {
        case "user":
            return (.user, forkedFromID == nil ? .interactive : .fork, .explicit)
        case "subagent":
            return (.codex, sessionSource == "subAgentThreadSpawn" ? .subagentSpawn : .internalAgent, .explicit)
        case "automation":
            return (.automation, .automation, .explicit)
        case "realtime_voice":
            return (.user, .realtimeVoice, .explicit)
        case .some:
            return (.unknown, forkedFromID == nil ? .unknown : .fork, .unknown)
        case nil:
            break
        }

        if sessionSource.hasPrefix("subAgent") || parentThreadID != nil {
            return (
                .codex,
                sessionSource == "subAgentThreadSpawn" ? .subagentSpawn : .internalAgent,
                .inferred
            )
        }
        if sessionSource == "exec" {
            return (.automation, .automation, .inferred)
        }
        if forkedFromID != nil {
            return (.unknown, .fork, .unknown)
        }
        if sessionSource == "cli" || sessionSource == "vscode" {
            return (.user, .interactive, .inferred)
        }
        if sessionSource == "appServer" {
            return (.unknown, .unknown, .unknown)
        }
        return (.unknown, .unknown, .unknown)
    }

    public static func normalizedSessionSource(_ source: ActivityJSONValue?) -> String {
        if let value = source?.stringValue { return value }
        guard let subagent = source?["subAgent"] else { return "unknown" }
        if let value = subagent.stringValue {
            switch value {
            case "review": return "subAgentReview"
            case "compact": return "subAgentCompact"
            default: return "subAgent:\(value)"
            }
        }
        if subagent["thread_spawn"] != nil { return "subAgentThreadSpawn" }
        if let other = subagent["other"]?.stringValue { return "subAgentOther:\(other)" }
        return "subAgentOther"
    }

    private static func nestedSpawnParent(_ source: ActivityJSONValue?) -> String? {
        source?["subAgent"]?["thread_spawn"]?["parent_thread_id"]?.stringValue
    }

    private static func inputMetrics(_ content: [ActivityJSONValue]) -> (
        characters: Int,
        utf8Bytes: Int,
        attachments: Int,
        skills: Int,
        mentions: Int
    ) {
        var characters = 0
        var utf8Bytes = 0
        var attachments = 0
        var skills = 0
        var mentions = 0

        for item in content {
            switch item["type"]?.stringValue {
            case "text":
                let text = item["text"]?.stringValue ?? ""
                characters += text.count
                utf8Bytes += text.utf8.count
            case "image", "localImage", "audio", "localAudio":
                attachments += 1
            case "skill":
                skills += 1
            case "mention":
                mentions += 1
            default:
                break
            }
        }
        return (characters, utf8Bytes, attachments, skills, mentions)
    }

    private static func date(seconds value: ActivityJSONValue?) -> Date? {
        guard let seconds = value?.doubleValue, seconds.isFinite else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
