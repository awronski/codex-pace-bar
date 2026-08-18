import CodexActivityInsightsCore
import CodexActivityInsightsMac
import Foundation
import Testing

@Suite(.serialized)
@MainActor
struct ActivityInsightsLaunchAgentTests {
    @Test
    func installWritesIndependentLaunchAgentRuntimePathAndSupportsReload() throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let collector = directory.appendingPathComponent("build/ActivityInsightsCollector")
        let codex = directory.appendingPathComponent("bin/codex")
        let node = directory.appendingPathComponent("runtime/node")
        try FileManager.default.createDirectory(
            at: collector.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: codex.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: node.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("collector".utf8).write(to: collector)
        try Data("#!/usr/bin/env node\n".utf8).write(to: codex)
        try Data("node".utf8).write(to: node)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: collector.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codex.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)

        var loaded = false
        var running = false
        var calls: [[String]] = []
        let manager = ActivityInsightsLaunchAgentManager(
            activityDirectory: directory.appendingPathComponent("activity"),
            launchAgentsDirectory: directory.appendingPathComponent("LaunchAgents"),
            userID: 501,
            homeDirectory: directory,
            executableSearchPath: node.deletingLastPathComponent().path,
            runLaunchctl: { arguments in
                calls.append(arguments)
                switch arguments.first {
                case "print":
                    return ActivityLaunchCommandResult(
                        exitCode: loaded ? 0 : 113,
                        output: running ? "state = running" : "state = exited"
                    )
                case "bootstrap":
                    loaded = true
                    if calls.filter({ $0.first == "bootstrap" }).count > 1 {
                        running = true
                    }
                    return ActivityLaunchCommandResult(exitCode: 0)
                case "bootout":
                    loaded = false
                    running = false
                    return ActivityLaunchCommandResult(exitCode: 0)
                default:
                    return ActivityLaunchCommandResult(exitCode: 1)
                }
            }
        )

        let installed = try manager.install(
            collectorExecutableURL: collector,
            codexExecutableURL: codex
        )
        try manager.start()
        let started = try manager.status()

