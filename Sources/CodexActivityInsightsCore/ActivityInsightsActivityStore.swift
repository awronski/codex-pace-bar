import Foundation
import SQLite3

struct ActivityInsightsActivitySnapshot {
    var activityMinutes: [String: ActivityMinuteFact] = [:]
    var observationFacts: [String: ActivityObservationFact] = [:]
    var collectorCoverageMinutes: [String: ActivityCollectorCoverageMinuteFact] = [:]
    var collectorState: ActivityCollectorState?
    var collectorSessionCount = 0
    var generatedAt = Date(timeIntervalSince1970: 0)
}

/// Transactional storage for the collector's high-frequency facts. Each operation opens a
/// short-lived SQLite connection so independent collector and audit processes coordinate via
/// SQLite's WAL and busy-timeout handling rather than process-local actors.
struct ActivityInsightsActivityStore {
    private static let migratedKey = "legacy_activity_imported"
    private static let generatedAtKey = "generated_at"
    private static let sessionCountKey = "collector_session_count"

    let fileURL: URL
    let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() throws -> ActivityInsightsActivitySnapshot {
        let database = try openDatabase()
        var snapshot = ActivityInsightsActivitySnapshot()

        try database.query("SELECT payload FROM activity_minutes") { statement in
            let fact = try Self.decode(ActivityMinuteFact.self, from: statement, column: 0)
            snapshot.activityMinutes[fact.key] = fact
        }
        try database.query("SELECT payload FROM observations") { statement in
            let fact = try Self.decode(ActivityObservationFact.self, from: statement, column: 0)
            snapshot.observationFacts[fact.key] = fact
        }
        try database.query("SELECT payload FROM collector_coverage_minutes") { statement in
            let fact = try Self.decode(ActivityCollectorCoverageMinuteFact.self, from: statement, column: 0)
            snapshot.collectorCoverageMinutes[fact.key] = fact
        }
        try database.query("SELECT payload FROM collector_state WHERE id = 1") { statement in
            snapshot.collectorState = try Self.decode(ActivityCollectorState.self, from: statement, column: 0)
        }
        snapshot.collectorSessionCount = Int(try database.metadataDouble(for: Self.sessionCountKey) ?? 0)
        snapshot.generatedAt = Date(
            timeIntervalSince1970: try database.metadataDouble(for: Self.generatedAtKey) ?? 0
        )
        return snapshot
    }

    func importLegacyIfNeeded(from archive: ActivityInsightsArchive, now: Date) throws -> Bool {
        let database = try openDatabase()
        return try database.transaction {
            guard try database.metadataDouble(for: Self.migratedKey) == nil else { return false }

            for fact in archive.activityMinutes.values {
                try database.upsert(payload: fact, key: fact.key, timestamp: fact.minuteStart, table: "activity_minutes")
            }
            for fact in archive.observationFacts.values {
                try database.upsert(payload: fact, key: fact.key, timestamp: fact.intervalEnd, table: "observations")
            }
            for fact in archive.collectorCoverageMinutes.values {
                try database.upsert(
                    payload: fact,
                    key: fact.key,
                    timestamp: fact.minuteStart,
                    table: "collector_coverage_minutes"
                )
            }
            if let state = archive.collectorState {
                try database.setCollectorState(state)
            }
            let existingCount = try database.metadataDouble(for: Self.sessionCountKey) ?? 0
            try database.setMetadata(max(existingCount, Double(archive.collectorSessionCount)), for: Self.sessionCountKey)
            let existingGeneratedAt = try database.metadataDouble(for: Self.generatedAtKey) ?? 0
            try database.setMetadata(
                max(existingGeneratedAt, max(archive.generatedAt, now).timeIntervalSince1970),
                for: Self.generatedAtKey
            )
            try database.setMetadata(1, for: Self.migratedKey)
            return true
        }
    }

    func record(
        observation: ActivityObservation,
        heartbeatFor collectorSessionID: UUID?,
        now: Date,
        retentionDuration: TimeInterval
    ) throws {
        let database = try openDatabase()
        try database.transaction {
            if let fact = observation.fact {
                try database.upsert(payload: fact, key: fact.key, timestamp: fact.intervalEnd, table: "observations")
            }
            for incoming in observation.minuteFacts {
                let existing: ActivityMinuteFact? = try database.fact(
                    ActivityMinuteFact.self,
                    key: incoming.key,
                    table: "activity_minutes"
                )
                let fact = existing.map { Self.merge(existing: $0, incoming: incoming) } ?? incoming
                try database.upsert(payload: fact, key: fact.key, timestamp: fact.minuteStart, table: "activity_minutes")
            }
            if let collectorSessionID {
                try recordHeartbeat(sessionID: collectorSessionID, at: now, database: database)
            }
            try retainRecentFacts(database: database, now: now, retentionDuration: retentionDuration)
            try database.setMetadata(now.timeIntervalSince1970, for: Self.generatedAtKey)
        }
    }

