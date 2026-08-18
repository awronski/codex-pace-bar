import Foundation

public struct ActivityInsightsCollectorStatus: Equatable, Sendable {
    public let isEnabled: Bool
    public let isInstalled: Bool
    public let isLoaded: Bool
    public let isRunning: Bool

    public init(
        isEnabled: Bool,
        isInstalled: Bool,
        isLoaded: Bool,
        isRunning: Bool
    ) {
        self.isEnabled = isEnabled
        self.isInstalled = isInstalled
        self.isLoaded = isLoaded
        self.isRunning = isRunning
    }
}

public enum ActivityInsightsControlError: LocalizedError, Equatable, Sendable {
    case bundledHelperMissing(String)
    case commandFailed(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .bundledHelperMissing(let name):
            "The bundled \(name) helper is unavailable."
        case .commandFailed(let message):
            message
        case .invalidResponse:
            "The Activity Insights helper returned an unreadable response."
        }
    }
}

public protocol ActivityInsightsCommandRunning: Sendable {
    func run(executableURL: URL, arguments: [String]) async throws -> Data
}

public struct ActivityInsightsProcessRunner: ActivityInsightsCommandRunning {
    public init() {}

    public func run(executableURL: URL, arguments: [String]) async throws -> Data {
        try await Task.detached {
            let process = Process()
            let output = Pipe()
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let message = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw ActivityInsightsControlError.commandFailed(
                    message.isEmpty ? "Activity Insights could not be updated." : message
                )
            }
            return data
        }.value
    }
}

public struct ActivityInsightsControlClient: Sendable {
    private let auditExecutableURL: URL
    private let collectorExecutableURL: URL
    private let runner: any ActivityInsightsCommandRunning

    public init(
        auditExecutableURL: URL,
        collectorExecutableURL: URL,
        runner: any ActivityInsightsCommandRunning = ActivityInsightsProcessRunner()
    ) {
        self.auditExecutableURL = auditExecutableURL
        self.collectorExecutableURL = collectorExecutableURL
        self.runner = runner
    }

    public static func bundled(in bundle: Bundle = .main) throws -> Self {
        guard let auditURL = bundle.url(forResource: "ActivityInsightsAudit", withExtension: nil) else {
            throw ActivityInsightsControlError.bundledHelperMissing("Activity Insights control")
        }
        guard let collectorURL = bundle.url(
            forResource: "ActivityInsightsCollector",
            withExtension: nil
        ) else {
            throw ActivityInsightsControlError.bundledHelperMissing("Activity Insights collector")
        }
        return .init(
            auditExecutableURL: auditURL,
            collectorExecutableURL: collectorURL
        )
    }

    public func status() async throws -> ActivityInsightsCollectorStatus {
        try decode(try await runner.run(
            executableURL: auditExecutableURL,
            arguments: ["control-status"]
        ))
    }

    public func setEnabled(
        _ enabled: Bool,
        configuredCodexPath: String?
    ) async throws -> ActivityInsightsCollectorStatus {
        if enabled {
            _ = try await runner.run(
                executableURL: auditExecutableURL,
                arguments: launcherInstallArguments(configuredCodexPath: configuredCodexPath)
            )
        }

        return try decode(try await runner.run(
            executableURL: auditExecutableURL,
            arguments: [enabled ? "enable" : "disable"]
        ))
    }

    /// Refreshes an existing opt-in installation after an app or Codex path update. It never
    /// installs the collector for a user who has not installed it before.
    public func reconcile(configuredCodexPath: String?) async throws -> ActivityInsightsCollectorStatus {
        let current = try await status()
        guard current.isInstalled else { return current }
        _ = try await runner.run(
            executableURL: auditExecutableURL,
            arguments: launcherInstallArguments(configuredCodexPath: configuredCodexPath)
        )
        return try await status()
    }

    private func launcherInstallArguments(configuredCodexPath: String?) -> [String] {
        var arguments = [
            "launcher-install",
            "--collector",
            collectorExecutableURL.path
        ]
        if let path = configuredCodexPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty,
           path != "codex" {
            arguments += ["--codex", path]
        }
        return arguments
    }

    private func decode(_ data: Data) throws -> ActivityInsightsCollectorStatus {
        do {
            let response = try JSONDecoder().decode(ControlResponse.self, from: data)
            return .init(
                isEnabled: response.configuration.shadowEnabled,
                isInstalled: response.launcher.installed,
                isLoaded: response.launcher.loaded,
                isRunning: response.launcher.running
            )
        } catch let error as ActivityInsightsControlError {
            throw error
        } catch {
            throw ActivityInsightsControlError.invalidResponse
        }
    }
}

private struct ControlResponse: Decodable {
    struct Configuration: Decodable {
        let shadowEnabled: Bool
    }

    struct Launcher: Decodable {
        let installed: Bool
        let loaded: Bool
        let running: Bool
    }

    let configuration: Configuration
    let launcher: Launcher
}
