import Foundation

public struct UsageHistoryRepository {
    public static let retentionDuration: TimeInterval = 30 * 24 * 60 * 60
    public static let currentSchemaVersion = 1

    private let fileURL: URL
    private let backupURL: URL
    private let corruptURL: URL
    private let appVersion: String
    private let retainedDuration: TimeInterval
    private let fileManager: FileManager
    private let writeData: (Data, URL) throws -> Void

    public init(
        fileURL: URL,
        backupURL: URL? = nil,
        appVersion: String = "development",
        retainedDuration: TimeInterval = Self.retentionDuration,
        fileManager: FileManager = .default
    ) {
        self.init(
            fileURL: fileURL,
            backupURL: backupURL ?? Self.defaultBackupURL(for: fileURL),
            appVersion: appVersion,
            retainedDuration: retainedDuration,
            fileManager: fileManager,
            writeData: { data, url in
                try data.write(to: url, options: .atomic)
            }
        )
    }

    init(
        fileURL: URL,
        backupURL: URL,
        appVersion: String = "development",
        retainedDuration: TimeInterval = Self.retentionDuration,
        fileManager: FileManager = .default,
        writeData: @escaping (Data, URL) throws -> Void
    ) {
        self.fileURL = fileURL
        self.backupURL = backupURL
        self.corruptURL = Self.defaultCorruptURL(for: fileURL)
        self.appVersion = appVersion
        self.retainedDuration = retainedDuration
        self.fileManager = fileManager
        self.writeData = writeData
    }

    public func load() -> [UsageSample] {
        if let samples = decodedSamples(at: fileURL) {
            return samples.sorted { $0.timestamp < $1.timestamp }
        }
        if let samples = decodedSamples(at: backupURL) {
            return samples.sorted { $0.timestamp < $1.timestamp }
        }
        return []
    }

    public func appending(_ sample: UsageSample, to samples: [UsageSample]) throws -> [UsageSample] {
        let newestTimestamp = max(sample.timestamp, samples.map(\.timestamp).max() ?? sample.timestamp)
        let retentionCutoff = newestTimestamp.addingTimeInterval(-retainedDuration)
        let retainedSamples = samples.filter { $0.timestamp >= retentionCutoff }
        let candidate = (retainedSamples + [sample]).sorted { $0.timestamp < $1.timestamp }

        guard candidate.count == retainedSamples.count + 1 else {
            throw UsageHistoryRepositoryError.unexpectedSampleLoss
        }

        let candidateFile = UsageHistoryFile(
            schemaVersion: Self.currentSchemaVersion,
            appVersion: appVersion,
            samples: candidate
        )
        let candidateData = try JSONEncoder().encode(candidateFile)
        guard let validatedCandidate = try? JSONDecoder().decode(UsageHistoryFile.self, from: candidateData),
              validatedCandidate == candidateFile
        else {
            throw UsageHistoryRepositoryError.validationFailed
        }

        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        if let currentData = try? Data(contentsOf: fileURL) {
            if Self.decodedSamples(from: currentData) != nil {
                try writeData(currentData, backupURL)
            } else {
                try? writeData(currentData, corruptURL)
            }
        }

        try writeData(candidateData, fileURL)
        return candidate
    }

    private func decodedSamples(at url: URL) -> [UsageSample]? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return Self.decodedSamples(from: data)
    }

    private static func decodedSamples(from data: Data) -> [UsageSample]? {
        if let history = try? JSONDecoder().decode(UsageHistoryFile.self, from: data),
           history.schemaVersion == currentSchemaVersion {
            return history.samples
        }
        return try? JSONDecoder().decode([UsageSample].self, from: data)
    }

    private static func defaultBackupURL(for fileURL: URL) -> URL {
        fileURL.deletingLastPathComponent()
            .appendingPathComponent("usage-history.backup.json")
    }

    private static func defaultCorruptURL(for fileURL: URL) -> URL {
        fileURL.deletingLastPathComponent()
            .appendingPathComponent("usage-history.corrupt.json")
    }
}

private struct UsageHistoryFile: Codable, Equatable {
    let schemaVersion: Int
    let appVersion: String
    let samples: [UsageSample]
}

public enum UsageHistoryRepositoryError: LocalizedError, Equatable {
    case unexpectedSampleLoss
    case validationFailed

    public var errorDescription: String? {
        switch self {
        case .unexpectedSampleLoss:
            return "Usage history update would have lost an existing sample."
        case .validationFailed:
            return "Usage history validation failed before writing the file."
        }
    }
}