    func startCollectorSession(
        expectedHeartbeatIntervalSeconds: TimeInterval,
        enabledSince: Date?,
        now: Date,
        retentionDuration: TimeInterval
    ) throws -> UUID {
        guard expectedHeartbeatIntervalSeconds >= 1 else {
            throw ActivityInsightsError.persistence("Collector heartbeat interval must be positive.")
        }
        let database = try openDatabase()
        return try database.transaction {
            if let previous = try database.collectorState() {
                if previous.isRunning {
                    try recordCollectorInterval(
                        from: previous.lastHeartbeatAt,
                        to: now,
                        expectedInterval: previous.expectedHeartbeatIntervalSeconds,
                        database: database
                    )
                } else if let enabledSince {
                    let gapStart = max(previous.stoppedAt ?? previous.lastHeartbeatAt, enabledSince)
                    try addCollectorCoverage(from: gapStart, to: now, running: false, database: database)
                }
            } else if let enabledSince,
                      now.timeIntervalSince(enabledSince) > expectedHeartbeatIntervalSeconds * 3 {
                try addCollectorCoverage(from: enabledSince, to: now, running: false, database: database)
            }

            let state = ActivityCollectorState(
                startedAt: now,
                lastHeartbeatAt: now,
                expectedHeartbeatIntervalSeconds: expectedHeartbeatIntervalSeconds
            )
            try database.setCollectorState(state)
            let count = Int(try database.metadataDouble(for: Self.sessionCountKey) ?? 0) + 1
            try database.setMetadata(Double(count), for: Self.sessionCountKey)
            try retainRecentFacts(database: database, now: now, retentionDuration: retentionDuration)
            try database.setMetadata(now.timeIntervalSince1970, for: Self.generatedAtKey)
            return state.sessionID
        }
    }

    func stopCollectorSession(
        sessionID: UUID,
        reason: ActivityCollectorStopReason,
        now: Date,
        retentionDuration: TimeInterval
    ) throws {
        let database = try openDatabase()
        try database.transaction {
            guard var state = try database.collectorState(),
                  state.sessionID == sessionID,
                  state.isRunning
            else {
                throw ActivityInsightsError.persistence("Collector session is not active.")
            }
            try recordCollectorInterval(
                from: state.lastHeartbeatAt,
                to: now,
                expectedInterval: state.expectedHeartbeatIntervalSeconds,
                database: database
            )
            state.lastHeartbeatAt = now
            state.stoppedAt = now
            state.stopReason = reason
            try database.setCollectorState(state)
            try retainRecentFacts(database: database, now: now, retentionDuration: retentionDuration)
            try database.setMetadata(now.timeIntervalSince1970, for: Self.generatedAtKey)
        }
    }

    func retainRecentFacts(now: Date, retentionDuration: TimeInterval) throws {
        let database = try openDatabase()
        try database.transaction {
            try retainRecentFacts(database: database, now: now, retentionDuration: retentionDuration)
        }
    }

    private func recordHeartbeat(sessionID: UUID, at date: Date, database: SQLiteDatabase) throws {
        guard var state = try database.collectorState(),
              state.sessionID == sessionID,
              state.isRunning
        else {
            throw ActivityInsightsError.persistence("Collector heartbeat does not match the active session.")
        }
        try recordCollectorInterval(
            from: state.lastHeartbeatAt,
            to: date,
            expectedInterval: state.expectedHeartbeatIntervalSeconds,
            database: database
        )
        state.lastHeartbeatAt = date
        try database.setCollectorState(state)
    }

    private func recordCollectorInterval(
        from start: Date,
        to end: Date,
        expectedInterval: TimeInterval,
        database: SQLiteDatabase
    ) throws {
        let elapsed = end.timeIntervalSince(start)
        guard elapsed >= 0 else {
            throw ActivityInsightsError.persistence("Collector heartbeat moved backwards in time.")
        }
        guard elapsed > 0 else { return }

        if elapsed <= expectedInterval * 3 {
            try addCollectorCoverage(from: start, to: end, running: true, database: database)
        } else {
            let observedStart = end.addingTimeInterval(-expectedInterval)
            try addCollectorCoverage(from: start, to: observedStart, running: false, database: database)
            try addCollectorCoverage(from: observedStart, to: end, running: true, database: database)
        }
    }

