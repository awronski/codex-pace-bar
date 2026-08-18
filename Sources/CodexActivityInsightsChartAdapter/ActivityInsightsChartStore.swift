import Foundation
import Observation

@MainActor
@Observable
public final class ActivityInsightsChartStore {
    public private(set) var state: ActivityInsightsChartState = .absent

    @ObservationIgnored
    private let reader: any ActivityInsightsChartReading
    @ObservationIgnored
    private let now: @MainActor @Sendable () -> Date

    public init(
        reader: any ActivityInsightsChartReading = ActivityInsightsChartReader(),
        now: @escaping @MainActor @Sendable () -> Date = Date.init
    ) {
        self.reader = reader
        self.now = now
    }

    public func refresh() async {
        let previousSnapshot = state.snapshot
        let next = await reader.read(at: now())
        if case .unavailable = next, let previousSnapshot {
            state = .stale(previousSnapshot)
        } else {
            state = next
        }
    }

    public func refreshWhileVisible(intervalSeconds: TimeInterval = 60) async {
        guard intervalSeconds > 0 else { return }
        while !Task.isCancelled {
            await refresh()
            do {
                try await Task.sleep(for: .seconds(intervalSeconds))
            } catch {
                return
            }
        }
    }
}
