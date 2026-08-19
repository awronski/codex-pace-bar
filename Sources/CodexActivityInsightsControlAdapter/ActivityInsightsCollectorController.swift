import Foundation
import Observation

@MainActor
@Observable
public final class ActivityInsightsCollectorController {
    public private(set) var isEnabled = false
    public private(set) var isRunning = false
    public private(set) var isBusy = false
    public private(set) var statusMessage = "Off by default; stores local timing totals only."

    @ObservationIgnored
    private let client: ActivityInsightsControlClient?

    @ObservationIgnored
    private let startupError: String?

    public convenience init() {
        do {
            try self.init(client: .bundled())
        } catch {
            self.init(client: nil, startupError: error.localizedDescription)
        }
    }

    public init(
        client: ActivityInsightsControlClient?,
        startupError: String? = nil
    ) {
        self.client = client
        self.startupError = startupError
        if let startupError {
            statusMessage = startupError
        }
    }

    public func refresh() {
        guard !isBusy else { return }
        guard let client else {
            statusMessage = startupError ?? "Activity Insights is unavailable."
            return
        }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                apply(try await client.status())
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    public func reconcile(configuredCodexPath: String?) {
        guard !isBusy else { return }
        guard let client else {
            statusMessage = startupError ?? "Activity Insights is unavailable."
            return
        }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                apply(try await client.reconcile(configuredCodexPath: configuredCodexPath))
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    public func setEnabled(_ enabled: Bool, configuredCodexPath: String?) {
        guard !isBusy, let client else {
            statusMessage = startupError ?? "Activity Insights is unavailable."
            return
        }
        let previousValue = isEnabled
        let previousRunningValue = isRunning
        isEnabled = enabled
        if !enabled {
            isRunning = false
        }
        isBusy = true
        statusMessage = enabled ? "Starting local collection…" : "Stopping local collection…"
        Task {
            defer { isBusy = false }
            do {
                apply(try await client.setEnabled(
                    enabled,
                    configuredCodexPath: configuredCodexPath
                ))
            } catch {
                isEnabled = previousValue
                isRunning = previousRunningValue
                statusMessage = error.localizedDescription
            }
        }
    }

    private func apply(_ status: ActivityInsightsCollectorStatus) {
        isEnabled = status.isEnabled
        isRunning = status.isRunning
        if !status.isEnabled {
            statusMessage = "Off. Existing local data stays on this Mac."
        } else if status.isRunning {
            statusMessage = "Collecting locally. Prompt text is counted for length, never stored."
        } else if status.isLoaded {
            statusMessage = "Enabled; the collector will resume automatically."
        } else {
            statusMessage = "Enabled, but the collector is not loaded."
        }
    }
}
