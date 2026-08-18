import CodexActivityInsightsChartAdapter
import CodexActivityInsightsContract
import SwiftUI

struct ActivityInsightsChartRow: View {
    @State private var store = ActivityInsightsChartStore()

    var body: some View {
        // Keep a concrete container in the hierarchy while the initial state is hidden;
        // a task attached to a Group containing only EmptyView is never started by SwiftUI.
        VStack(alignment: .leading, spacing: 0) {
            switch store.state {
            case .collecting:
                rowShell {
                    Text("Collecting enough observed time to show Codex time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .ready(let snapshot), .partial(let snapshot):
                rowShell { gauge(snapshot.fourState) }
            case .stale(let snapshot):
                rowShell {
                    qualityNotice("Collector not updating", systemImage: "pause.circle.fill")
                    if snapshot.fourState.codexWorkingSeconds > 0 {
                        gauge(snapshot.fourState)
                    } else {
                        Text("No current Codex activity data is available.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            case .absent, .disabled, .unavailable:
                EmptyView()
            }
        }
        .task {
            await store.refreshWhileVisible()
        }
    }

    private func qualityNotice(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.orange)
            .accessibilityLabel(text)
    }

    @ViewBuilder
    private func rowShell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Divider()
            HStack {
                Text("Activity Insights")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("Last 7 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            content()
        }
    }

    @ViewBuilder
    private func gauge(_ state: ActivityInsightsFourStateDurations) -> some View {
        if let handsOffPercent = state.handsOffCodexSharePercent,
           let handsOnPercent = state.handsOnCodexSharePercent {
            CodexTimeGauge(
                totalSeconds: state.codexWorkingSeconds,
                handsOffSeconds: state.inactiveCodexWorkingSeconds,
                handsOnSeconds: state.activeCodexWorkingSeconds,
                handsOffPercent: handsOffPercent,
                handsOnPercent: handsOnPercent
            )
        } else {
            Text("No Codex working time observed in the last 7 days.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CodexTimeGauge: View {
    let totalSeconds: TimeInterval
    let handsOffSeconds: TimeInterval
    let handsOnSeconds: TimeInterval
    let handsOffPercent: Double
    let handsOnPercent: Double

    private let handsOffColor = Color(red: 0.24, green: 0.76, blue: 0.73)
    private let handsOnColor = Color(red: 1.00, green: 0.76, blue: 0.12)

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            GaugeLegend(
                label: "Hands-off",
                value: "\(duration(handsOffSeconds)) · \(percent(handsOffPercent))",
                color: handsOffColor
            )
            .frame(width: 91)

            ZStack(alignment: .top) {
                ZStack {
                    Circle()
                        .inset(by: 10)
                        .trim(from: 0.5, to: 1)
                        .stroke(.secondary.opacity(0.16), style: strokeStyle)

                    Circle()
                        .inset(by: 10)
                        .trim(from: 0.5, to: splitPoint)
                        .stroke(handsOffColor, style: strokeStyle)

                    Circle()
                        .inset(by: 10)
                        .trim(from: splitPoint, to: 1)
                        .stroke(handsOnColor, style: strokeStyle)
                }
                .frame(width: 140, height: 140)
                .padding(.top, 4)

                Text(duration(totalSeconds))
                    .font(.system(size: 20, weight: .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .padding(.top, 47)
            }
            .frame(width: 150, height: 74, alignment: .top)
            .clipped()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Observed Codex time \(duration(totalSeconds)); hands-off \(duration(handsOffSeconds)), \(percent(handsOffPercent)); hands-on \(duration(handsOnSeconds)), \(percent(handsOnPercent))"
            )

            GaugeLegend(
                label: "Hands-on",
                value: "\(duration(handsOnSeconds)) · \(percent(handsOnPercent))",
                color: handsOnColor
            )
            .frame(width: 91)
        }
        .frame(maxWidth: .infinity)
    }

    private var splitPoint: CGFloat {
        0.5 + 0.5 * CGFloat(min(max(handsOffPercent / 100, 0), 1))
    }

    private var strokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: 20, lineCap: .round, lineJoin: .round)
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        if minutes < 60 { return "\(minutes)m" }
        let hours = Double(minutes) / 60
        return hours < 10 ? String(format: "%.1fh", hours) : "\(Int(hours.rounded()))h"
    }

    private func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }
}

private struct GaugeLegend: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.leading, 15)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}
