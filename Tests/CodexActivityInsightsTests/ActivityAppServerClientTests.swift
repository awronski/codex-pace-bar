@testable import CodexActivityInsightsCore
import Foundation
import Testing

@Suite(.serialized)
struct ActivityAppServerClientTests {
    @Test
    func lineDecoderHandlesPartialMultipleAndMalformedMessages() throws {
        var decoder = ActivityJSONLineDecoder()

        #expect(decoder.append(Data(#"{"id":1"#.utf8)).isEmpty)
        let values = decoder.append(Data(", \"result\":{\"ok\":true}}\n{\"method\":\"event\"}\nnot-json\n".utf8))

        #expect(values.count == 3)
        #expect(try values[0].get()["result"]?["ok"] == .bool(true))
        #expect(try values[1].get()["method"] == .string("event"))
        #expect(throws: ActivityInsightsError.self) { _ = try values[2].get() }
    }

    @Test
    func initializesOnceAndCorrelatesResponses() async throws {
        let fixture = try makeActivityFakeServer()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let client = ActivityAppServerClient(executableURL: fixture.executable)
        defer { Task { await client.shutdown() } }

        let first = try await client.request(method: "echo", timeoutSeconds: 1)
        let second = try await client.request(method: "echo", timeoutSeconds: 1)

        #expect(first["ok"] == .bool(true))
        #expect(second["ok"] == .bool(true))
    }

    @Test
    func preservesByteOrderWhenOneResponseArrivesInManyChunks() async throws {
        let fixture = try makeActivityFakeServer()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let client = ActivityAppServerClient(executableURL: fixture.executable)
        defer { Task { await client.shutdown() } }

        let result = try await client.request(method: "fragmented", timeoutSeconds: 2)

        #expect(result["payload"]?.stringValue?.count == 4_000)
        #expect(result["payload"]?.stringValue?.allSatisfy { $0 == "x" } == true)
    }

    @Test
    func correlatesManyConcurrentRequests() async throws {
        let fixture = try makeActivityFakeServer()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let client = ActivityAppServerClient(executableURL: fixture.executable)
        defer { Task { await client.shutdown() } }

        let results = try await withThrowingTaskGroup(of: ActivityJSONValue.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    try await client.request(method: "echo", timeoutSeconds: 2)
                }
            }
            var values: [ActivityJSONValue] = []
            for try await value in group { values.append(value) }
            return values
        }

        #expect(results.count == 20)
        #expect(results.allSatisfy { $0["ok"] == .bool(true) })
    }

    @Test
    func jsonRpcErrorsPreserveCodeAndMessage() async throws {
        let fixture = try makeActivityFakeServer()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let client = ActivityAppServerClient(executableURL: fixture.executable)
        defer { Task { await client.shutdown() } }

        do {
            _ = try await client.request(method: "rpc-error", timeoutSeconds: 1)
            Issue.record("Expected JSON-RPC error.")
        } catch let error as ActivityInsightsError {
            #expect(error == .jsonRPC(code: -32601, message: "missing"))
        }
    }

    @Test
    func timeoutCancelsPendingRequestAndClientRemainsUsable() async throws {
        let fixture = try makeActivityFakeServer()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let client = ActivityAppServerClient(executableURL: fixture.executable)
        defer { Task { await client.shutdown() } }

        do {
            _ = try await client.request(method: "hang", timeoutSeconds: 0.05)
            Issue.record("Expected timeout.")
        } catch let error as ActivityInsightsError {
            #expect(error == .appServerTimeout("hang"))
        }

        #expect(try await client.request(method: "echo", timeoutSeconds: 1)["ok"] == .bool(true))
    }

    @Test
    func malformedOutputAndProcessExitFailPendingRequests() async throws {
        let malformedFixture = try makeActivityFakeServer()
        defer { try? FileManager.default.removeItem(at: malformedFixture.root) }
        let malformedClient = ActivityAppServerClient(executableURL: malformedFixture.executable)
        do {
            _ = try await malformedClient.request(method: "malformed", timeoutSeconds: 1)
            Issue.record("Expected malformed response failure.")
        } catch let error as ActivityInsightsError {
            guard case .invalidJSON = error else {
                Issue.record("Expected invalidJSON, got \(error).")
                return
            }
        }
        await malformedClient.shutdown()

        let exitFixture = try makeActivityFakeServer()
        defer { try? FileManager.default.removeItem(at: exitFixture.root) }
        let exitClient = ActivityAppServerClient(executableURL: exitFixture.executable)
        do {
            _ = try await exitClient.request(method: "exit", timeoutSeconds: 1)
            Issue.record("Expected process exit failure.")
        } catch let error as ActivityInsightsError {
            #expect(error == .appServerExited(7))
        }
        await exitClient.shutdown()
    }

    @Test
    func executableResolverHonorsConfiguredPathAndPathLookup() throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("codex-test")
        try "#!/bin/sh\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let resolver = ActivityCodexExecutableResolver(
            path: directory.path,
            home: directory
        )

        #expect(try resolver.resolve(configuredPath: executable.path) == executable)
        #expect(try resolver.resolve(configuredPath: "codex-test") == executable)
        #expect(throws: ActivityInsightsError.self) {
            _ = try resolver.resolve(configuredPath: "does-not-exist")
        }
    }

    private func makeActivityFakeServer() throws -> (root: URL, executable: URL) {
        let root = try makeTestDirectory("ActivityAppServerClientTests")
        let executable = root.appendingPathComponent("fake-codex")
        let script = #"""
        #!/bin/sh
        while IFS= read -r line; do
          id=$(printf '%s\n' "$line" | /usr/bin/sed -E 's/.*"id":([0-9]+).*/\1/')
          case "$line" in
            *'"method":"initialize"'*)
              printf '{"id":%s,"result":{}}\n' "$id"
              ;;
            *'"method":"echo"'*)
              printf '{"id":%s,"result":{"ok":true}}\n' "$id"
              ;;
            *'"method":"rpc-error"'*)
              printf '{"id":%s,"error":{"code":-32601,"message":"missing"}}\n' "$id"
              ;;
            *'"method":"fragmented"'*)
              printf '{"id":%s,"result":{"payload":"' "$id"
              i=0
              while [ "$i" -lt 4000 ]; do
                printf 'x'
                i=$((i + 1))
              done
              printf '"}}\n'
              ;;
            *'"method":"malformed"'*)
              printf 'not-json\n'
              ;;
            *'"method":"exit"'*)
              exit 7
              ;;
            *'"method":"hang"'*)
              ;;
          esac
        done
        """#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return (root, executable)
    }
}
