import Darwin
import Foundation
import SQLite3

/// Independent, on-demand reader. Connections are read-only and caches contain no conversations.
public actor TaskTokenHistoryReader {
    private let home: URL
    private var cache: [String: ParsedFile] = [:]

    private struct ParsedFile {
        let size: Int
        let modified: Date
        let id: String?
        let cwd: String?
        let parentID: String?
        let events: [TaskTokenEvent]
        let resets: [UsageSample]
        let warnings: Set<String>
    }

    public init(home: URL? = nil) {
        self.home = home ?? ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    public func load(window: CodexLimitWindow, snapshotAt: Date, samples: [UsageSample] = []) throws -> TaskAllowanceReport {
        guard window.usedPercent.isFinite, (0...100).contains(window.usedPercent),
              window.windowDurationMins == 10080, snapshotAt < window.resetsAt else {
            throw TaskAllowanceError.invalidWindow
        }
        let nominalStart = window.resetsAt.addingTimeInterval(-window.windowDurationMins * 60)
        guard nominalStart < snapshotAt else { throw TaskAllowanceError.invalidWindow }
        let index = try readIndex()
        var warnings = index.warnings
        var paths = Set(index.tasks.values.filter { $0.updated >= nominalStart }.map(\.path).filter { !$0.isEmpty })
        for folder in ["sessions", "archived_sessions"] {
            guard let enumerator = FileManager.default.enumerator(
                at: home.appendingPathComponent(folder), includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles], errorHandler: { _, _ in true }
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                try Task.checkCancellation()
                if let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   date >= nominalStart { paths.insert(url.path) }
            }
        }
        var chosen: [String: ParsedFile] = [:]
        var chosenPaths: [String: String] = [:]
        var unreadable = 0
        // Include owning files even when only an alternate copy was modified recently.
        for path in paths.sorted() {
            try Task.checkCancellation()
            guard let file = try? parse(path), let id = file.id else { unreadable += 1; continue }
            if let canonical = index.tasks[id]?.path, canonical != path,
               FileManager.default.fileExists(atPath: canonical) {
                if chosenPaths[id] == canonical { continue }
                guard let owner = try? parse(canonical), owner.id == id else { unreadable += 1; continue }
                chosen[id] = owner
                chosenPaths[id] = canonical
            } else if let old = chosen[id] {
                let oldIDs = Set(old.events.map(\.identity))
                let newIDs = Set(file.events.map(\.identity))
                if oldIDs.isSubset(of: newIDs) {
                    chosen[id] = file
                    chosenPaths[id] = path
                } else if !newIDs.isSubset(of: oldIDs) {
                    warnings.insert("Conflicting copies of task history were found; only one copy is included.")
                }
            } else {
                chosen[id] = file
                chosenPaths[id] = path
            }
        }
        if unreadable > 0 { warnings.insert("Partial local history: \(unreadable) task files were missing or unreadable.") }
        cache = cache.filter { paths.contains($0.key) || chosenPaths.values.contains($0.key) }
        let resetSamples = samples + chosen.values.flatMap(\.resets)
        let boundary = TaskAllowanceBoundary.resolve(window: window, snapshotAt: snapshotAt, samples: resetSamples)
        if boundary.approximate { warnings.insert("A reset was observed after the advertised start. The start shown is approximate.") }
        var histories: [String: TaskTokenHistory] = [:]
        var excludedBucket = false
        for (id, file) in chosen {
            let metadata = index.tasks[id]
            let events = file.events.filter { event in
                guard event.timestamp >= boundary.start, event.timestamp <= snapshotAt else { return false }
                // Explicit non-Codex/Spark buckets must never be charged to the selected weekly window.
                let separateBucket = event.limitID.map { $0 != window.limitId } ?? false
                let spark = (event.model ?? metadata?.model ?? "").lowercased().contains("spark")
                if separateBucket || spark || (metadata?.provider != nil && metadata?.provider != "openai") {
                    excludedBucket = true
                    return false
                }
                return true
            }
            warnings.formUnion(file.warnings)
            histories[id] = TaskTokenHistory(
                id: id, name: metadata?.name ?? "Untitled task",
                project: project(for: metadata, cwd: file.cwd, index: index),
                parentID: index.parents[id] ?? metadata?.parentID ?? file.parentID, events: events
            )
        }
        // Parents may be older than the window. Keep their metadata without charging lifetime totals.
        for id in Array(histories.keys) {
            var parent = histories[id]?.parentID
            var visited: Set<String> = [id]
            while let parentID = parent, visited.insert(parentID).inserted {
                if histories[parentID] == nil, let task = index.tasks[parentID] {
                    histories[parentID] = TaskTokenHistory(id: parentID, name: task.name,
                        project: project(for: task, cwd: nil, index: index),
                        parentID: index.parents[parentID] ?? task.parentID, events: [])
                }
                if histories[parentID] == nil {
                    warnings.insert("Some child tasks could not be matched to an owning task.")
                }
                parent = histories[parentID]?.parentID
            }
        }
        if excludedBucket { warnings.insert("Separate model buckets and non-OpenAI providers are excluded.") }
        if histories.values.allSatisfy({ $0.events.isEmpty }) && window.usedPercent > 0 {
            warnings.insert("No matching local token events were found for the allowance used.")
        }
        return TaskAllowanceReport(windowStart: boundary.start, snapshotAt: snapshotAt,
            usedPercent: window.usedPercent, histories: Array(histories.values), warnings: warnings.sorted())
    }

    private func parse(_ path: String) throws -> ParsedFile {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let modified = attributes[.modificationDate] as? Date ?? .distantPast
        if let previous = cache[path], previous.size == size, previous.modified == modified { return previous }
        guard let handle = fopen(path, "r") else { throw TaskAllowanceError.unreadableHistory }
        defer { fclose(handle) }
        var line: UnsafeMutablePointer<CChar>?
        var capacity = 0
        defer { free(line) }
        var parser = TaskTokenHistoryParser()
        while getline(&line, &capacity, handle) > 0 {
            try Task.checkCancellation()
            if let line { parser.consume(String(cString: line)) }
        }
        guard ferror(handle) == 0 else { throw TaskAllowanceError.unreadableHistory }
        let result = ParsedFile(size: size, modified: modified, id: parser.id, cwd: parser.cwd,
            parentID: parser.parentID, events: parser.events, resets: parser.resetObservations, warnings: parser.warnings)
        cache[path] = result
        return result
    }

    private struct TaskMetadata {
        let path: String
        let name: String
        let cwd: String
        let projectID: String?
        let parentID: String?
        let updated: Date
        let model: String?
        let provider: String?
    }

    private struct Index {
        var tasks: [String: TaskMetadata] = [:]
        var projects: [String: String] = [:]
        var roots: [(path: String, projectID: String)] = []
        var parents: [String: String] = [:]
        var warnings: Set<String> = []
    }

    private func project(for task: TaskMetadata?, cwd: String?, index: Index) -> String {
        if let id = task?.projectID, let name = index.projects[id] { return name }
        let directory = task?.cwd ?? cwd ?? ""
        if let root = index.roots.first(where: { directory == $0.path || directory.hasPrefix($0.path + "/") }),
           let name = index.projects[root.projectID] { return name }
        return directory.isEmpty ? "No project" : URL(fileURLWithPath: directory).lastPathComponent
    }

    private func readIndex() throws -> Index {
        let files = (try? FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)) ?? []
        let databases = files.compactMap { url -> (Int, URL)? in
            let name = url.deletingPathExtension().lastPathComponent
            guard url.pathExtension == "sqlite", name.hasPrefix("state_"), let version = Int(name.dropFirst(6)) else { return nil }
            return (version, url)
        }.sorted { $0.0 > $1.0 }
        guard let url = databases.first?.1 else { throw TaskAllowanceError.unavailableHistory }
        let db = try TaskHistoryDatabase(url: url)
        let columns = Set(try db.query("PRAGMA table_info(threads)").compactMap { $0["name"] })
        guard ["id", "rollout_path", "updated_at", "cwd", "title"].allSatisfy(columns.contains) else {
            throw TaskAllowanceError.unsupportedHistory
        }
        let optional = ["name", "project_id", "source", "model", "model_provider"].map {
            columns.contains($0) ? $0 : "NULL AS \($0)"
        }.joined(separator: ", ")
        var index = Index()
        for row in try db.query("SELECT id, rollout_path, updated_at, cwd, title, \(optional) FROM threads") {
            guard let id = row["id"] else { continue }
            let name = [row["name"], row["title"]].compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            index.tasks[id] = TaskMetadata(path: row["rollout_path"] ?? "", name: name ?? "Untitled task",
                cwd: row["cwd"] ?? "", projectID: row["project_id"], parentID: TaskTokenHistoryParser.parent(from: row["source"]),
                updated: Date(timeIntervalSince1970: Double(row["updated_at"] ?? "0") ?? 0),
                model: row["model"], provider: row["model_provider"])
        }
        let tables = Set(try db.query("SELECT name FROM sqlite_master WHERE type = 'table'").compactMap { $0["name"] })
        if tables.contains("projects") {
            for row in try db.query("SELECT id, name FROM projects") {
                if let id = row["id"], let name = row["name"] { index.projects[id] = name }
            }
        }
        if tables.contains("project_roots") {
            index.roots = try db.query("SELECT project_id, path FROM project_roots").compactMap {
                guard let path = $0["path"], let id = $0["project_id"] else { return nil }
                return (path, id)
            }.sorted { $0.path.count > $1.path.count }
        }
        if tables.contains("thread_spawn_edges") {
            for row in try db.query("SELECT parent_thread_id, child_thread_id FROM thread_spawn_edges") {
                if let child = row["child_thread_id"], let parent = row["parent_thread_id"] { index.parents[child] = parent }
            }
        }
        return index
    }
}

