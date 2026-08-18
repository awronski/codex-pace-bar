import CodexActivityInsightsCore
import CodexActivityInsightsMac
import Darwin
import Foundation

@main
@MainActor
struct ActivityInsightsCollectorCommand {
    static func main() async {
        do {
            try await run()
        } catch {
            FileHandle.standardError.write(Data("ActivityInsightsCollector failed: \(error.localizedDescription)\n".utf8))
            Darwin.exit(1)
        }
    }

    private static func run() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("--help") || arguments.contains("-h") {
            printUsage()
            return
        }

        let storeURL = option("--store", in: arguments).map(URL.init(fileURLWithPath:))
            ?? ActivityInsightsRepository.defaultFileURL()
        let configurationURL = option("--configuration", in: arguments).map(URL.init(fileURLWithPath:))
            ?? storeURL.deletingLastPathComponent().appendingPathComponent("configuration.json")
        let configurationStore = ActivityInsightsConfigurationStore(fileURL: configurationURL)
        let repository = ActivityInsightsRepository(fileURL: storeURL)
        let controller = ActivityInsightsShadowController(
            configurationStore: configurationStore,
            repository: repository,
            chartSnapshotWriter: ActivityInsightsChartSnapshotWriter(
                fileURL: storeURL.deletingLastPathComponent().appendingPathComponent("chart-summary.json")
            ),
            configuredCodexPath: option("--codex", in: arguments)
        )

        let initialConfiguration = try await configurationStore.load()
        guard initialConfiguration.shadowEnabled else {
            FileHandle.standardError.write(Data("Activity Insights shadow collection is disabled.\n".utf8))
            return
        }
        await controller.startIfEnabled()
        guard controller.isRunning else {
            throw ActivityInsightsError.appServerStartupFailed("Shadow collection could not start.")
        }

        let duration = numberOption("--duration", in: arguments)
        if let duration, duration < 0 {
            throw ActivityInsightsError.persistence("Duration must be non-negative.")
        }
        let deadline = duration.map { Date().addingTimeInterval($0) }
        var stopReason: ActivityCollectorStopReason = duration == nil ? .requested : .durationEnded
        FileHandle.standardError.write(Data("Activity Insights shadow collection is running.\n".utf8))

        while deadline.map({ Date() < $0 }) ?? true {
            let remaining = deadline.map { max(0, $0.timeIntervalSinceNow) } ?? 5
            let wait = min(5, remaining)
            if wait <= 0 { break }
            try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard try await configurationStore.load().shadowEnabled else {
                stopReason = .disabled
                break
            }
        }

        await controller.stop(reason: stopReason)
        FileHandle.standardError.write(Data("Activity Insights shadow collection stopped.\n".utf8))
    }

    private static func option(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func numberOption(_ name: String, in arguments: [String]) -> TimeInterval? {
        option(name, in: arguments).flatMap(Double.init)
    }

    private static func printUsage() {
        print("""
        Usage: ActivityInsightsCollector [options]

          Runs the independent Activity Insights shadow collector while its
          configuration is enabled. Disable it with ActivityInsightsAudit disable.

        Options:
          --store PATH                   Override the independent archive path.
          --configuration PATH           Override the independent configuration path.
          --codex PATH                   Override the Codex executable.
          --duration SECONDS             Stop after a bounded duration; default is continuous.
        """)
    }
}
