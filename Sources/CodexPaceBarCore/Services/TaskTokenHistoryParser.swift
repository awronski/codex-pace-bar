import Foundation

/// Retains only token facts and task provenance, never message bodies.
struct TaskTokenHistoryParser {
    var id: String?
    var cwd: String?
    var parentID: String?
    var events: [TaskTokenEvent] = []
    var warnings: Set<String> = []
    var resetObservations: [UsageSample] = []
    private var previous: Int64?
    private var seen: Set<String> = []
    private var model: String?
    private var createdAt: Date?
    private var inheritedHistory = false
    private var fractionalFormatter = ISO8601DateFormatter()
    private var formatter = ISO8601DateFormatter()

    init() {
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    mutating func consume(_ line: String) {
        // Avoid decoding prompt/tool payloads. Matching text inside a message is harmless:
        // the envelope type is checked before any content can be retained.
        guard line.contains("\"token_count\"") || line.contains("\"session_meta\"")
                || line.contains("\"turn_context\"") else { return }
        guard let data = line.data(using: .utf8),
              let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = envelope["type"] as? String,
              let payload = envelope["payload"] as? [String: Any]
        else {
            warnings.insert("Some token history could not be decoded.")
            return
        }
        let date = (envelope["timestamp"] as? String).flatMap { fractionalFormatter.date(from: $0) ?? formatter.date(from: $0) }
        if type == "session_meta", id == nil {
            id = payload["id"] as? String ?? payload["session_id"] as? String
            cwd = payload["cwd"] as? String
            createdAt = (payload["timestamp"] as? String).flatMap { fractionalFormatter.date(from: $0) ?? formatter.date(from: $0) } ?? date
            parentID = Self.parent(from: payload["source"])
            if payload["source"] is [String: Any], let session = payload["session_id"] as? String, session != id {
                parentID = parentID ?? session
            }
            inheritedHistory = payload["history_base"] is [String: Any] || payload["forked_from_id"] is String
            return
        }
        if type == "turn_context" {
            model = payload["model"] as? String
            return
        }
        guard type == "event_msg", payload["type"] as? String == "token_count", let date else { return }
        let limits = payload["rate_limits"] as? [String: Any]
        let limitID = limits?["limit_id"] as? String
        if let limits, limitID == nil || limitID == "codex" {
            for key in ["primary", "secondary"] {
                if let window = limits[key] as? [String: Any],
                   (window["window_minutes"] as? Double) == 10080,
                   let used = window["used_percent"] as? Double,
                   let reset = window["resets_at"] as? Double,
                   used.isFinite, reset.isFinite, (0...100).contains(used) {
                    resetObservations.append(UsageSample(timestamp: date, usedPercent: used,
                        resetAt: Date(timeIntervalSince1970: reset), limitId: "codex"))
                }
            }
        }
        guard let info = payload["info"] as? [String: Any] else { return }
        guard let total = Self.tokens(info["total_token_usage"]) else {
            warnings.insert("Some token counters have an unsupported format.")
            return
        }
        let last = Self.tokens(info["last_token_usage"])
        let identity = "\(date.timeIntervalSince1970):\(total):\(last ?? -1)"
        guard seen.insert(identity).inserted else { return }
        if previous == total { return } // Repeated notification with a new timestamp.
        let delta = previous.flatMap { total >= $0 ? total - $0 : nil }
        let isFirst = previous == nil
        previous = total
        // Forks can carry copied events and a cumulative opening balance.
        if let createdAt, date < createdAt { return }
        if isFirst && inheritedHistory {
            // Without a prior counter, even last_token_usage may belong to the parent.
            // Keep this total as the baseline and qualify the ambiguous opening request.
            warnings.insert("An inherited opening token counter was used as a baseline; its ambiguous request usage was excluded.")
            return
        }
        guard let count = last ?? delta ?? (isFirst && !inheritedHistory ? total : nil), count >= 0 else {
            warnings.insert("Some inherited or restarted token counters could not be allocated.")
            return
        }
        if let last, let delta, last != delta {
            warnings.insert("Some request totals differ from cumulative counters; allocation uses recorded request totals.")
        }
        if last == nil {
            warnings.insert("Some token counts were recovered from cumulative counters.")
        }
        guard count > 0 else { return }
        events.append(TaskTokenEvent(timestamp: date, tokens: count, identity: identity, limitID: limitID, model: model))
    }

    static func parent(from source: Any?) -> String? {
        var value = source
        if let string = source as? String, let data = string.data(using: .utf8) {
            value = try? JSONSerialization.jsonObject(with: data)
        }
        let object = value as? [String: Any]
        let subagent = object?["subagent"] as? [String: Any]
        let spawn = subagent?["thread_spawn"] as? [String: Any]
        return spawn?["parent_thread_id"] as? String
    }

    private static func tokens(_ value: Any?) -> Int64? {
        guard let object = value as? [String: Any],
              let input = object["input_tokens"] as? NSNumber,
              let output = object["output_tokens"] as? NSNumber else { return nil }
        // Cache is a subset of input and reasoning is a subset of output.
        let a = input.doubleValue, b = output.doubleValue
        guard a.isFinite, b.isFinite, a >= 0, b >= 0,
              a.rounded(.down) == a, b.rounded(.down) == b,
              a + b < Double(Int64.max) else { return nil }
        return Int64(a + b)
    }
}
