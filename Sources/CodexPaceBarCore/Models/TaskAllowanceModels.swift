import Foundation

public enum TaskAllowancePeriod: String, CaseIterable, Identifiable, Sendable {
    case today
    case sinceReset

    public var id: String { rawValue }
    public var title: String { self == .today ? "Today" : "Since last reset" }
}

public struct TaskTokenEvent: Equatable, Sendable {
    public let timestamp: Date
    public let tokens: Int64
    public let identity: String
    public let limitID: String?
    public let model: String?
}

public struct TaskTokenHistory: Sendable {
    public var id: String
    public var name: String
    public var project: String
    public var parentID: String?
    public var events: [TaskTokenEvent]
}

public struct TaskAllowanceRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let project: String
    public let name: String
    public let tokens: Int64
    public let percentagePoints: Double
}

public struct TaskAllowanceReport: Sendable {
    public let windowStart: Date
    public let snapshotAt: Date
    public let usedPercent: Double
    public let histories: [TaskTokenHistory]
    public let warnings: [String]

    public func periodStart(_ period: TaskAllowancePeriod, calendar: Calendar = .current) -> Date {
        period == .today ? max(windowStart, calendar.startOfDay(for: snapshotAt)) : windowStart
    }

    /// Both periods use the FULL weekly token denominator. Today only changes the numerator.
    public func rows(for period: TaskAllowancePeriod, calendar: Calendar = .current) -> [TaskAllowanceRow] {
        let start = periodStart(period, calendar: calendar)
        let byID = Dictionary(histories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var totals: [String: Int64] = [:]
        var weeklyTotal: Double = 0
        for history in histories {
            var root = history.id
            var seen: Set<String> = [root]
            while let parent = byID[root]?.parentID, byID[parent] != nil, seen.insert(parent).inserted {
                root = parent
            }
            for event in history.events where event.timestamp >= windowStart && event.timestamp <= snapshotAt {
                weeklyTotal += Double(event.tokens)
                if event.timestamp >= start {
                    totals[root, default: 0] += event.tokens
                }
            }
        }
        guard weeklyTotal > 0 else { return [] }
        return totals.compactMap { id, tokens in
            guard tokens > 0, let history = byID[id] else { return nil }
            return TaskAllowanceRow(
                id: id, project: history.project, name: history.name, tokens: tokens,
                percentagePoints: usedPercent * Double(tokens) / weeklyTotal
            )
        }.sorted { $0.tokens == $1.tokens ? $0.id < $1.id : $0.tokens > $1.tokens }
    }
}

public enum TaskAllowanceError: LocalizedError {
    case unavailableHistory
    case unsupportedHistory
    case unreadableHistory
    case invalidWindow

    public var errorDescription: String? {
        switch self {
        case .unavailableHistory: "Local Codex task history is unavailable."
        case .unsupportedHistory: "This Codex history format is not supported."
        case .unreadableHistory: "Local Codex task history could not be read."
        case .invalidWindow: "Refresh weekly usage before allocating task usage."
        }
    }
}
