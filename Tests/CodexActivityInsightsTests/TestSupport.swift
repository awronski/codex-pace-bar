import CodexActivityInsightsCore
import Foundation

let testDay: TimeInterval = 24 * 60 * 60

func testDate(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: seconds)
}

func testJSON(_ source: String) throws -> ActivityJSONValue {
    try ActivityJSONValue.parse(data: Data(source.utf8))
}

func makeTestDirectory(_ name: String = #function) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("CodexActivityInsightsTests", isDirectory: true)
        .appendingPathComponent(name, isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

func testThread(
    id: String = "thread-1",
    createdAt: Date = testDate(1_000),
    updatedAt: Date = testDate(1_100),
    recencyAt: Date = testDate(1_100),
    actor: ActivityThreadActor = .user,
    mechanism: ActivityCreationMechanism = .interactive,
    confidence: ActivityProvenanceConfidence = .explicit,
    archived: Bool = false
) -> ActivityThreadFact {
    ActivityThreadFact(
        threadID: id,
        createdAt: createdAt,
        sourceUpdatedAt: updatedAt,
        sourceRecencyAt: recencyAt,
        sessionSource: actor == .codex ? "subAgentThreadSpawn" : "vscode",
        threadSource: actor == .unknown ? nil : actor.rawValue,
        parentThreadID: actor == .codex ? "parent" : nil,
        forkedFromID: nil,
        actor: actor,
        mechanism: mechanism,
        confidence: confidence,
        archived: archived
    )
}

func testTurn(
    threadID: String = "thread-1",
    turnID: String = "turn-1",
    startedAt: Date? = testDate(1_200),
    completedAt: Date? = testDate(1_202),
    durationMilliseconds: Int? = 2_000,
    status: String = "completed"
) -> ActivityTurnFact {
    ActivityTurnFact(
        threadID: threadID,
        turnID: turnID,
        startedAt: startedAt,
        completedAt: completedAt,
        durationMilliseconds: durationMilliseconds,
        status: status
    )
}

func testInput(
    threadID: String = "thread-1",
    turnID: String = "turn-1",
    itemID: String = "input-1",
    ordinal: Int = 0,
    actor: ActivityThreadActor = .user,
    kind: ActivityInputKind = .initialTask,
    submittedAtEstimate: Date? = testDate(1_200),
    characters: Int = 12,
    bytes: Int = 12
) -> ActivityInputFact {
    ActivityInputFact(
        threadID: threadID,
        turnID: turnID,
        itemID: itemID,
        ordinal: ordinal,
        actor: actor,
        kind: kind,
        submittedAtEstimate: submittedAtEstimate,
        textCharacters: characters,
        utf8Bytes: bytes,
        attachmentCount: 0,
        skillCount: 0,
        mentionCount: 0
    )
}

func testRun(
    id: UUID = UUID(),
    at date: Date = testDate(1_300),
    failures: Int = 0
) -> ActivityCollectionRun {
    ActivityCollectionRun(
        runID: id,
        startedAt: date.addingTimeInterval(-1),
        finishedAt: date,
        pagesRead: 2,
        threadsSeen: 1,
        threadsCollected: 1,
        threadsUnchanged: 0,
        turnsCollected: 1,
        inputsCollected: 1,
        threadFailures: failures
    )
}

func testBatch(
    thread: ActivityThreadFact = testThread(),
    turn: ActivityTurnFact = testTurn(),
    input: ActivityInputFact = testInput(),
    run: ActivityCollectionRun = testRun()
) -> ActivityCollectionBatch {
    ActivityCollectionBatch(
        threads: [thread],
        turns: [turn],
        inputs: [input],
        refreshedThreadIDs: [thread.threadID],
        run: run
    )
}
