@testable import CodexPaceBarCore
import Foundation
import SQLite3
import Testing

@Suite
struct TaskAllowanceTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func event(_ time: Date, _ tokens: Int64) -> TaskTokenEvent {
        TaskTokenEvent(timestamp: time, tokens: tokens, identity: UUID().uuidString, limitID: "codex", model: nil)
    }
    private func history(_ id: String, parent: String? = nil, events: [TaskTokenEvent]) -> TaskTokenHistory {
        TaskTokenHistory(id: id, name: "Task \(id)", project: "Project", parentID: parent, events: events)
    }

    @Test func allocationUsesAllTasksBeforeTakingTop20() {
        let histories = (0..<25).map { history(String($0), events: [event(start, 100)]) }
        let report = TaskAllowanceReport(windowStart: start, snapshotAt: start.addingTimeInterval(100),
            usedPercent: 60, histories: histories, warnings: [])
        let rows = report.rows(for: .sinceReset)
        #expect(rows.count == 25)
        #expect(abs(rows.reduce(0) { $0 + $1.percentagePoints } - 60) < 0.000001)
        #expect(abs(rows.prefix(20).reduce(0) { $0 + $1.percentagePoints } - 48) < 0.000001)
    }

    @Test func todayUsesWeeklyDenominatorAndIncludesChildTokens() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.startOfDay(for: start).addingTimeInterval(86400)
        let report = TaskAllowanceReport(windowStart: start, snapshotAt: today.addingTimeInterval(3600), usedPercent: 60,
            histories: [history("a", events: [event(start, 600), event(today, 100)]),
                        history("b", events: [event(start, 200)]),
                        history("child", parent: "a", events: [event(today, 100)])], warnings: [])
        let rows = report.rows(for: .today, calendar: calendar)
        #expect(rows.count == 1)
        #expect(rows.first?.id == "a")
        #expect(rows.first?.tokens == 200)
        #expect(rows.first?.percentagePoints == 12)
        #expect(report.rows(for: .sinceReset).first?.percentagePoints == 48)
    }

    @Test func todayClipsToResetAndRespectsLocalCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let report = TaskAllowanceReport(windowStart: start, snapshotAt: start.addingTimeInterval(60), usedPercent: 20,
            histories: [history("a", events: [event(start.addingTimeInterval(-1), 500), event(start, 100),
                                               event(start.addingTimeInterval(61), 900)])], warnings: [])
        #expect(report.periodStart(.today, calendar: calendar) == start)
        #expect(report.rows(for: .today, calendar: calendar).first?.tokens == 100)
        #expect(report.rows(for: .today, calendar: calendar).first?.percentagePoints == 20)
    }

    @Test func duplicateNotificationsCacheAndReasoningAreNotAddedAgain() {
        var parser = TaskTokenHistoryParser()
        parser.consume(meta("a", at: start))
        parser.consume(token(at: start, total: 100, last: 100))
        parser.consume(token(at: start, total: 100, last: 100))
        parser.consume(token(at: start.addingTimeInterval(1), total: 100, last: 100))
        parser.consume(token(at: start.addingTimeInterval(2), total: 150, last: 50))
        #expect(parser.events.map(\.tokens) == [100, 50])
        #expect(parser.warnings.isEmpty)
    }

    @Test func inheritedOpeningBalanceAndResumedCountersAreNotLifetimeUsage() {
        var parser = TaskTokenHistoryParser()
        parser.consume(meta("fork", at: start, inherited: true))
        parser.consume(token(at: start.addingTimeInterval(-100), total: 900, last: 900))
        parser.consume(token(at: start, total: 1000, last: 100))
        parser.consume(token(at: start.addingTimeInterval(10), total: 50, last: 50))
        parser.consume(token(at: start.addingTimeInterval(20), total: 80, last: 30))
        #expect(parser.events.map(\.tokens) == [100, 50, 30])
    }

    @Test func copiedSessionMetadataDoesNotChangeOwner() {
        var parser = TaskTokenHistoryParser()
        parser.consume(meta("fork", at: start))
        parser.consume(meta("original", at: start.addingTimeInterval(-100)))
        parser.consume(token(at: start, total: 1100, last: 100))
        #expect(parser.id == "fork")
        #expect(parser.events.first?.tokens == 100)
    }

    @Test func missingRequestCounterAndMismatchedTotalsAreQualified() {
        var parser = TaskTokenHistoryParser()
        parser.consume(meta("a", at: start))
        parser.consume(token(at: start, total: 100, last: 100))
        parser.consume(token(at: start.addingTimeInterval(1), total: 160, last: nil))
        parser.consume(token(at: start.addingTimeInterval(2), total: 200, last: 30))
        #expect(parser.events.map(\.tokens) == [100, 60, 30])
        #expect(parser.warnings.count == 2)
    }

    @Test func inheritedFirstCounterWithoutRequestIsNotCharged() {
        var parser = TaskTokenHistoryParser()
        parser.consume(meta("fork", at: start, inherited: true))
        parser.consume(token(at: start, total: 10000, last: nil))
        #expect(parser.events.isEmpty)
        #expect(!parser.warnings.isEmpty)
    }

    @Test(arguments: [false, true])
    func inheritedOpeningRequestCounterEstablishesBaseline(usesForkID: Bool) {
        var parser = TaskTokenHistoryParser()
        if usesForkID {
            parser.consume(json(["timestamp": stamp(start), "type": "session_meta",
                "payload": ["id": "fork", "timestamp": stamp(start), "forked_from_id": "original"]]))
        } else {
            parser.consume(meta("fork", at: start, inherited: true))
        }
        parser.consume(token(at: start, total: 10000, last: 100))
        #expect(parser.events.isEmpty)
        #expect(!parser.warnings.isEmpty)

        // A repeated opening notification stays excluded; subsequent work is counted.
        parser.consume(token(at: start.addingTimeInterval(1), total: 10000, last: 100))
        parser.consume(token(at: start.addingTimeInterval(2), total: 10050, last: 50))
        parser.consume(token(at: start.addingTimeInterval(3), total: 10080, last: nil))
        #expect(parser.events.map(\.tokens) == [50, 30])
    }

    @Test func resetBoundaryUsesMetadataUnlessLaterResetContradictsIt() {
        let window = CodexLimitWindow(limitId: "codex", source: "test", usedPercent: 10,
            windowDurationMins: 10080, resetsAt: start.addingTimeInterval(604800))
        let now = start.addingTimeInterval(200)
        #expect(TaskAllowanceBoundary.resolve(window: window, snapshotAt: now, samples: []).start == start)
        let samples = [UsageSample(timestamp: start.addingTimeInterval(50), usedPercent: 90,
                                    resetAt: window.resetsAt.addingTimeInterval(-7200), limitId: "codex"),
                       UsageSample(timestamp: start.addingTimeInterval(100), usedPercent: 1,
                                    resetAt: window.resetsAt, limitId: "codex")]
        let result = TaskAllowanceBoundary.resolve(window: window, snapshotAt: now, samples: samples)
        #expect(result.start == samples[1].timestamp)
        #expect(result.approximate)
        // Ordinary lower/stale readings with unchanged reset metadata do not reset the denominator.
        let correction = samples.map { UsageSample(timestamp: $0.timestamp, usedPercent: $0.usedPercent,
                                                   resetAt: window.resetsAt, limitId: "codex") }
        #expect(!TaskAllowanceBoundary.resolve(window: window, snapshotAt: now, samples: correction).approximate)
    }

    @Test func readerUsesCanonicalHistoryProjectNameArchivedAndExplicitParents() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let end = start.addingTimeInterval(300)
        try fixture.task(id: "parent", name: "Saved task title", project: "project", updated: start.addingTimeInterval(-10),
                         contents: meta("parent", at: start.addingTimeInterval(-1000)))
        try fixture.task(id: "child", name: "Agent", project: nil, updated: end,
                         contents: meta("child", at: start) + "\n" + token(at: start, total: 100, last: 100))
        try fixture.sql("INSERT INTO thread_spawn_edges VALUES ('parent', 'child')")
        try fixture.sql("INSERT INTO projects VALUES ('project', 'Saved Project')")
        // A separate fork keeps its own row. Its copied metadata never takes over ownership.
        try fixture.task(id: "fork", name: "Separate fork", project: nil, updated: end,
                         contents: meta("fork", at: start) + "\n" + meta("parent", at: start.addingTimeInterval(-1000))
                         + "\n" + token(at: start, total: 1050, last: 50))
        // Alternate owning-id file must not contribute to canonical total.
        try (meta("child", at: start) + "\n" + token(at: start, total: 900, last: 900))
            .write(to: fixture.home.appendingPathComponent("archived_sessions/duplicate.jsonl"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: end],
            ofItemAtPath: fixture.home.appendingPathComponent("archived_sessions/duplicate.jsonl").path)
        let reader = TaskTokenHistoryReader(home: fixture.home)
        let window = CodexLimitWindow(limitId: "codex", source: "test", usedPercent: 60,
            windowDurationMins: 10080, resetsAt: start.addingTimeInterval(604800))
        let report = try await reader.load(window: window, snapshotAt: end)
        let rows = report.rows(for: .sinceReset)
        #expect(rows.map(\.tokens) == [100, 50])
        #expect(rows.first?.name == "Saved task title")
        #expect(rows.first?.project == "Saved Project")
        #expect(rows.map(\.percentagePoints) == [40, 20])
        // Changing a file invalidates its cached token facts.
        try fixture.append("\n" + token(at: start.addingTimeInterval(50), total: 200, last: 100), task: "child")
        let refreshed = try await reader.load(window: window, snapshotAt: end)
        #expect(refreshed.rows(for: .sinceReset).first?.tokens == 200)
    }

    @Test func readerExcludesOtherBucketsAndReportsMissingHistory() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.task(id: "a", name: "A", project: nil, updated: start,
            contents: meta("a", at: start) + "\n" + token(at: start, total: 100, last: 100))
        try fixture.task(id: "spark", name: "Spark", project: nil, updated: start,
            contents: meta("spark", at: start) + "\n" + token(at: start, total: 900, last: 900, bucket: "codex-spark"))
        try fixture.sql("INSERT INTO threads VALUES ('missing','/no-such-task-history',1800000000,'/code/project','Missing',NULL,NULL,NULL,NULL,'openai')")
        let window = CodexLimitWindow(limitId: "codex", source: "test", usedPercent: 60,
            windowDurationMins: 10080, resetsAt: start.addingTimeInterval(604800))
        let report = try await TaskTokenHistoryReader(home: fixture.home).load(window: window, snapshotAt: start.addingTimeInterval(100))
        #expect(report.rows(for: .sinceReset).map(\.tokens) == [100])
        #expect(report.warnings.contains { $0.contains("missing or unreadable") })
        #expect(report.warnings.contains { $0.contains("Separate model buckets") })
    }

    @Test func missingDatabaseDoesNotCreateDatabase() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let window = CodexLimitWindow(limitId: "codex", source: "test", usedPercent: 60,
            windowDurationMins: 10080, resetsAt: start.addingTimeInterval(604800))
        await #expect(throws: TaskAllowanceError.self) {
            try await TaskTokenHistoryReader(home: home).load(window: window, snapshotAt: start.addingTimeInterval(1))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: home.path).isEmpty)
    }

    private func meta(_ id: String, at date: Date, inherited: Bool = false) -> String {
        json(["timestamp": stamp(date), "type": "session_meta", "payload": ["id": id, "timestamp": stamp(date),
              "cwd": "/code/test", "history_base": inherited ? ["id": "original"] as Any : NSNull()]])
    }
    private func token(at date: Date, total: Int, last: Int?, bucket: String = "codex") -> String {
        func usage(_ count: Int) -> [String: Int] {
            ["input_tokens": count - 10, "output_tokens": 10, "cached_input_tokens": count - 20,
             "reasoning_output_tokens": 5, "total_tokens": count]
        }
        return json(["timestamp": stamp(date), "type": "event_msg", "payload": ["type": "token_count",
            "rate_limits": ["limit_id": bucket], "info": ["total_token_usage": usage(total),
                "last_token_usage": last.map(usage) as Any? ?? NSNull()]]])
    }
    private func stamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    private func json(_ object: [String: Any]) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), encoding: .utf8)!
    }
}

