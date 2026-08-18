import Foundation
import Darwin

public actor ActivityInsightsRepository {
    public static let retentionDuration: TimeInterval = 30 * 24 * 60 * 60
    public static let maximumRunHistory = 100

    public let fileURL: URL
    private let backupURL: URL
    private let lockURL: URL
    private let activityStore: ActivityInsightsActivityStore
    private let fileManager: FileManager

    public init(fileURL: URL = ActivityInsightsRepository.defaultFileURL(), fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.backupURL = fileURL.deletingPathExtension().appendingPathExtension("backup.json")
        self.lockURL = fileURL.deletingPathExtension().appendingPathExtension("lock")
        self.activityStore = ActivityInsightsActivityStore(
            fileURL: fileURL.deletingPathExtension().appendingPathExtension("sqlite3"),
            fileManager: fileManager
        )
        self.fileManager = fileManager
    }

    public static func defaultDirectoryURL(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return applicationSupport
            .appendingPathComponent("CodexPaceBar", isDirectory: true)
            .appendingPathComponent("ActivityInsights", isDirectory: true)
    }

    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        defaultDirectoryURL(fileManager: fileManager).appendingPathComponent("activity-insights.json")
    }

    public func load() throws -> ActivityInsightsArchive {
        try withArchiveLock {
            var archive = try loadCore()
            _ = try activityStore.importLegacyIfNeeded(from: archive, now: archive.generatedAt)
            if archiveContainsLegacyActivity(archive) {
                stripActivity(from: &archive)
                try saveCore(archive)
            }
            try overlayActivity(on: &archive)
            return archive
        }
    }

    @discardableResult
    public func apply(
        _ batch: ActivityCollectionBatch,
        now: Date = Date()
    ) throws -> ActivityInsightsArchive {
        try withArchiveLock {
            var archive = try loadCore()
            let isNewRun = !archive.collectionRuns.contains(where: { $0.runID == batch.run.runID })
            _ = try activityStore.importLegacyIfNeeded(from: archive, now: now)
            if archiveContainsLegacyActivity(archive) { stripActivity(from: &archive) }

            for threadID in batch.refreshedThreadIDs {
                archive.turns = archive.turns.filter { $0.value.threadID != threadID }
                archive.inputs = archive.inputs.filter { $0.value.threadID != threadID }
            }
            for thread in batch.threads { archive.threads[thread.threadID] = thread }
            for turn in batch.turns { archive.turns[turn.key] = turn }
            for input in batch.inputs { archive.inputs[input.key] = input }
            let currentActors = Dictionary(uniqueKeysWithValues: batch.threads.map {
                ($0.threadID, $0.actor)
            })
            archive.inputs = archive.inputs.mapValues { input in
                guard let actor = currentActors[input.threadID], actor != input.actor else { return input }
                return input.reclassified(as: actor)
            }
            let threadVersions = Dictionary(uniqueKeysWithValues: batch.threads.map {
                ($0.threadID, $0.sourceUpdatedAt)
            })
            for threadID in batch.attemptedThreadIDs {
                if let version = threadVersions[threadID] {
                    archive.historyAttemptVersions[threadID] = version
                }
            }
            for threadID in batch.refreshedThreadIDs {
                if let version = threadVersions[threadID] {
                    archive.historySyncVersions[threadID] = version
                    archive.historyFailureVersions.removeValue(forKey: threadID)
                    archive.historyFailureAttemptCounts.removeValue(forKey: threadID)
                }
            }
            for threadID in batch.attemptedThreadIDs.subtracting(batch.refreshedThreadIDs) {
                if let version = threadVersions[threadID] {
                    archive.historyFailureVersions[threadID] = version
                    if isNewRun {
                        archive.historyFailureAttemptCounts[threadID, default: 0] += 1
                    }
                }
            }
            if isNewRun {
                archive.collectionRuns.append(batch.run)
            }
            if archive.collectionRuns.count > Self.maximumRunHistory {
                archive.collectionRuns.removeFirst(archive.collectionRuns.count - Self.maximumRunHistory)
            }

            retainRecentHistory(in: &archive, now: now)
            try activityStore.retainRecentFacts(now: now, retentionDuration: Self.retentionDuration)
            archive.generatedAt = now
            stripActivity(from: &archive)
            try saveCore(archive)
            try overlayActivity(on: &archive)
            return archive
        }
    }

    public func record(
        observation: ActivityObservation,
        heartbeatFor collectorSessionID: UUID? = nil,
        now: Date = Date()
    ) throws {
        try activityStore.record(
            observation: observation,
            heartbeatFor: collectorSessionID,
            now: now,
            retentionDuration: Self.retentionDuration
        )
    }

    public func startCollectorSession(
        expectedHeartbeatIntervalSeconds: TimeInterval,
        enabledSince: Date?,
        now: Date = Date()
    ) throws -> UUID {
        try activityStore.startCollectorSession(
            expectedHeartbeatIntervalSeconds: expectedHeartbeatIntervalSeconds,
            enabledSince: enabledSince,
            now: now,
            retentionDuration: Self.retentionDuration
        )
    }

    @discardableResult
    public func stopCollectorSession(
        sessionID: UUID,
        reason: ActivityCollectorStopReason,
        now: Date = Date()
    ) throws -> ActivityInsightsArchive {
        try activityStore.stopCollectorSession(
            sessionID: sessionID,
            reason: reason,
            now: now,
            retentionDuration: Self.retentionDuration
        )
        return try load()
    }

    private func retainRecentHistory(in archive: inout ActivityInsightsArchive, now: Date) {
        let cutoff = now.addingTimeInterval(-Self.retentionDuration)
        archive.threads = archive.threads.filter { $0.value.sourceRecencyAt >= cutoff }
        let retainedThreadIDs = Set(archive.threads.keys)
        archive.historyAttemptVersions = archive.historyAttemptVersions.filter {
            retainedThreadIDs.contains($0.key)
        }
        archive.historySyncVersions = archive.historySyncVersions.filter {
            retainedThreadIDs.contains($0.key)
        }
        archive.historyFailureVersions = archive.historyFailureVersions.filter {
            retainedThreadIDs.contains($0.key)
        }
        archive.historyFailureAttemptCounts = archive.historyFailureAttemptCounts.filter {
            retainedThreadIDs.contains($0.key)
        }
        archive.turns = archive.turns.filter {
            retainedThreadIDs.contains($0.value.threadID)
                && ($0.value.startedAt ?? .distantPast) >= cutoff
        }
        let retainedTurnKeys = Set(archive.turns.keys)
        archive.inputs = archive.inputs.filter {
            retainedTurnKeys.contains(ActivityTurnFact.key(
                threadID: $0.value.threadID,
                turnID: $0.value.turnID
            ))
        }
    }

    private func decode(at url: URL) throws -> ActivityInsightsArchive {
        let data = try Data(contentsOf: url)
        let archive = try Self.decoder.decode(ActivityInsightsArchive.self, from: data)
        guard archive.schemaVersion == ActivityInsightsArchive.currentSchemaVersion else {
            throw ActivityInsightsError.unsupportedSchema(archive.schemaVersion)
        }
        return archive
    }

    private func loadCore() throws -> ActivityInsightsArchive {
        if !fileManager.fileExists(atPath: fileURL.path),
           !fileManager.fileExists(atPath: backupURL.path) {
            return .init()
        }
        if let archive = try? decode(at: fileURL) { return archive }
        if let archive = try? decode(at: backupURL) { return archive }
        throw ActivityInsightsError.persistence("Both the primary archive and backup are unreadable.")
    }

    private func overlayActivity(on archive: inout ActivityInsightsArchive) throws {
        let activity = try activityStore.load()
        archive.activityMinutes = activity.activityMinutes
        archive.observationFacts = activity.observationFacts
        archive.collectorCoverageMinutes = activity.collectorCoverageMinutes
        archive.collectorState = activity.collectorState
        archive.collectorSessionCount = activity.collectorSessionCount
        archive.generatedAt = max(archive.generatedAt, activity.generatedAt)
    }

    private func archiveContainsLegacyActivity(_ archive: ActivityInsightsArchive) -> Bool {
        !archive.activityMinutes.isEmpty
            || !archive.observationFacts.isEmpty
            || !archive.collectorCoverageMinutes.isEmpty
            || archive.collectorState != nil
            || archive.collectorSessionCount > 0
    }

    private func stripActivity(from archive: inout ActivityInsightsArchive) {
        archive.activityMinutes = [:]
        archive.observationFacts = [:]
        archive.collectorCoverageMinutes = [:]
        archive.collectorState = nil
        archive.collectorSessionCount = 0
    }

    private func withArchiveLock<T>(_ body: () throws -> T) throws -> T {
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else {
                throw ActivityInsightsError.persistence("Unable to open the activity-insights archive lock.")
            }
            defer {
                flock(descriptor, LOCK_UN)
                Darwin.close(descriptor)
            }
            guard flock(descriptor, LOCK_EX) == 0 else {
                throw ActivityInsightsError.persistence("Unable to lock the activity-insights archive.")
            }
            return try body()
        } catch let error as ActivityInsightsError {
            throw error
        } catch {
            throw ActivityInsightsError.persistence(error.localizedDescription)
        }
    }

    private func saveCore(_ archive: ActivityInsightsArchive) throws {
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoded = try Self.encoder.encode(archive)
            let validated = try Self.decoder.decode(ActivityInsightsArchive.self, from: encoded)
            guard validated.schemaVersion == ActivityInsightsArchive.currentSchemaVersion else {
                throw ActivityInsightsError.unsupportedSchema(validated.schemaVersion)
            }
            if let existing = try? Data(contentsOf: fileURL),
               (try? Self.decoder.decode(ActivityInsightsArchive.self, from: existing)) != nil {
                try existing.write(to: backupURL, options: .atomic)
            }
            try encoded.write(to: fileURL, options: .atomic)
        } catch let error as ActivityInsightsError {
            throw error
        } catch {
            throw ActivityInsightsError.persistence(error.localizedDescription)
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}
