import Foundation

public struct ActivityCollaborationMetrics: Equatable, Sendable {
    public var codexFocusedSeconds = 0.0
    public var codexNotFocusedSeconds = 0.0
    public var codexFocusUnknownSeconds = 0.0
    public var activeCodexWorkingSeconds = 0.0
    public var activeCodexIdleSeconds = 0.0
    public var inactiveCodexWorkingSeconds = 0.0
    public var inactiveCodexIdleSeconds = 0.0
    public var activeCodexUnknownSeconds = 0.0
    public var inactiveCodexUnknownSeconds = 0.0
    public var unknownUserCodexWorkingSeconds = 0.0
    public var unknownUserCodexIdleSeconds = 0.0
    public var unknownUserCodexUnknownSeconds = 0.0
    public var codexWorkingFocusedSeconds = 0.0
    public var codexWorkingNotFocusedSeconds = 0.0
    public var codexWorkingFocusUnknownSeconds = 0.0

    public init() {}

    public var fourStateUnknownSeconds: TimeInterval {
        activeCodexUnknownSeconds + inactiveCodexUnknownSeconds + unknownUserStateSeconds
    }

    public var unknownUserStateSeconds: TimeInterval {
        unknownUserCodexWorkingSeconds
            + unknownUserCodexIdleSeconds
            + unknownUserCodexUnknownSeconds
    }
}

public enum ActivityCollaborationAnalyzer {
    private struct ActivityInterval {
        var start: Date
        var end: Date
    }

    public static func analyze(
        observations: [ActivityObservationFact],
        turns: [ActivityTurnFact],
        threads: [String: ActivityThreadFact],
        now: Date,
        windowStart: Date? = nil
    ) -> ActivityCollaborationMetrics {
        let observations = observations.sorted {
            if $0.intervalStart == $1.intervalStart { return $0.intervalEnd < $1.intervalEnd }
            return $0.intervalStart < $1.intervalStart
        }
        let lowerBound = windowStart
            ?? observations.first?.intervalStart
            ?? turns.compactMap(\.startedAt).min()
            ?? now
        let completedIntervals = mergedIntervals(turns.compactMap { turn -> ActivityInterval? in
            guard let start = turn.startedAt,
                  let end = turn.completedAt,
                  end > start
            else {
                return nil
            }
            return clippedInterval(start: start, end: end, lowerBound: lowerBound, upperBound: now)
        })
        let possibleIntervals = mergedIntervals(turns.compactMap { turn -> ActivityInterval? in
            guard let start = turn.startedAt else { return nil }
            let end: Date
            if let completedAt = turn.completedAt {
                end = completedAt
            } else if isTerminalTurnStatus(turn.status) {
                end = min(threads[turn.threadID]?.sourceUpdatedAt ?? start, now)
            } else {
                end = now
            }
            guard end > start else { return nil }
            return clippedInterval(start: start, end: end, lowerBound: lowerBound, upperBound: now)
        })

        var metrics = ActivityCollaborationMetrics()
        var completedIndex = 0
        var possibleIndex = 0
        var previousObservationEnd = lowerBound
        var observedIntervals: [ActivityInterval] = []
        for observation in observations {
            let start = max(max(observation.intervalStart, lowerBound), previousObservationEnd)
            let end = min(observation.intervalEnd, now)
            guard end > start else { continue }
            previousObservationEnd = end
            observedIntervals.append(ActivityInterval(start: start, end: end))
            let duration = end.timeIntervalSince(start)
            let completedWorking = overlapSeconds(
                from: start,
                to: end,
                intervals: completedIntervals,
                index: &completedIndex
            )
            let possibleWorking = overlapSeconds(
                from: start,
                to: end,
                intervals: possibleIntervals,
                index: &possibleIndex
            )
            let unknownCodex = max(0, possibleWorking - completedWorking)
            let idle = max(0, duration - possibleWorking)

            switch observation.codexFocus {
            case .focused:
                metrics.codexFocusedSeconds += duration
                metrics.codexWorkingFocusedSeconds += completedWorking
            case .notFocused:
                metrics.codexNotFocusedSeconds += duration
                metrics.codexWorkingNotFocusedSeconds += completedWorking
            case .unknown:
                metrics.codexFocusUnknownSeconds += duration
                metrics.codexWorkingFocusUnknownSeconds += completedWorking
            }

            switch observation.userState {
            case .active:
                metrics.activeCodexWorkingSeconds += completedWorking
                metrics.activeCodexIdleSeconds += idle
                metrics.activeCodexUnknownSeconds += unknownCodex
            case .inactive:
                metrics.inactiveCodexWorkingSeconds += completedWorking
                metrics.inactiveCodexIdleSeconds += idle
                metrics.inactiveCodexUnknownSeconds += unknownCodex
            case .unknown:
                metrics.unknownUserCodexWorkingSeconds += completedWorking
                metrics.unknownUserCodexIdleSeconds += idle
                metrics.unknownUserCodexUnknownSeconds += unknownCodex
            }
        }

        // Persisted Codex turns remain valid evidence when the Mac sampler was stopped or
        // unavailable. Keep the Codex work, but mark the user's state and Codex focus unknown
        // rather than silently dropping the interval from coverage and from the gauge.
        let completedUnobserved = max(
            0,
            totalSeconds(completedIntervals)
                - intersectionSeconds(intervals: completedIntervals, coveredBy: observedIntervals)
        )
        let possibleUnobserved = max(
            0,
            totalSeconds(possibleIntervals)
                - intersectionSeconds(intervals: possibleIntervals, coveredBy: observedIntervals)
        )
        metrics.unknownUserCodexWorkingSeconds += completedUnobserved
        metrics.unknownUserCodexUnknownSeconds += max(0, possibleUnobserved - completedUnobserved)
        metrics.codexWorkingFocusUnknownSeconds += completedUnobserved
        return metrics
    }

