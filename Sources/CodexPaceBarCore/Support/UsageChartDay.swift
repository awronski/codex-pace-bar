import Foundation

/// The visible part of a local calendar day within an allowance window.
public struct UsageChartDay: Equatable, Sendable, Identifiable {
    public let start: Date
    public let end: Date

    public var id: Date { start }
    public var center: Date { start.addingTimeInterval(end.timeIntervalSince(start) / 2) }

    public static func segments(
        from start: Date,
        to end: Date,
        calendar: Calendar = .current
    ) -> [UsageChartDay] {
        var days: [UsageChartDay] = []
        var cursor = start
        while cursor < end {
            guard let day = calendar.dateInterval(of: .day, for: cursor), day.end > cursor else {
                break
            }
            let segmentEnd = min(day.end, end)
            days.append(UsageChartDay(start: cursor, end: segmentEnd))
            cursor = segmentEnd
        }
        return days
    }
}
