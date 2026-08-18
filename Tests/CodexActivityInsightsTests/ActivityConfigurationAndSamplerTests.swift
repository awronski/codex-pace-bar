@preconcurrency import AppKit
import CodexActivityInsightsCore
@testable import CodexActivityInsightsMac
import Foundation
import Testing

@Suite
struct ActivityInsightsConfigurationTests {
    @Test
    func shadowCollectionIsOffByDefaultAndCanBeEnabledAndDisabled() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ActivityInsightsConfigurationStore(fileURL: directory.appendingPathComponent("configuration.json"))

        #expect(try await store.load().shadowEnabled == false)
        let enabled = try await store.setShadowEnabled(true, now: testDate(1_000))
        #expect(enabled.shadowEnabled)
        #expect(enabled.shadowEnabledSince == testDate(1_000))
        #expect(try await store.load().shadowEnabled)
        #expect(try await store.setShadowEnabled(false).shadowEnabled == false)
        #expect(try await store.load().shadowEnabledSince == nil)
    }

    @Test
    func invalidSamplingConfigurationIsRejected() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ActivityInsightsConfigurationStore(fileURL: directory.appendingPathComponent("configuration.json"))

        do {
            try await store.save(.init(
                shadowEnabled: true,
                historyIntervalSeconds: 300,
                sampleIntervalSeconds: 0,
                lookbackDays: 30
            ))
            Issue.record("Expected invalid interval to fail.")
        } catch let error as ActivityInsightsError {
            #expect(error == .persistence("Configuration intervals and lookback must be positive."))
        }
    }
}

@Suite(.serialized)
@MainActor
struct MacActivitySamplerTests {
    @Test
    func failedDeferredHistoryCheckpointUsesScheduledBackoff() {
        let cleanBacklog = ActivityCollectionRun(
            startedAt: testDate(1_000),
            finishedAt: testDate(1_001),
            pagesRead: 1,
            threadsSeen: 3,
            threadsCollected: 1,
            threadsUnchanged: 0,
            threadsDeferred: 2,
            turnsCollected: 1,
            inputsCollected: 1,
            threadFailures: 0
        )
        let failedBacklog = ActivityCollectionRun(
            startedAt: testDate(1_000),
            finishedAt: testDate(1_001),
            pagesRead: 1,
            threadsSeen: 3,
            threadsCollected: 1,
            threadsUnchanged: 0,
            threadsDeferred: 2,
            turnsCollected: 0,
            inputsCollected: 0,
            threadFailures: 1,
            failureCounts: ["history_timeout": 1]
        )

        #expect(ActivityInsightsShadowController.shouldContinueHistoryBackfillImmediately(
            after: cleanBacklog
        ))
        #expect(!ActivityInsightsShadowController.shouldContinueHistoryBackfillImmediately(
            after: failedBacklog
        ))
    }

    @Test
    func disabledShadowControllerDoesNotResolveCodexOrCreateDataStore() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configurationStore = ActivityInsightsConfigurationStore(
            fileURL: directory.appendingPathComponent("configuration.json")
        )
        let archiveURL = directory.appendingPathComponent("archive.json")
        let controller = ActivityInsightsShadowController(
            configurationStore: configurationStore,
            repository: ActivityInsightsRepository(fileURL: archiveURL),
            sampler: MacActivitySampler(notificationCenter: NotificationCenter(), idleReader: { 0 }),
            resolver: ActivityCodexExecutableResolver(path: "", home: directory)
        )

        await controller.startIfEnabled()

        #expect(!controller.isRunning)
        #expect(!FileManager.default.fileExists(atPath: archiveURL.path))
    }

    @Test
    func physicalIdleReadingMapsToThreeExplicitActivityThresholds() {
        let center = NotificationCenter()
        let sampler = MacActivitySampler(
            notificationCenter: center,
            idleReader: { 180 },
            frontmostBundleIdentifierReader: { MacActivitySampler.codexDesktopBundleIdentifier }
        )
        sampler.start()
        defer { sampler.stop() }

        let observation = sampler.observation(at: testDate(1_200), intervalSeconds: 15)
        let minute = observation.minuteFacts[0]

        #expect(minute.observedSeconds == 15)
        #expect(minute.activeWithinTwoMinutesSeconds == 0)
        #expect(minute.activeWithinFiveMinutesSeconds == 15)
        #expect(minute.activeWithinTenMinutesSeconds == 15)
        #expect(minute.unavailableSeconds == 0)
        #expect(observation.fact?.userState == .active)
        #expect(observation.fact?.codexFocus == .focused)
    }

    @Test
    func frontmostApplicationIsReducedToCodexFocusWithoutPersistingItsIdentity() {
        let codex = MacActivitySampler(
            notificationCenter: NotificationCenter(),
            idleReader: { 1 },
            frontmostBundleIdentifierReader: { MacActivitySampler.codexDesktopBundleIdentifier }
        )
        let anotherApplication = MacActivitySampler(
            notificationCenter: NotificationCenter(),
            idleReader: { 1 },
            frontmostBundleIdentifierReader: { "private.other-application.marker" }
        )
        let unavailable = MacActivitySampler(
            notificationCenter: NotificationCenter(),
            idleReader: { 1 },
            frontmostBundleIdentifierReader: { nil }
        )

        #expect(codex.observation(at: testDate(1_200), intervalSeconds: 15).codexFocus == .focused)
        #expect(anotherApplication.observation(at: testDate(1_200), intervalSeconds: 15).codexFocus == .notFocused)
        #expect(unavailable.observation(at: testDate(1_200), intervalSeconds: 15).codexFocus == .unknown)
    }

    @Test
    func sleepScreenAndSessionGatesRecordUnknownCoverageUntilEachRecovers() {
        let center = NotificationCenter()
        let sampler = MacActivitySampler(
            notificationCenter: center,
            idleReader: { 1 },
            frontmostBundleIdentifierReader: { MacActivitySampler.codexDesktopBundleIdentifier }
        )
        sampler.start()
        defer { sampler.stop() }

        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        let sleeping = sampler.observation(at: testDate(1_200), intervalSeconds: 10)
        #expect(sleeping.minuteFacts[0].unavailableSeconds == 10)
        #expect(sleeping.codexFocus == .unknown)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(sampler.observation(at: testDate(1_210), intervalSeconds: 10).minuteFacts[0].observedSeconds == 10)

        center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        #expect(sampler.observation(at: testDate(1_220), intervalSeconds: 10).minuteFacts[0].unavailableSeconds == 10)
        center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)

        center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        #expect(sampler.observation(at: testDate(1_230), intervalSeconds: 10).minuteFacts[0].unavailableSeconds == 10)
        center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        #expect(sampler.observation(at: testDate(1_240), intervalSeconds: 10).minuteFacts[0].observedSeconds == 10)
    }

    @Test
    func invalidIdleReadingIsUnavailableNotInactive() {
        let sampler = MacActivitySampler(notificationCenter: NotificationCenter(), idleReader: { .nan })

        let minute = sampler.observation(at: testDate(1_200), intervalSeconds: 15).minuteFacts[0]

        #expect(minute.observedSeconds == 0)
        #expect(minute.unavailableSeconds == 15)
    }
}