private struct Fixture {
    let home: URL
    init() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("archived_sessions"), withIntermediateDirectories: true)
        try sql("CREATE TABLE threads (id TEXT, rollout_path TEXT, updated_at INTEGER, cwd TEXT, title TEXT, name TEXT, project_id TEXT, source TEXT, model TEXT, model_provider TEXT)")
        try sql("CREATE TABLE projects (id TEXT, name TEXT)")
        try sql("CREATE TABLE thread_spawn_edges (parent_thread_id TEXT, child_thread_id TEXT)")
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
    func sql(_ text: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(home.appendingPathComponent("state_5.sqlite").path, &db) == SQLITE_OK else { throw TaskAllowanceError.unreadableHistory }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, text, nil, nil, nil) == SQLITE_OK else { throw TaskAllowanceError.unreadableHistory }
    }
    func task(id: String, name: String, project: String?, updated: Date, contents: String) throws {
        let path = home.appendingPathComponent("archived_sessions/\(id).jsonl")
        try (contents + "\n").write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: updated], ofItemAtPath: path.path)
        let projectSQL = project.map { "'\($0)'" } ?? "NULL"
        try sql("INSERT INTO threads VALUES ('\(id)', '\(path.path)', \(Int(updated.timeIntervalSince1970)), '/code/project', 'Old title', '\(name)', \(projectSQL), NULL, NULL, 'openai')")
    }
    func append(_ text: String, task: String) throws {
        let handle = try FileHandle(forWritingTo: home.appendingPathComponent("archived_sessions/\(task).jsonl"))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }
}
