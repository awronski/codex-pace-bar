import CodexPaceBarCore
import Foundation
import Observation

@MainActor
@Observable
public final class TaskAllowanceStore {
    public private(set) var report: TaskAllowanceReport?
    public private(set) var isLoading = false
    public private(set) var error: String?
    public var refreshID = 0
    @ObservationIgnored private let reader: TaskTokenHistoryReader
    @ObservationIgnored private var generation = 0

    public init(reader: TaskTokenHistoryReader = .init()) { self.reader = reader }

    public func refresh(window: CodexLimitWindow?, snapshotAt: Date?, samples: [UsageSample]) async {
        generation += 1
        let request = generation
        guard let window, let snapshotAt, Date() < window.resetsAt else {
            report = nil
            error = TaskAllowanceError.invalidWindow.errorDescription
            isLoading = false
            return
        }
        // Never leave an old reset window visible beneath a new period label.
        if report?.windowStart != window.resetsAt.addingTimeInterval(-window.windowDurationMins * 60) { report = nil }
        isLoading = true
        error = nil
        defer { if request == generation { isLoading = false } }
        do {
            let result = try await reader.load(window: window, snapshotAt: snapshotAt, samples: samples)
            try Task.checkCancellation()
            guard request == generation else { return }
            report = result
        } catch is CancellationError {
            // A newer snapshot or closing the view cancels this request.
        } catch {
            guard request == generation else { return }
            report = nil
            self.error = (error as? TaskAllowanceError)?.errorDescription ?? "Local token usage could not be read."
        }
    }
}