    private func addCollectorCoverage(
        from start: Date,
        to end: Date,
        running: Bool,
        database: SQLiteDatabase
    ) throws {
        guard end > start else { return }
        var cursor = start
        while cursor < end {
            let minuteStart = Date(timeIntervalSince1970: floor(cursor.timeIntervalSince1970 / 60) * 60)
            let segmentEnd = min(minuteStart.addingTimeInterval(60), end)
            let seconds = segmentEnd.timeIntervalSince(cursor)
            var incoming = ActivityCollectorCoverageMinuteFact(minuteStart: minuteStart)
            if running { incoming.runningSeconds = seconds } else { incoming.unknownSeconds = seconds }
            let existing: ActivityCollectorCoverageMinuteFact? = try database.fact(
                ActivityCollectorCoverageMinuteFact.self,
                key: incoming.key,
                table: "collector_coverage_minutes"
            )
            let fact = existing.map { Self.merge(existing: $0, incoming: incoming) } ?? incoming
            try database.upsert(
                payload: fact,
                key: fact.key,
                timestamp: fact.minuteStart,
                table: "collector_coverage_minutes"
            )
            cursor = segmentEnd
        }
    }

    private func retainRecentFacts(
        database: SQLiteDatabase,
        now: Date,
        retentionDuration: TimeInterval
    ) throws {
        let cutoff = now.addingTimeInterval(-retentionDuration).timeIntervalSince1970
        try database.deleteBefore(cutoff, table: "activity_minutes")
        try database.deleteBefore(cutoff, table: "observations")
        try database.deleteBefore(cutoff, table: "collector_coverage_minutes")
        if let state = try database.collectorState(),
           let stoppedAt = state.stoppedAt,
           stoppedAt.timeIntervalSince1970 < cutoff {
            try database.clearCollectorState()
        }
    }

    private func openDatabase() throws -> SQLiteDatabase {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try SQLiteDatabase(fileURL: fileURL)
    }

    private static func merge(existing: ActivityMinuteFact, incoming: ActivityMinuteFact) -> ActivityMinuteFact {
        let existingTotal = existing.observedSeconds + existing.unavailableSeconds
        let incomingTotal = incoming.observedSeconds + incoming.unavailableSeconds
        let acceptedTotal = min(max(0, 60 - existingTotal), incomingTotal)
        guard acceptedTotal > 0, incomingTotal > 0 else { return existing }
        let fraction = acceptedTotal / incomingTotal
        return ActivityMinuteFact(
            minuteStart: existing.minuteStart,
            observedSeconds: existing.observedSeconds + incoming.observedSeconds * fraction,
            activeWithinTwoMinutesSeconds: existing.activeWithinTwoMinutesSeconds
                + incoming.activeWithinTwoMinutesSeconds * fraction,
            activeWithinFiveMinutesSeconds: existing.activeWithinFiveMinutesSeconds
                + incoming.activeWithinFiveMinutesSeconds * fraction,
            activeWithinTenMinutesSeconds: existing.activeWithinTenMinutesSeconds
                + incoming.activeWithinTenMinutesSeconds * fraction,
            unavailableSeconds: existing.unavailableSeconds + incoming.unavailableSeconds * fraction
        )
    }

    private static func merge(
        existing: ActivityCollectorCoverageMinuteFact,
        incoming: ActivityCollectorCoverageMinuteFact
    ) -> ActivityCollectorCoverageMinuteFact {
        let existingTotal = existing.runningSeconds + existing.unknownSeconds
        let incomingTotal = incoming.runningSeconds + incoming.unknownSeconds
        let acceptedTotal = min(max(0, 60 - existingTotal), incomingTotal)
        guard acceptedTotal > 0, incomingTotal > 0 else { return existing }
        let fraction = acceptedTotal / incomingTotal
        return ActivityCollectorCoverageMinuteFact(
            minuteStart: existing.minuteStart,
            runningSeconds: existing.runningSeconds + incoming.runningSeconds * fraction,
            unknownSeconds: existing.unknownSeconds + incoming.unknownSeconds * fraction
        )
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        from statement: OpaquePointer,
        column: Int32
    ) throws -> T {
        guard let bytes = sqlite3_column_blob(statement, column) else {
            throw ActivityInsightsError.persistence("SQLite row contains no payload.")
        }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
        return try decoder.decode(type, from: data)
    }

    fileprivate static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()

    fileprivate static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}

