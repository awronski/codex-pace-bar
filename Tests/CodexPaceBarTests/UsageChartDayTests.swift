import CodexPaceBarCore
import Foundation
import Testing

@Suite
struct UsageChartDayTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }

    private func date(_ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test
    func noonResetShowsHalfMondaysAndSixFullDays() {
        let start = date(9, 14, hour: 12)
        let end = date(9, 21, hour: 12)
        let days = UsageChartDay.segments(from: start, to: end, calendar: calendar)

        #expect(days.map { $0.end.timeIntervalSince($0.start) / 3600 } == [12, 24, 24, 24, 24, 24, 24, 12])
        #expect(days.first?.start == start)
        #expect(days.last?.end == end)
        #expect(days.map { calendar.component(.weekday, from: $0.center) } == [2, 3, 4, 5, 6, 7, 1, 2])
        let tuesdayMorning = date(9, 15, hour: 11)
        #expect(days.first { $0.start <= tuesdayMorning && tuesdayMorning < $0.end } == days[1])
    }

    @Test
    func midnightResetHasSevenFullDaysWithoutAnExtraEmptyDay() {
        let days = UsageChartDay.segments(from: date(9, 14), to: date(9, 21), calendar: calendar)
        #expect(days.count == 7)
        #expect(days.allSatisfy { $0.end.timeIntervalSince($0.start) == 24 * 3600 })
    }

    @Test
    func partialDaysPreserveMinutesAndContiguousCoverage() {
        let start = date(9, 14, hour: 23, minute: 59)
        let end = date(9, 21, hour: 23, minute: 59)
        let days = UsageChartDay.segments(from: start, to: end, calendar: calendar)
        #expect(days.first?.end.timeIntervalSince(start) == 60)
        let lastDuration = days.last.map { $0.end.timeIntervalSince($0.start) }
        #expect(lastDuration == TimeInterval(24 * 3600 - 60))
        #expect(zip(days, days.dropFirst()).allSatisfy { $0.end == $1.start })
        #expect(days.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } == end.timeIntervalSince(start))
    }

    @Test
    func daylightSavingDaysUseLocalMidnights() {
        let spring = UsageChartDay.segments(from: date(3, 28, hour: 12), to: date(3, 30, hour: 12), calendar: calendar)
        #expect(spring.map { $0.end.timeIntervalSince($0.start) / 3600 } == [12, 23, 12])
        let autumn = UsageChartDay.segments(from: date(10, 24, hour: 12), to: date(10, 26, hour: 12), calendar: calendar)
        #expect(autumn.map { $0.end.timeIntervalSince($0.start) / 3600 } == [12, 25, 12])
    }

    @Test
    func emptyOrReversedWindowsHaveNoDays() {
        #expect(UsageChartDay.segments(from: date(9, 14), to: date(9, 14), calendar: calendar).isEmpty)
        #expect(UsageChartDay.segments(from: date(9, 15), to: date(9, 14), calendar: calendar).isEmpty)
    }
}