        #expect(installed == ActivityInsightsLaunchAgentStatus(
            installed: true,
            loaded: true,
            running: false
        ))
        #expect(started.running)
        #expect(calls.contains(["bootstrap", "gui/501", manager.plistURL.path]))
        #expect(calls.contains(["bootout", "gui/501/\(ActivityInsightsLaunchAgentManager.label)"]))

        let plistData = try Data(contentsOf: manager.plistURL)
        let plist = try #require(
            PropertyListSerialization.propertyList(from: plistData, format: nil)
                as? [String: Any]
        )
        #expect(plist["Label"] as? String == ActivityInsightsLaunchAgentManager.label)
        #expect(plist["RunAtLoad"] as? Bool == true)
        #expect((plist["KeepAlive"] as? [String: Bool])?["SuccessfulExit"] == false)
        #expect((plist["EnvironmentVariables"] as? [String: String])?["PATH"] == [
            node.deletingLastPathComponent().path,
            codex.deletingLastPathComponent().path,
            directory.appendingPathComponent(".local/bin").path,
            directory.appendingPathComponent(".npm-global/bin").path,
            directory.appendingPathComponent(".bun/bin").path,
            directory.appendingPathComponent(".local/share/mise/shims").path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ].joined(separator: ":"))
        #expect(plist["ProgramArguments"] as? [String] == [
            manager.installedCollectorURL.path,
            "--codex",
            codex.path
        ])
        #expect(FileManager.default.isExecutableFile(atPath: manager.installedCollectorURL.path))
    }

    @Test
    func installRejectsEnvironmentLauncherWhenInterpreterIsUnavailable() throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let collector = directory.appendingPathComponent("collector")
        let codex = directory.appendingPathComponent("codex")
        try Data("collector".utf8).write(to: collector)
        try Data("#!/usr/bin/env missing-runtime\n".utf8).write(to: codex)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: collector.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codex.path)
        let manager = ActivityInsightsLaunchAgentManager(
            activityDirectory: directory.appendingPathComponent("activity"),
            launchAgentsDirectory: directory.appendingPathComponent("LaunchAgents"),
            userID: 501,
            homeDirectory: directory,
            executableSearchPath: "",
            runLaunchctl: { _ in ActivityLaunchCommandResult(exitCode: 113) }
        )

        #expect(throws: ActivityInsightsError.persistence(
            "The Codex launcher requires 'missing-runtime', but it was not found in PATH. "
                + "Configure a Codex executable whose runtime is installed on this Mac."
        )) {
            try manager.install(collectorExecutableURL: collector, codexExecutableURL: codex)
        }
        #expect(!FileManager.default.fileExists(atPath: manager.plistURL.path))
    }

    @Test
    func unchangedReinstallDoesNotRestartLoadedAgentButChangedCollectorDoes() throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let collector = directory.appendingPathComponent("collector")
        let codex = directory.appendingPathComponent("codex")
        try Data("collector-v1".utf8).write(to: collector)
        try Data("codex".utf8).write(to: codex)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: collector.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codex.path)
        var loaded = false
        var bootoutCount = 0
        var bootstrapCount = 0
        let manager = ActivityInsightsLaunchAgentManager(
            activityDirectory: directory.appendingPathComponent("activity"),
            launchAgentsDirectory: directory.appendingPathComponent("LaunchAgents"),
            userID: 501,
            homeDirectory: directory,
            executableSearchPath: "",
            runLaunchctl: { arguments in
                switch arguments.first {
                case "print": return .init(exitCode: loaded ? 0 : 113)
                case "bootout":
                    bootoutCount += 1
                    loaded = false
                    return .init(exitCode: 0)
                case "bootstrap":
                    bootstrapCount += 1
                    loaded = true
                    return .init(exitCode: 0)
                default: return .init(exitCode: 1)
                }
            }
        )

        _ = try manager.install(collectorExecutableURL: collector, codexExecutableURL: codex)
        _ = try manager.install(collectorExecutableURL: collector, codexExecutableURL: codex)
        #expect(bootoutCount == 0)
        #expect(bootstrapCount == 1)

        try Data("collector-v2".utf8).write(to: collector)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: collector.path)
        _ = try manager.install(collectorExecutableURL: collector, codexExecutableURL: codex)

        #expect(bootoutCount == 1)
        #expect(bootstrapCount == 2)
        #expect(try Data(contentsOf: manager.installedCollectorURL) == Data("collector-v2".utf8))
    }

    @Test
    func reinstallRetriesTransientBootstrapAfterBootout() throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let collector = directory.appendingPathComponent("collector")
        let codex = directory.appendingPathComponent("codex")
        try Data("collector".utf8).write(to: collector)
        try Data("codex".utf8).write(to: codex)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: collector.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codex.path)

        var loaded = true
        var bootstrapAttempts = 0
        var retryWaits = 0
        let manager = ActivityInsightsLaunchAgentManager(
            activityDirectory: directory.appendingPathComponent("activity"),
            launchAgentsDirectory: directory.appendingPathComponent("LaunchAgents"),
            userID: 501,
            runLaunchctl: { arguments in
                switch arguments.first {
                case "print":
                    return ActivityLaunchCommandResult(exitCode: loaded ? 0 : 113)
                case "bootout":
                    loaded = false
                    return ActivityLaunchCommandResult(exitCode: 0)
                case "bootstrap":
                    bootstrapAttempts += 1
                    if bootstrapAttempts == 1 {
                        return ActivityLaunchCommandResult(exitCode: 5)
                    }
                    loaded = true
                    return ActivityLaunchCommandResult(exitCode: 0)
                default:
                    return ActivityLaunchCommandResult(exitCode: 1)
                }
            },
            waitBeforeBootstrapRetry: { retryWaits += 1 }
        )

        let status = try manager.install(
            collectorExecutableURL: collector,
            codexExecutableURL: codex
        )

        #expect(status.loaded)
        #expect(bootstrapAttempts == 2)
        #expect(retryWaits == 1)
    }

    @Test
    func uninstallRemovesOnlyManagedFiles() throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let collector = directory.appendingPathComponent("collector")
        let codex = directory.appendingPathComponent("codex")
        try Data("collector".utf8).write(to: collector)
        try Data("codex".utf8).write(to: codex)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: collector.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codex.path)
        var loaded = false
        let manager = ActivityInsightsLaunchAgentManager(
            activityDirectory: directory.appendingPathComponent("activity"),
            launchAgentsDirectory: directory.appendingPathComponent("LaunchAgents"),
            userID: 501,
            runLaunchctl: { arguments in
                if arguments.first == "bootstrap" { loaded = true }
                if arguments.first == "bootout" { loaded = false }
                return ActivityLaunchCommandResult(exitCode: arguments.first == "print" && !loaded ? 113 : 0)
            }
        )
        _ = try manager.install(collectorExecutableURL: collector, codexExecutableURL: codex)

        let status = try manager.uninstall()

        #expect(status == ActivityInsightsLaunchAgentStatus(
            installed: false,
            loaded: false,
            running: false
        ))
        #expect(!FileManager.default.fileExists(atPath: manager.plistURL.path))
        #expect(!FileManager.default.fileExists(atPath: manager.installedCollectorURL.path))
        #expect(FileManager.default.fileExists(atPath: collector.path))
        #expect(FileManager.default.fileExists(atPath: codex.path))
    }
}
