import CodexActivityInsightsControlAdapter
import Foundation
import Testing

@Suite
struct ActivityInsightsControlAdapterTests {
    @Test
    func statusReadsOnlySanitizedControlState() async throws {
        let runner = CommandRecorder(responses: [response(enabled: false, installed: false)])
        let client = makeClient(runner: runner)

        let status = try await client.status()

        #expect(status == .init(
            isEnabled: false,
            isInstalled: false,
            isLoaded: false,
            isRunning: false
        ))
        #expect(await runner.commands == [["control-status"]])
    }

    @Test
    func enablingFreshInstallInstallsThenStartsCollector() async throws {
        let runner = CommandRecorder(responses: [
            Data("{}".utf8),
            response(enabled: true, installed: true, loaded: true, running: true)
        ])
        let client = makeClient(runner: runner)

        let status = try await client.setEnabled(
            true,
            configuredCodexPath: "/tmp/codex"
        )

        #expect(status.isEnabled)
        #expect(status.isRunning)
        #expect(await runner.commands == [
            ["launcher-install", "--collector", "/tmp/ActivityInsightsCollector", "--codex", "/tmp/codex"],
            ["enable"]
        ])
    }

    @Test
    func enablingExistingInstallStillRefreshesBundledCollector() async throws {
        let runner = CommandRecorder(responses: [
            Data("{}".utf8),
            response(enabled: true, installed: true, loaded: true, running: true)
        ])
        let client = makeClient(runner: runner)

        _ = try await client.setEnabled(true, configuredCodexPath: nil)

        #expect(await runner.commands == [
            ["launcher-install", "--collector", "/tmp/ActivityInsightsCollector"],
            ["enable"]
        ])
    }

    @Test
    func reconcileRefreshesOnlyAnExistingInstallation() async throws {
        let installedRunner = CommandRecorder(responses: [
            response(enabled: false, installed: true),
            Data("{}".utf8),
            response(enabled: false, installed: true, loaded: true)
        ])
        let installedClient = makeClient(runner: installedRunner)
        _ = try await installedClient.reconcile(configuredCodexPath: "/tmp/codex")
        #expect(await installedRunner.commands == [
            ["control-status"],
            ["launcher-install", "--collector", "/tmp/ActivityInsightsCollector", "--codex", "/tmp/codex"],
            ["control-status"]
        ])

        let absentRunner = CommandRecorder(responses: [
            response(enabled: false, installed: false)
        ])
        let absentClient = makeClient(runner: absentRunner)
        _ = try await absentClient.reconcile(configuredCodexPath: nil)
        #expect(await absentRunner.commands == [["control-status"]])
    }

    @Test
    func disablingDoesNotInstallOrRemoveCollector() async throws {
        let runner = CommandRecorder(responses: [
            response(enabled: false, installed: true, loaded: true, running: true)
        ])
        let client = makeClient(runner: runner)

        let status = try await client.setEnabled(false, configuredCodexPath: nil)

        #expect(!status.isEnabled)
        #expect(await runner.commands == [["disable"]])
    }

    @Test
    func unreadableHelperResponseIsRejected() async {
        let runner = CommandRecorder(responses: [Data("not-json".utf8)])
        let client = makeClient(runner: runner)

        await #expect(throws: ActivityInsightsControlError.invalidResponse) {
            try await client.status()
        }
    }

    @Test @MainActor
    func controllerDistinguishesRunningFromEnabled() async {
        let runningController = ActivityInsightsCollectorController(
            client: makeClient(runner: CommandRecorder(responses: [
                response(enabled: true, installed: true, loaded: true, running: true)
            ]))
        )
        runningController.refresh()
        await waitUntilIdle(runningController)

        #expect(runningController.isEnabled)
        #expect(runningController.isRunning)

        let waitingController = ActivityInsightsCollectorController(
            client: makeClient(runner: CommandRecorder(responses: [
                response(enabled: true, installed: true, loaded: true, running: false)
            ]))
        )
        waitingController.refresh()
        await waitUntilIdle(waitingController)

        #expect(waitingController.isEnabled)
        #expect(!waitingController.isRunning)
    }

    private func makeClient(runner: CommandRecorder) -> ActivityInsightsControlClient {
        .init(
            auditExecutableURL: URL(fileURLWithPath: "/tmp/ActivityInsightsAudit"),
            collectorExecutableURL: URL(fileURLWithPath: "/tmp/ActivityInsightsCollector"),
            runner: runner
        )
    }

    private func response(
        enabled: Bool,
        installed: Bool,
        loaded: Bool = false,
        running: Bool = false
    ) -> Data {
        Data("""
        {
          "configuration": { "shadowEnabled": \(enabled) },
          "launcher": {
            "installed": \(installed),
            "loaded": \(loaded),
            "running": \(running)
          }
        }
        """.utf8)
    }

    @MainActor
    private func waitUntilIdle(_ controller: ActivityInsightsCollectorController) async {
        for _ in 0..<100 where controller.isBusy {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(!controller.isBusy)
    }
}

private actor CommandRecorder: ActivityInsightsCommandRunning {
    private var responses: [Data]
    private(set) var commands: [[String]] = []

    init(responses: [Data]) {
        self.responses = responses
    }

    func run(executableURL: URL, arguments: [String]) async throws -> Data {
        commands.append(arguments)
        return responses.removeFirst()
    }
}
