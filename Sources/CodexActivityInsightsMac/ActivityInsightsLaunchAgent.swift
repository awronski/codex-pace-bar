import CodexActivityInsightsCore
import Darwin
import Foundation

public struct ActivityLaunchCommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let output: String

    public init(exitCode: Int32, output: String = "") {
        self.exitCode = exitCode
        self.output = output
    }
}

public struct ActivityInsightsLaunchAgentStatus: Codable, Equatable, Sendable {
    public let installed: Bool
    public let loaded: Bool
    public let running: Bool

    public init(installed: Bool, loaded: Bool, running: Bool) {
        self.installed = installed
        self.loaded = loaded
        self.running = running
    }
}

@MainActor
public final class ActivityInsightsLaunchAgentManager {
    public static let label = "app.codexpacebar.activity-insights"
    private static let standardExecutableDirectories = [
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"
    ]

    public let plistURL: URL
    public let installedCollectorURL: URL

    private let logURL: URL
    private let userID: uid_t
    private let fileManager: FileManager
    private let homeDirectory: URL
    private let executableSearchPath: String
    private let runLaunchctl: @MainActor ([String]) throws -> ActivityLaunchCommandResult
    private let waitBeforeBootstrapRetry: @MainActor () -> Void

    public init(
        activityDirectory: URL = ActivityInsightsRepository.defaultDirectoryURL(),
        launchAgentsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true),
        userID: uid_t = getuid(),
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        executableSearchPath: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
        runLaunchctl: @escaping @MainActor ([String]) throws -> ActivityLaunchCommandResult = {
            try ActivityInsightsLaunchAgentManager.runLaunchctl(arguments: $0)
        },
        waitBeforeBootstrapRetry: @escaping @MainActor () -> Void = {
            Thread.sleep(forTimeInterval: 0.5)
        }
    ) {
        self.plistURL = launchAgentsDirectory.appendingPathComponent("\(Self.label).plist")
        self.installedCollectorURL = activityDirectory
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("ActivityInsightsCollector")
        self.logURL = activityDirectory.appendingPathComponent("collector.log")
        self.userID = userID
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.executableSearchPath = executableSearchPath
        self.runLaunchctl = runLaunchctl
        self.waitBeforeBootstrapRetry = waitBeforeBootstrapRetry
    }

    public func status() throws -> ActivityInsightsLaunchAgentStatus {
        let installed = fileManager.fileExists(atPath: plistURL.path)
            && fileManager.isExecutableFile(atPath: installedCollectorURL.path)
        let result = try runLaunchctl(["print", serviceTarget])
        return .init(
            installed: installed,
            loaded: result.exitCode == 0,
            running: result.exitCode == 0 && result.output.contains("state = running")
        )
    }

    @discardableResult
    public func install(
        collectorExecutableURL: URL,
        codexExecutableURL: URL
    ) throws -> ActivityInsightsLaunchAgentStatus {
        guard fileManager.isExecutableFile(atPath: collectorExecutableURL.path) else {
            throw ActivityInsightsError.persistence("Collector executable is missing or not executable.")
        }
        guard fileManager.isExecutableFile(atPath: codexExecutableURL.path) else {
            throw ActivityInsightsError.codexExecutableNotFound
        }
        let launchEnvironmentPath = try launchEnvironmentPath(for: codexExecutableURL)
        let collectorData = try Data(contentsOf: collectorExecutableURL)
        let propertyList: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": [
                installedCollectorURL.path,
                "--codex",
                codexExecutableURL.path
            ],
            "EnvironmentVariables": ["PATH": launchEnvironmentPath],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Background",
            "ThrottleInterval": 60,
            "StandardOutPath": logURL.path,
            "StandardErrorPath": logURL.path
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .xml,
            options: 0
        )
        let currentStatus = try status()
        let collectorMatches = (try? Data(contentsOf: installedCollectorURL)) == collectorData
        let plistMatches = (try? Data(contentsOf: plistURL)) == plistData
        let needsReplacement = !currentStatus.installed || !collectorMatches || !plistMatches

        if !needsReplacement {
            if currentStatus.loaded { return currentStatus }
            let bootstrap = try bootstrapWithOneRetry()
            guard bootstrap.exitCode == 0 else {
                throw ActivityInsightsError.persistence(
                    "LaunchAgent could not be loaded (launchctl exit \(bootstrap.exitCode))."
                )
            }
            return try status()
        }

        if currentStatus.loaded {
            let bootout = try runLaunchctl(["bootout", serviceTarget])
            guard bootout.exitCode == 0 else {
                throw ActivityInsightsError.persistence(
                    "LaunchAgent could not be unloaded for replacement "
                        + "(launchctl exit \(bootout.exitCode))."
                )
            }
        }

        try fileManager.createDirectory(
            at: installedCollectorURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try collectorData.write(
            to: installedCollectorURL,
            options: .atomic
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: installedCollectorURL.path
        )
        try plistData.write(to: plistURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: plistURL.path
        )
        let bootstrap = try bootstrapWithOneRetry()
        guard bootstrap.exitCode == 0 else {
            throw ActivityInsightsError.persistence(
                "LaunchAgent could not be loaded (launchctl exit \(bootstrap.exitCode))."
            )
        }
        return try status()
    }

    public func start() throws {
        let currentStatus = try status()
        guard currentStatus.installed else {
            throw ActivityInsightsError.persistence("Install the Activity Insights LaunchAgent first.")
        }
        if currentStatus.loaded {
            let bootout = try runLaunchctl(["bootout", serviceTarget])
            guard bootout.exitCode == 0 else {
                throw ActivityInsightsError.persistence("LaunchAgent could not be reloaded.")
            }
        }
        let bootstrap = try bootstrapWithOneRetry()
        guard bootstrap.exitCode == 0 else {
            throw ActivityInsightsError.persistence(
                "LaunchAgent could not be started (launchctl exit \(bootstrap.exitCode))."
            )
        }
    }

    @discardableResult
    public func uninstall() throws -> ActivityInsightsLaunchAgentStatus {
        if (try status()).loaded {
            let result = try runLaunchctl(["bootout", serviceTarget])
            guard result.exitCode == 0 else {
                throw ActivityInsightsError.persistence("LaunchAgent could not be unloaded.")
            }
        }
        if fileManager.fileExists(atPath: plistURL.path) {
            try fileManager.removeItem(at: plistURL)
        }
        if fileManager.fileExists(atPath: installedCollectorURL.path) {
            try fileManager.removeItem(at: installedCollectorURL)
        }
        return try status()
    }

    private var domainTarget: String { "gui/\(userID)" }
    private var serviceTarget: String { "\(domainTarget)/\(Self.label)" }

    private func bootstrapWithOneRetry() throws -> ActivityLaunchCommandResult {
        var result = try runLaunchctl(["bootstrap", domainTarget, plistURL.path])
        if result.exitCode != 0 {
            waitBeforeBootstrapRetry()
            result = try runLaunchctl(["bootstrap", domainTarget, plistURL.path])
        }
        return result
    }

    private func launchEnvironmentPath(for executableURL: URL) throws -> String {
        let home = homeDirectory
        var directories = executableSearchPath
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
        directories += [
            executableURL.deletingLastPathComponent().path,
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent(".npm-global/bin").path,
            home.appendingPathComponent(".bun/bin").path,
            home.appendingPathComponent(".local/share/mise/shims").path
        ]
        directories += Self.standardExecutableDirectories
        if let interpreter = try environmentInterpreterName(for: executableURL) {
            guard let interpreterURL = findExecutable(interpreter, directories: directories) else {
                throw ActivityInsightsError.persistence(
                    "The Codex launcher requires '\(interpreter)', but it was not found in PATH. "
                        + "Configure a Codex executable whose runtime is installed on this Mac."
                )
            }
            directories.insert(interpreterURL.deletingLastPathComponent().path, at: 0)
        }
        var seen = Set<String>()
        return directories.filter { seen.insert($0).inserted }.joined(separator: ":")
    }

    private func environmentInterpreterName(for executableURL: URL) throws -> String? {
        let handle = try FileHandle(forReadingFrom: executableURL)
        defer { try? handle.close() }
        guard let data = try handle.read(upToCount: 256), !data.isEmpty else { return nil }
        let firstLine = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: { $0.isNewline })
            .first
            .map(String.init)
        guard let firstLine, firstLine.hasPrefix("#!/usr/bin/env ") else { return nil }

        var arguments = firstLine
            .dropFirst("#!/usr/bin/env ".count)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        if arguments.first == "-S" { arguments.removeFirst() }
        return arguments.first(where: { !$0.hasPrefix("-") && !$0.contains("=") })
    }

    private func findExecutable(_ name: String, directories: [String]) -> URL? {
        return directories
            .map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    public static func runLaunchctl(arguments: [String]) throws -> ActivityLaunchCommandResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        return ActivityLaunchCommandResult(
            exitCode: process.terminationStatus,
            output: output
        )
    }
}
