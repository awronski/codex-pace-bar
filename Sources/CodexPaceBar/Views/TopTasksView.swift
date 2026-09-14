import CodexPaceBarAppSupport
import CodexPaceBarCore
import SwiftUI

struct TopTasksView: View {
    let store: TaskAllowanceStore
    let model: AppModel
    let history: UsageHistoryStore
    @AppStorage("topTasksPeriod") private var period: TaskAllowancePeriod = .sinceReset
    @State private var showingExplanation = false

    private struct RefreshKey: Hashable {
        let snapshot: Date?
        let refresh: Int
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Top tasks").font(.title2.weight(.semibold))
                Spacer()
                if store.isLoading { ProgressView().controlSize(.small) }
            }
            Picker("Period", selection: $period) {
                ForEach(TaskAllowancePeriod.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if let error = store.error {
                ContentUnavailableView("Task usage unavailable", systemImage: "doc.text.magnifyingglass", description: Text(error))
            } else if let report = store.report {
                ranking(report)
            } else {
                Spacer()
                Text("Reading local token history…").foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .task(id: RefreshKey(snapshot: model.lastCheckedAt, refresh: store.refreshID)) {
            await store.refresh(window: model.selectedWindow, snapshotAt: model.lastCheckedAt, samples: history.samples)
        }
    }

    private func ranking(_ report: TaskAllowanceReport) -> some View {
        let rows = report.rows(for: period)
        let top = Array(rows.prefix(20))
        let other = rows.dropFirst(20).reduce(0) { $0 + $1.percentagePoints }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(rangeLabel(report))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button { showingExplanation.toggle() } label: {
                    HStack(spacing: 4) {
                        Text("Share of weekly allowance")
                        Image(systemName: "info.circle")
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityLabel("How weekly allowance is allocated")
                .popover(isPresented: $showingExplanation) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Share of weekly allowance").font(.headline)
                        Text("2.4% means an illustrative share of your full weekly allowance.")
                        Text("Weekly usage is divided between tasks in proportion to their recorded tokens. Today counts only today's tokens and keeps the same weekly scale.")
                        Text("Model and cache charging weights are unknown. Only local history is included; child-agent usage belongs to its parent task.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 14))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(18).frame(width: 340, alignment: .leading)
                }
            }
            if top.isEmpty {
                ContentUnavailableView("No recorded tokens", systemImage: "list.number",
                    description: Text("No task token events were found in this period."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(top.enumerated()), id: \.element.id) { index, row in
                            TaskAllowanceListRow(row: row, rank: index + 1, maximum: top.first?.percentagePoints ?? 0)
                            if index < top.count - 1 { Divider().padding(.horizontal, 10) }
                        }
                    }
                }
                .id(period)
                .accessibilityLabel("Top tasks ranked by share of weekly allowance")
            }
            HStack {
                Text("Illustrative allocation · local history")
                Spacer()
                Text(rows.count > 20 ? "Top 20 · scroll for more" : "\(rows.count) tasks")
            }
            .font(.caption).foregroundStyle(.secondary)
            if rows.count > 20 {
                Text("Other tasks: \(allowancePercentage(other))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !report.warnings.isEmpty {
                Label("Partial or qualified history", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .help(report.warnings.joined(separator: "\n"))
                    .accessibilityValue(report.warnings.joined(separator: " "))
            }
        }
    }

    private func rangeLabel(_ report: TaskAllowanceReport) -> String {
        let start = report.periodStart(period)
        if Calendar.current.isDate(start, inSameDayAs: report.snapshotAt) {
            return "\(start.formatted(.dateTime.day().month(.abbreviated))) · \(start.formatted(.dateTime.hour().minute()))–\(report.snapshotAt.formatted(.dateTime.hour().minute()))"
        }
        return "\(start.formatted(.dateTime.day().month(.abbreviated))) – \(report.snapshotAt.formatted(.dateTime.day().month(.abbreviated)))"
    }
}

private struct TaskAllowanceListRow: View {
    let row: TaskAllowanceRow
    let rank: Int
    let maximum: Double
    @State private var hovering = false
    @State private var showingTitle = false

    var body: some View {
        Button { showingTitle.toggle() } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(rank)").font(.system(size: 13)).foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .trailing)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(Text(row.project).foregroundStyle(.secondary)) — \(row.name)")
                            .font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        Text(allowancePercentage(row.percentagePoints))
                            .font(.system(size: 14, weight: .semibold)).monospacedDigit().fixedSize()
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.primary.opacity(0.1))
                            Capsule().fill(.blue.opacity(0.8))
                                .frame(width: maximum > 0 ? geometry.size.width * row.percentagePoints / maximum : 0)
                        }
                    }
                    .frame(height: 4)
                    .padding(.trailing, 54)
                    .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .background(hovering ? Color.blue.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovering = inside
            if !inside { showingTitle = false }
        }
        .task(id: hovering) {
            guard hovering else { return }
            do {
                try await Task.sleep(for: .milliseconds(350))
                showingTitle = true
            } catch { /* Pointer left the row before the hover delay. */ }
        }
        .popover(isPresented: $showingTitle, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 8) {
                Text(row.project).font(.system(size: 13)).foregroundStyle(.secondary)
                Text(row.name).font(.system(size: 17, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(width: 310, alignment: .leading)
        }
        .accessibilityLabel("\(rank). \(row.project), \(row.name), \(allowancePercentage(row.percentagePoints)) of weekly allowance, illustrative")
        .accessibilityHint("Show full task title")
    }
}

private func allowancePercentage(_ value: Double) -> String {
    (value > 0 && value < 0.05 ? "<0.1" : value.formatted(.number.precision(.fractionLength(1)))) + "%"
}
