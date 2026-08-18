import Foundation

public struct ActivityInsightsConfiguration: Codable, Equatable, Sendable {
    public var shadowEnabled: Bool
    public var shadowEnabledSince: Date?
    public var historyIntervalSeconds: TimeInterval
    public var sampleIntervalSeconds: TimeInterval
    public var lookbackDays: Int

    public init(
        shadowEnabled: Bool = false,
        shadowEnabledSince: Date? = nil,
        historyIntervalSeconds: TimeInterval = 5 * 60,
        sampleIntervalSeconds: TimeInterval = 15,
        lookbackDays: Int = 30
    ) {
        self.shadowEnabled = shadowEnabled
        self.shadowEnabledSince = shadowEnabledSince
        self.historyIntervalSeconds = historyIntervalSeconds
        self.sampleIntervalSeconds = sampleIntervalSeconds
        self.lookbackDays = lookbackDays
    }
}

public actor ActivityInsightsConfigurationStore {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(
        fileURL: URL = ActivityInsightsRepository.defaultDirectoryURL()
            .appendingPathComponent("configuration.json"),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func load() throws -> ActivityInsightsConfiguration {
        guard fileManager.fileExists(atPath: fileURL.path) else { return .init() }
        do {
            return try JSONDecoder().decode(
                ActivityInsightsConfiguration.self,
                from: Data(contentsOf: fileURL)
            )
        } catch {
            throw ActivityInsightsError.persistence("Configuration is unreadable: \(error.localizedDescription)")
        }
    }

    public func setShadowEnabled(
        _ enabled: Bool,
        now: Date = Date()
    ) throws -> ActivityInsightsConfiguration {
        var configuration = try load()
        if enabled {
            if !configuration.shadowEnabled || configuration.shadowEnabledSince == nil {
                configuration.shadowEnabledSince = now
            }
        } else {
            configuration.shadowEnabledSince = nil
        }
        configuration.shadowEnabled = enabled
        try save(configuration)
        return configuration
    }

    public func save(_ configuration: ActivityInsightsConfiguration) throws {
        guard configuration.historyIntervalSeconds >= 1,
              configuration.sampleIntervalSeconds >= 1,
              configuration.lookbackDays >= 1
        else {
            throw ActivityInsightsError.persistence("Configuration intervals and lookback must be positive.")
        }
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(configuration).write(to: fileURL, options: .atomic)
        } catch {
            throw ActivityInsightsError.persistence(error.localizedDescription)
        }
    }
}
