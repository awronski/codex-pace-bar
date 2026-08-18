import CodexActivityInsightsContract
import Darwin
import Foundation
import OSLog

public actor ActivityInsightsChartSnapshotWriter {
    public let fileURL: URL

    private let fileManager: FileManager
    private let lockURL: URL
    private static let log = Logger(
        subsystem: "app.codexpacebar.activity-insights",
        category: "chart-snapshot"
    )

    public init(
        fileURL: URL = ActivityInsightsChartSnapshotLocation.defaultFileURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.lockURL = fileURL.deletingPathExtension().appendingPathExtension("lock")
    }

    @discardableResult
    public func publish(
        archive: ActivityInsightsArchive,
        configuration: ActivityInsightsConfiguration,
        now: Date = Date()
    ) throws -> ActivityInsightsChartSnapshot {
        let snapshot = ActivityInsightsChartSnapshotBuilder.build(
            archive: archive,
            configuration: configuration,
            now: now
        )
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
            guard descriptor >= 0, flock(descriptor, LOCK_EX) == 0 else {
                if descriptor >= 0 { Darwin.close(descriptor) }
                throw ActivityInsightsError.persistence("Chart snapshot could not be locked.")
            }
            defer {
                flock(descriptor, LOCK_UN)
                Darwin.close(descriptor)
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let existingData = try? Data(contentsOf: fileURL),
               let existing = try? decoder.decode(ActivityInsightsChartSnapshot.self, from: existingData),
               existing.schemaVersion == ActivityInsightsChartSnapshot.currentSchemaVersion,
               (existing.sourceUpdatedAt > snapshot.sourceUpdatedAt
                    || (existing.sourceUpdatedAt == snapshot.sourceUpdatedAt
                        && existing.generatedAt > snapshot.generatedAt)) {
                return existing
            }
            try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
            Self.log.info(
                "snapshot_written schema=\(snapshot.schemaVersion, privacy: .public) coverage=\(snapshot.quality.fourStateCoveragePercent, privacy: .public)"
            )
            return snapshot
        } catch {
            Self.log.error("snapshot_write_failed code=persistence")
            throw ActivityInsightsError.persistence("Chart snapshot could not be saved.")
        }
    }
}
