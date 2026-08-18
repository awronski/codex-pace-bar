import CodexActivityInsightsChartAdapter
import CodexActivityInsightsContract
import Foundation
import Testing

@Suite
struct ActivityInsightsChartAdapterTests {
    @Test
    func missingSnapshotIsAbsentAndCreatesNothing() async throws {
        let directory = temporaryDirectory()
        let fileURL = directory.appendingPathComponent("chart-summary.json")
        let reader = ActivityInsightsChartReader(fileURL: fileURL)

        #expect(await reader.read(at: date(1_000)) == .absent)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test
    func validSnapshotMapsReadyPartialStaleAndDisabled() async throws {
        let directory = try createdTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("chart-summary.json")
        let reader = ActivityInsightsChartReader(fileURL: fileURL)

        try write(snapshot(), to: fileURL)
        #expect(await reader.read(at: date(1_000)) == .ready(snapshot()))

        let partial = snapshot(fourStateCoverage: 94)
        try write(partial, to: fileURL)
        #expect(await reader.read(at: date(1_000)) == .partial(partial))

        try write(snapshot(), to: fileURL)
        #expect(await reader.read(at: date(1_100)) == .stale(snapshot()))

        let disabled = snapshot(collectionEnabled: false)
        try write(disabled, to: fileURL)
        #expect(await reader.read(at: date(1_000)) == .disabled)
    }

    @Test
    func emptySnapshotIsCollectingOnlyWhileHeartbeatIsFresh() async throws {
        let directory = try createdTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("chart-summary.json")
        let reader = ActivityInsightsChartReader(fileURL: fileURL)
        let empty = snapshot(hasData: false)
        try write(empty, to: fileURL)

        #expect(await reader.read(at: date(1_000)) == .collecting(empty))
        #expect(await reader.read(at: date(1_100)) == .stale(empty))
    }

    @Test
    func unsupportedAndInvalidSnapshotsFailClosed() async throws {
        let directory = try createdTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("chart-summary.json")
        let reader = ActivityInsightsChartReader(fileURL: fileURL)

        try write(snapshot(schemaVersion: 99), to: fileURL)
        #expect(await reader.read(at: date(1_000)) == .unavailable(.unsupportedSchema))

        try write(snapshot(activeWorking: -1), to: fileURL)
        #expect(await reader.read(at: date(1_000)) == .unavailable(.invalidSnapshot))

        try write(snapshot(generatedAt: date(1_400)), to: fileURL)
        #expect(await reader.read(at: date(1_000)) == .unavailable(.invalidSnapshot))

        try Data("not-json".utf8).write(to: fileURL)
        #expect(await reader.read(at: date(1_000)) == .unavailable(.unreadable))
    }

    @Test
    func readsDoNotModifySnapshot() async throws {
        let directory = try createdTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("chart-summary.json")
        let original = try encoded(snapshot())
        try original.write(to: fileURL)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let reader = ActivityInsightsChartReader(fileURL: fileURL)

        _ = await reader.read(at: date(1_000))
        _ = await reader.read(at: date(1_000))

        #expect(try Data(contentsOf: fileURL) == original)
        #expect(try FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date
            == attributes[.modificationDate] as? Date)
    }

    @MainActor
    @Test
    func storeKeepsLastGoodSnapshotAfterTransientFailure() async {
        let good = snapshot()
        let reader = SequenceReader(states: [.ready(good), .unavailable(.unreadable)])
        let store = ActivityInsightsChartStore(reader: reader, now: { date(1_000) })

        await store.refresh()
        #expect(store.state == .ready(good))
        await store.refresh()
        #expect(store.state == .stale(good))
    }

    @Test
    func activeShareRangeIncludesOnlyActiveUnknownTime() {
        let state = snapshot().fourState
        #expect(state.confirmedActiveCodexSharePercent == 50)
        #expect(state.possibleActiveCodexSharePercent == 75)
    }

    @Test
    func codexWorkingShareSplitsHandsOnFromHandsOff() {
        let state = snapshot().fourState
        #expect(state.codexWorkingSeconds == 15)
        #expect(abs((state.handsOnCodexSharePercent ?? 0) - (100.0 / 1.5)) < 0.000_001)
        #expect(abs((state.handsOffCodexSharePercent ?? 0) - (100.0 / 3)) < 0.000_001)
    }

    private func snapshot(
        schemaVersion: Int = ActivityInsightsChartSnapshot.currentSchemaVersion,
        collectionEnabled: Bool = true,
        fourStateCoverage: Double = 100,
        activeWorking: Double = 10,
        generatedAt: Date = Date(timeIntervalSince1970: 1_000),
        hasData: Bool = true
    ) -> ActivityInsightsChartSnapshot {
        ActivityInsightsChartSnapshot(
            schemaVersion: schemaVersion,
            generatedAt: generatedAt,
            sourceUpdatedAt: date(999),
            windowStart: date(100),
            windowEnd: date(1_000),
            collectionEnabled: collectionEnabled,
            collectorHeartbeatAt: date(990),
            heartbeatGraceSeconds: 45,
            fourState: .init(
                activeCodexWorkingSeconds: hasData ? activeWorking : 0,
                activeCodexIdleSeconds: hasData ? 5 : 0,
                inactiveCodexWorkingSeconds: hasData ? 5 : 0,
                inactiveCodexIdleSeconds: hasData ? 15 : 0,
                activeCodexUnknownSeconds: hasData ? 5 : 0,
                inactiveCodexUnknownSeconds: 0,
                unknownUserCodexWorkingSeconds: 0,
                unknownUserCodexIdleSeconds: 0,
                unknownUserCodexUnknownSeconds: 0
            ),
            workingFocus: .init(
                focusedSeconds: hasData ? 10 : 0,
                notFocusedSeconds: hasData ? 5 : 0,
                unknownSeconds: 0
            ),
            quality: .init(
                fourStateCoveragePercent: fourStateCoverage,
                focusCoveragePercent: 100,
                historySyncCoveragePercent: 100,
                provisionalTurnCount: 0
            )
        )
    }

    private func write(_ snapshot: ActivityInsightsChartSnapshot, to fileURL: URL) throws {
        try encoded(snapshot).write(to: fileURL, options: .atomic)
    }

    private func encoded(_ snapshot: ActivityInsightsChartSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivityInsightsChartAdapterTests-\(UUID().uuidString)")
    }

    private func createdTemporaryDirectory() throws -> URL {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private actor SequenceReader: ActivityInsightsChartReading {
    private var states: [ActivityInsightsChartState]

    init(states: [ActivityInsightsChartState]) {
        self.states = states
    }

    func read(at now: Date) async -> ActivityInsightsChartState {
        states.isEmpty ? .absent : states.removeFirst()
    }
}