private final class SQLiteDatabase {
    private var handle: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(fileURL: URL) throws {
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(fileURL.path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open SQLite database."
            if let handle { sqlite3_close(handle) }
            throw ActivityInsightsError.persistence(message)
        }
        sqlite3_busy_timeout(handle, 5_000)
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=NORMAL")
        try execute("CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value REAL NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS activity_minutes (key TEXT PRIMARY KEY, timestamp REAL NOT NULL, payload BLOB NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS observations (key TEXT PRIMARY KEY, timestamp REAL NOT NULL, payload BLOB NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS collector_coverage_minutes (key TEXT PRIMARY KEY, timestamp REAL NOT NULL, payload BLOB NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS collector_state (id INTEGER PRIMARY KEY CHECK (id = 1), payload BLOB NOT NULL)")
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? errorDescription
            sqlite3_free(errorMessage)
            throw ActivityInsightsError.persistence(message)
        }
    }

    func query(_ sql: String, row: (OpaquePointer) throws -> Void) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: try row(statement)
            case SQLITE_DONE: return
            default: throw ActivityInsightsError.persistence(errorDescription)
            }
        }
    }

    func fact<T: Decodable>(_ type: T.Type, key: String, table: String) throws -> T? {
        let statement = try prepare("SELECT payload FROM \(table) WHERE key = ?")
        defer { sqlite3_finalize(statement) }
        try bind(key, to: statement, index: 1)
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            guard let bytes = sqlite3_column_blob(statement, 0) else { return nil }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            return try ActivityInsightsActivityStore.decoder.decode(type, from: data)
        case SQLITE_DONE: return nil
        default: throw ActivityInsightsError.persistence(errorDescription)
        }
    }

    func upsert<T: Encodable>(payload: T, key: String, timestamp: Date, table: String) throws {
        let data = try ActivityInsightsActivityStore.encoder.encode(payload)
        let statement = try prepare(
            "INSERT INTO \(table) (key, timestamp, payload) VALUES (?, ?, ?) "
                + "ON CONFLICT(key) DO UPDATE SET timestamp = excluded.timestamp, payload = excluded.payload"
        )
        defer { sqlite3_finalize(statement) }
        try bind(key, to: statement, index: 1)
        sqlite3_bind_double(statement, 2, timestamp.timeIntervalSince1970)
        let bindResult = data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, 3, bytes.baseAddress, Int32(data.count), Self.transient)
        }
        guard bindResult == SQLITE_OK else {
            throw ActivityInsightsError.persistence(errorDescription)
        }
        try stepDone(statement)
    }

    func deleteBefore(_ timestamp: TimeInterval, table: String) throws {
        let statement = try prepare("DELETE FROM \(table) WHERE timestamp < ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, timestamp)
        try stepDone(statement)
    }

    func metadataDouble(for key: String) throws -> Double? {
        let statement = try prepare("SELECT value FROM metadata WHERE key = ?")
        defer { sqlite3_finalize(statement) }
        try bind(key, to: statement, index: 1)
        switch sqlite3_step(statement) {
        case SQLITE_ROW: return sqlite3_column_double(statement, 0)
        case SQLITE_DONE: return nil
        default: throw ActivityInsightsError.persistence(errorDescription)
        }
    }

    func setMetadata(_ value: Double, for key: String) throws {
        let statement = try prepare(
            "INSERT INTO metadata (key, value) VALUES (?, ?) "
                + "ON CONFLICT(key) DO UPDATE SET value = excluded.value"
        )
        defer { sqlite3_finalize(statement) }
        try bind(key, to: statement, index: 1)
        sqlite3_bind_double(statement, 2, value)
        try stepDone(statement)
    }

    func collectorState() throws -> ActivityCollectorState? {
        var state: ActivityCollectorState?
        try query("SELECT payload FROM collector_state WHERE id = 1") { statement in
            guard let bytes = sqlite3_column_blob(statement, 0) else { return }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            state = try ActivityInsightsActivityStore.decoder.decode(ActivityCollectorState.self, from: data)
        }
        return state
    }

    func setCollectorState(_ state: ActivityCollectorState) throws {
        let data = try ActivityInsightsActivityStore.encoder.encode(state)
        let statement = try prepare(
            "INSERT INTO collector_state (id, payload) VALUES (1, ?) "
                + "ON CONFLICT(id) DO UPDATE SET payload = excluded.payload"
        )
        defer { sqlite3_finalize(statement) }
        let bindResult = data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, 1, bytes.baseAddress, Int32(data.count), Self.transient)
        }
        guard bindResult == SQLITE_OK else {
            throw ActivityInsightsError.persistence(errorDescription)
        }
        try stepDone(statement)
    }

    func clearCollectorState() throws {
        try execute("DELETE FROM collector_state WHERE id = 1")
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw ActivityInsightsError.persistence(errorDescription)
        }
        return statement
    }

    private func bind(_ value: String, to statement: OpaquePointer, index: Int32) throws {
        guard sqlite3_bind_text(statement, index, value, -1, Self.transient) == SQLITE_OK else {
            throw ActivityInsightsError.persistence(errorDescription)
        }
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ActivityInsightsError.persistence(errorDescription)
        }
    }

    private var errorDescription: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error."
    }
}
