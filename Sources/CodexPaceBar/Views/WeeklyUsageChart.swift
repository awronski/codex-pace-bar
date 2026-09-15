import Charts
import CodexPaceBarCore
import SwiftUI

struct WeeklyUsageChart: View {
    let windowStart: Date
    let windowEnd: Date
    let samples: [UsageSample]
    let forecast: UsageForecast?
    let now: Date

    private var days: [UsageChartDay] {
        UsageChartDay.segments(from: windowStart, to: windowEnd)
    }

    private var visibleSamples: [UsageSample] {
        samples.filter { $0.timestamp >= windowStart && $0.timestamp <= min(now, windowEnd) }
    }

    private var exhaustionAt: Date? {
        guard let forecast, forecast.exhaustionAt >= windowStart,
              forecast.exhaustionAt < windowEnd else { return nil }
        return forecast.exhaustionAt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Weekly usage (%)")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(windowStart, format: .dateTime.day().month(.abbreviated))
                    + Text(" – ")
                    + Text(windowEnd, format: .dateTime.day().month(.abbreviated))
            }
            .font(.caption)

            HStack {
                if let exhaustionAt {
                    Text("Estimated limit · \(timeLabel(exhaustionAt))")
                        .foregroundStyle(.orange)
                } else {
                    Text(forecast == nil ? "Forecast pending" : "Should last until reset")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text("Reset · \(timeLabel(windowEnd))")
                    .foregroundStyle(.secondary)
                    .help(windowEnd.formatted(date: .complete, time: .shortened))
            }
            .font(.system(size: 10))
            .monospacedDigit()
            .lineLimit(1)

            chart
                .frame(height: 125)

            HStack(spacing: 12) {
                legend("Actual", color: .blue, dashed: false)
                legend("Forecast", color: .orange, dashed: true)
                Spacer(minLength: 0)
                Text("Local time")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(0.5))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.separator.opacity(0.35), lineWidth: 1)
                }
        }
    }

    private var chart: some View {
        Chart {
            if let today = days.first(where: { $0.start <= now && now < $0.end }) {
                RectangleMark(
                    xStart: .value("Day start", today.start),
                    xEnd: .value("Day end", today.end),
                    yStart: .value("Minimum", 0),
                    yEnd: .value("Maximum", 100)
                )
                .foregroundStyle(.blue.opacity(0.08))
                .accessibilityHidden(true)
            }

            ForEach(visibleSamples, id: \.timestamp) { sample in
                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Used", sample.usedPercent),
                    series: .value("Series", "Actual")
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.linear)
            }

            ForEach(forecast?.projection ?? [], id: \.timestamp) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Forecast", point.usedPercent),
                    series: .value("Series", "Forecast")
                )
                .foregroundStyle(.orange)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 3]))
                .interpolationMethod(.linear)
            }

            if now >= windowStart && now <= windowEnd {
                RuleMark(x: .value("Now", now))
                    .foregroundStyle(.blue.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }

            if let latest = visibleSamples.last {
                PointMark(x: .value("Time", latest.timestamp), y: .value("Used", latest.usedPercent))
                    .foregroundStyle(.blue)
                    .symbolSize(40)
                    .accessibilityLabel("Latest usage, \(timeLabel(latest.timestamp))")
            }

            if let exhaustionAt {
                PointMark(x: .value("Estimated limit", exhaustionAt), y: .value("Used", 100))
                    .foregroundStyle(.orange)
                    .symbolSize(35)
                    .accessibilityLabel("Estimated limit, \(timeLabel(exhaustionAt))")
            }

            RuleMark(x: .value("Reset", windowEnd))
                .foregroundStyle(Color.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
        .chartLegend(.hidden)
        .chartYScale(domain: 0...100)
        .chartXScale(domain: windowStart...windowEnd)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) {
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartXAxis {
            AxisMarks(values: days.dropFirst().map(\.start)) {
                AxisGridLine()
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let frame = geometry[plotFrame]
                    ForEach(days) { day in
                        if let x = proxy.position(forX: day.center) {
                            VStack(spacing: 1) {
                                Text(day.center, format: .dateTime.weekday(.abbreviated))
                                Text(day.center, format: .dateTime.day())
                            }
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                            .position(x: frame.minX + x, y: frame.maxY + 16)
                        }
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .padding(.bottom, 30)
    }

    private func timeLabel(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private func legend(_ title: String, color: Color, dashed: Bool) -> some View {
        HStack(spacing: 4) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 3))
                path.addLine(to: CGPoint(x: 16, y: 3))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [4, 2] : []))
            .frame(width: 16, height: 6)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