private final class TaskHistoryDatabase {
    private var handle: OpaquePointer?

    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let handle { sqlite3_close(handle) }
            handle = nil
            throw TaskAllowanceError.unreadableHistory
        }
        sqlite3_busy_timeout(handle, 1500)
        try execute("BEGIN")
    }

    deinit { sqlite3_close(handle) }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw TaskAllowanceError.unreadableHistory }
    }

    func query(_ sql: String) throws -> [[String: String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw TaskAllowanceError.unsupportedHistory }
        defer { sqlite3_finalize(statement) }
        var rows: [[String: String]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return rows }
            guard result == SQLITE_ROW else { throw TaskAllowanceError.unreadableHistory }
            var row: [String: String] = [:]
            for column in 0..<sqlite3_column_count(statement) {
                if let name = sqlite3_column_name(statement, column), let value = sqlite3_column_text(statement, column) {
                    row[String(cString: name)] = String(cString: value)
                }
            }
            rows.append(row)
        }
    }
}

public enum TaskAllowanceBoundary {
    /// Use the advertised weekly boundary, unless a later observed reset contradicts it.
    public static func resolve(window: CodexLimitWindow, snapshotAt: Date, samples: [UsageSample]) -> (start: Date, approximate: Bool) {
        var start = window.resetsAt.addingTimeInterval(-window.windowDurationMins * 60)
        var approximate = false
        let ordered = samples.filter { $0.limitId == window.limitId && $0.timestamp <= snapshotAt }
            .sorted { $0.timestamp < $1.timestamp }
        for (previous, sample) in zip(ordered, ordered.dropFirst()) {
            if sample.timestamp > start, previous.timestamp >= start,
               sample.resetAt.timeIntervalSince(previous.resetAt) >= UsageHistorySeries.minimumScheduledResetAdvance,
               sample.usedPercent < previous.usedPercent,
               abs(sample.resetAt.timeIntervalSince(window.resetsAt)) < 60 {
                start = sample.timestamp
                approximate = true
            }
        }
        return (start, approximate)
    }
}
