import Foundation

public enum ActivityInsightsError: Error, Equatable, LocalizedError, Sendable {
    case codexExecutableNotFound
    case appServerStartupFailed(String)
    case appServerExited(Int32?)
    case appServerTimeout(String)
    case appServerWriteFailed
    case invalidJSON(String)
    case jsonRPC(code: Int?, message: String)
    case invalidResponse(String)
    case unsupportedSchema(Int)
    case persistence(String)

    public var errorDescription: String? {
        switch self {
        case .codexExecutableNotFound:
            return "Codex executable was not found."
        case let .appServerStartupFailed(message):
            return "Codex App Server could not start: \(message)"
        case let .appServerExited(status):
            return "Codex App Server exited\(status.map { " with status \($0)" } ?? "")."
        case let .appServerTimeout(method):
            return "Codex App Server timed out while calling \(method)."
        case .appServerWriteFailed:
            return "Could not write to Codex App Server."
        case let .invalidJSON(message):
            return "Invalid App Server JSON: \(message)"
        case let .jsonRPC(code, message):
            return "App Server error\(code.map { " \($0)" } ?? ""): \(message)"
        case let .invalidResponse(message):
            return "Invalid App Server response: \(message)"
        case let .unsupportedSchema(version):
            return "Unsupported activity-insights schema version \(version)."
        case let .persistence(message):
            return "Activity-insights persistence failed: \(message)"
        }
    }
}

public protocol ActivityAppServerRequesting: Sendable {
    func request(
        method: String,
        params: ActivityJSONValue?,
        timeoutSeconds: TimeInterval
    ) async throws -> ActivityJSONValue

    func shutdown() async
}