    private static func isTerminalTurnStatus(_ status: String) -> Bool {
        switch status.lowercased() {
        case "completed", "cancelled", "canceled", "failed", "interrupted":
            return true
        default:
            return false
        }
    }

    private static func clippedInterval(
        start: Date,
        end: Date,
        lowerBound: Date,
        upperBound: Date
    ) -> ActivityInterval? {
        let start = max(start, lowerBound)
        let end = min(end, upperBound)
        return end > start ? ActivityInterval(start: start, end: end) : nil
    }

    private static func mergedIntervals(_ intervals: [ActivityInterval]) -> [ActivityInterval] {
        let intervals = intervals.sorted {
            if $0.start == $1.start { return $0.end < $1.end }
            return $0.start < $1.start
        }
        var merged: [ActivityInterval] = []
        for interval in intervals {
            guard var last = merged.last else {
                merged.append(interval)
                continue
            }
            if interval.start <= last.end {
                last.end = max(last.end, interval.end)
                merged[merged.count - 1] = last
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    private static func overlapSeconds(
        from start: Date,
        to end: Date,
        intervals: [ActivityInterval],
        index: inout Int
    ) -> TimeInterval {
        while index < intervals.count, intervals[index].end <= start {
            index += 1
        }
        var cursor = index
        var seconds = 0.0
        while cursor < intervals.count, intervals[cursor].start < end {
            let overlapStart = max(start, intervals[cursor].start)
            let overlapEnd = min(end, intervals[cursor].end)
            if overlapEnd > overlapStart {
                seconds += overlapEnd.timeIntervalSince(overlapStart)
            }
            cursor += 1
        }
        return min(end.timeIntervalSince(start), seconds)
    }

    private static func totalSeconds(_ intervals: [ActivityInterval]) -> TimeInterval {
        intervals.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }

    private static func intersectionSeconds(
        intervals: [ActivityInterval],
        coveredBy coverage: [ActivityInterval]
    ) -> TimeInterval {
        let coverage = mergedIntervals(coverage)
        var total = 0.0
        var coverageIndex = 0
        for interval in intervals {
            total += overlapSeconds(
                from: interval.start,
                to: interval.end,
                intervals: coverage,
                index: &coverageIndex
            )
        }
        return total
    }
}