public actor ActivityAppServerClient: ActivityAppServerRequesting {
    private let executableURL: URL
    private let clientVersion: String
    private var process: Process?
    private var processGeneration: UUID?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutContinuation: AsyncStream<Data>.Continuation?
    private var stdoutReaderTask: Task<Void, Never>?
    private var decoder = ActivityJSONLineDecoder()
    private var initialized = false
    private var nextRequestID = 1
    private var pending: [Int: CheckedContinuation<ActivityJSONValue, Error>] = [:]

    public init(executableURL: URL, clientVersion: String = "development") {
        self.executableURL = executableURL
        self.clientVersion = clientVersion
    }

    public func request(
        method: String,
        params: ActivityJSONValue? = nil,
        timeoutSeconds: TimeInterval = 15
    ) async throws -> ActivityJSONValue {
        try await ensureInitialized()
        return try await sendRequest(method: method, params: params, timeoutSeconds: timeoutSeconds)
    }

    public func shutdown() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutContinuation?.finish()
        stdoutReaderTask?.cancel()
        stdoutContinuation = nil
        stdoutReaderTask = nil
        process?.terminationHandler = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        processGeneration = nil
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        initialized = false
        failPending(ActivityInsightsError.appServerExited(nil))
    }

    private func ensureInitialized() async throws {
        if initialized, process?.isRunning == true { return }
        try startIfNeeded()

        _ = try await sendRequest(
            method: "initialize",
            params: .object([
                "clientInfo": .object([
                    "name": .string("codex_activity_insights"),
                    "title": .string("Codex Activity Insights"),
                    "version": .string(clientVersion)
                ]),
                "capabilities": .object(["experimentalApi": .bool(true)])
            ]),
            timeoutSeconds: 15
        )
        try writeNotification(method: "initialized", params: .object([:]))
        initialized = true
    }

    private func startIfNeeded() throws {
        if process?.isRunning == true { return }

        let process = Process()
        let generation = UUID()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let (stdoutStream, stdoutContinuation) = AsyncStream<Data>.makeStream()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                stdoutContinuation.finish()
                return
            }
            stdoutContinuation.yield(data)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        process.terminationHandler = { [weak self] process in
            Task {
                await self?.handleTermination(status: process.terminationStatus, generation: generation)
            }
        }

        processGeneration = generation
        self.stdoutContinuation = stdoutContinuation
        stdoutReaderTask = Task { [weak self] in
            for await data in stdoutStream {
                guard !Task.isCancelled else { return }
                await self?.receive(data)
            }
        }
        decoder = ActivityJSONLineDecoder()
        initialized = false

        do {
            try process.run()
        } catch {
            throw ActivityInsightsError.appServerStartupFailed(error.localizedDescription)
        }

        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
    }

    private func sendRequest(
        method: String,
        params: ActivityJSONValue?,
        timeoutSeconds: TimeInterval
    ) async throws -> ActivityJSONValue {
        let id = nextRequestID
        nextRequestID += 1

        return try await withThrowingTaskGroup(of: ActivityJSONValue.self) { group in
            group.addTask { [self] in
                try await performRequest(id: id, method: method, params: params)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                throw ActivityInsightsError.appServerTimeout(method)
            }

            guard let value = try await group.next() else {
                throw ActivityInsightsError.appServerTimeout(method)
            }
            group.cancelAll()
            return value
        }
    }

    private func performRequest(
        id: Int,
        method: String,
        params: ActivityJSONValue?
    ) async throws -> ActivityJSONValue {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation(isolation: self) { continuation in
                pending[id] = continuation
                do {
                    try writeRequest(id: id, method: method, params: params)
                } catch {
                    pending.removeValue(forKey: id)
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            Task { await self.cancelPendingRequest(id) }
        }
    }

    private func writeRequest(id: Int, method: String, params: ActivityJSONValue?) throws {
        var message: [String: Any] = ["id": id, "method": method]
        if let params { message["params"] = params.anyValue() }
        try write(message)
    }

    private func writeNotification(method: String, params: ActivityJSONValue?) throws {
        var message: [String: Any] = ["method": method]
        if let params { message["params"] = params.anyValue() }
        try write(message)
    }

    private func write(_ message: [String: Any]) throws {
        guard let stdinPipe,
              JSONSerialization.isValidJSONObject(message),
              var data = try? JSONSerialization.data(withJSONObject: message)
        else {
            throw ActivityInsightsError.appServerWriteFailed
        }
        data.append(0x0A)
        do {
            try stdinPipe.fileHandleForWriting.write(contentsOf: data)
        } catch {
            throw ActivityInsightsError.appServerWriteFailed
        }
    }

    private func receive(_ data: Data) {
        for result in decoder.append(data) {
            switch result {
            case let .success(message):
                handle(message)
            case let .failure(error):
                failPending(error)
            }
        }
    }

    private func handle(_ message: ActivityJSONValue) {
        guard let object = message.objectValue,
              object["method"] == nil,
              let id = object["id"]?.intValue,
              let continuation = pending.removeValue(forKey: id)
        else {
            return
        }

        if let error = object["error"]?.objectValue {
            continuation.resume(throwing: ActivityInsightsError.jsonRPC(
                code: error["code"]?.intValue,
                message: error["message"]?.stringValue ?? "Unknown error"
            ))
            return
        }
        continuation.resume(returning: object["result"] ?? .null)
    }

    private func handleTermination(status: Int32, generation: UUID) {
        guard generation == processGeneration else { return }
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutContinuation?.finish()
        stdoutReaderTask?.cancel()
        stdoutContinuation = nil
        stdoutReaderTask = nil
        processGeneration = nil
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        initialized = false
        failPending(ActivityInsightsError.appServerExited(status))
    }

    private func cancelPendingRequest(_ id: Int) {
        pending.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    private func failPending(_ error: Error) {
        let continuations = pending.values
        pending.removeAll()
        continuations.forEach { $0.resume(throwing: error) }
    }
}

public struct ActivityCodexExecutableResolver {
    private let path: String
    private let home: URL
    private let fileManager: FileManager

    public init(
        path: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.path = path
        self.home = home
        self.fileManager = fileManager
    }

    public func resolve(configuredPath: String? = nil) throws -> URL {
        if let configuredPath, !configuredPath.isEmpty {
            let candidate = configuredPath.hasPrefix("~/")
                ? home.appendingPathComponent(String(configuredPath.dropFirst(2)))
                : URL(fileURLWithPath: configuredPath)
            if configuredPath.contains("/"), fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
            if !configuredPath.contains("/"), let found = findInPath(configuredPath) {
                return found
            }
            throw ActivityInsightsError.codexExecutableNotFound
        }

        if let found = findInPath("codex") { return found }
        let candidates = [
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
            home.appendingPathComponent(".local/bin/codex"),
            home.appendingPathComponent(".npm-global/bin/codex"),
            home.appendingPathComponent(".bun/bin/codex"),
            home.appendingPathComponent(".local/share/mise/shims/codex")
        ]
        if let found = candidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) {
            return found
        }
        let installs = home.appendingPathComponent(".local/share/mise/installs/npm-openai-codex")
        if let versions = try? fileManager.contentsOfDirectory(at: installs, includingPropertiesForKeys: nil),
           let found = versions
            .sorted(by: { $0.lastPathComponent > $1.lastPathComponent })
            .map({ $0.appendingPathComponent("bin/codex") })
            .first(where: { fileManager.isExecutableFile(atPath: $0.path) }) {
            return found
        }
        throw ActivityInsightsError.codexExecutableNotFound
    }

    private func findInPath(_ name: String) -> URL? {
        path.split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}
