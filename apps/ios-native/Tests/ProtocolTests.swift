import XCTest
@testable import T3Native

final class ProtocolTests: XCTestCase {
    func json(_ text: String) throws -> JSONValue { try .decode(Data(text.utf8)) }

    func testHostedPairingPreservesEscapedCredentialAndRemovesSecretsFromOrigin() throws {
        let target = try PairingTarget("https://app.t3.codes/pair?host=https%3A%2F%2Fdev.example.com%3A8443&token=a%2Bb%3D#ignored=1")
        XCTAssertEqual(target.origin.absoluteString, "https://dev.example.com:8443")
        XCTAssertEqual(target.credential, "a+b=")
    }
    func testMobileWrapperAndFragmentToken() throws {
        let target = try PairingTarget("t3code://connect?pairingUrl=https%3A%2F%2Fhost.example%2F%23token%3Dabc")
        XCTAssertEqual(target.credential, "abc")
        XCTAssertEqual(target.origin.absoluteString, "https://host.example")
    }
    func testRejectsCredentialInURLUserinfoAndUnsupportedScheme() {
        XCTAssertThrowsError(try PairingTarget("https://user:password@host.example"))
        XCTAssertThrowsError(try PairingTarget("file:///private/file"))
    }
    func testFragmentCredentialWinsOverQueryAndSeparateCode() throws {
        let target = try PairingTarget("http://192.168.1.2:3773/path?token=query#token=fragment", code: "code")
        XCTAssertEqual(target.credential, "fragment")
        XCTAssertEqual(target.origin.absoluteString, "http://192.168.1.2:3773")
    }
    func testStreamingReplacementPreservesPositionAndDeduplicatesSequence() throws {
        var state = ThreadProjection()
        state.apply(try json(#"{"kind":"snapshot","snapshotSequence":10,"projection":{"thread":{"id":"t"},"turnItems":[{"id":"a","type":"assistant_message","text":"Hel"},{"id":"b","type":"user_message","text":"Continue"}]}}"#))
        let update = try json(#"{"kind":"event","sequence":11,"event":{"type":"turn-item.updated","payload":{"id":"a","type":"assistant_message","text":"Hello"}}}"#)
        state.apply(update)
        state.apply(try json(#"{"kind":"event","sequence":10,"event":{"type":"turn-item.updated","payload":{"id":"a","text":"stale"}}}"#))
        XCTAssertEqual(state.rows.map(\.id), ["a", "b"])
        XCTAssertEqual(state.rows[0].text, "Hello")
        XCTAssertEqual(state.sequence, 11)
    }
    func testReconnectSnapshotReplacesOldState() throws {
        var state = ThreadProjection()
        state.apply(try json(#"{"kind":"snapshot","snapshotSequence":10,"projection":{"turnItems":[{"id":"old"}]}}"#))
        state.apply(try json(#"{"kind":"snapshot","snapshotSequence":15,"projection":{"turnItems":[{"id":"new"}]}}"#))
        XCTAssertEqual(state.rows.map(\.id), ["new"])
    }
    func testInheritedVisiblePositionAndHistoryOverlap() throws {
        var state = ThreadProjection()
        state.apply(try json(#"{"kind":"snapshot","snapshotSequence":5,"projection":{"turnItems":[{"id":"b"}],"visibleTurnItems":[{"position":1,"item":{"id":"b"}},{"position":0,"item":{"id":"a"}}]},"hasMoreHistory":true,"historyCursor":"opaque"}"#))
        state.prependHistory(try json(#"{"items":[{"item":{"id":"earlier"}},{"item":{"id":"a","text":"stale"}}],"hasMoreHistory":false,"nextCursor":null}"#))
        XCTAssertEqual(state.rows.map(\.id), ["earlier", "a", "b"])
        XCTAssertFalse(state.hasMoreHistory)
        XCTAssertNil(state.historyCursor)
    }
    func testUnknownEventsAdvanceSequenceWithoutDeletingRows() throws {
        var state = ThreadProjection()
        state.apply(try json(#"{"kind":"snapshot","snapshotSequence":1,"projection":{"turnItems":[{"id":"a"}]}}"#))
        state.apply(try json(#"{"kind":"event","sequence":2,"event":{"type":"future.event","payload":{}}}"#))
        XCTAssertEqual(state.sequence, 2); XCTAssertEqual(state.rows.count, 1)
    }
    func testArchivedThreadLeavesActiveShell() throws {
        var shell = ShellProjection()
        shell.apply(try json(#"{"kind":"snapshot","snapshot":{"snapshotSequence":1,"projects":[],"threads":[{"id":"t"}]}}"#))
        shell.apply(try json(#"{"kind":"thread.updated","sequence":2,"location":"archive","thread":{"id":"t"}}"#))
        XCTAssertTrue(shell.threads.isEmpty)
    }
    func testRepositoryEnrichmentPreservesConversationsAndSequence() throws {
        var shell = ShellProjection()
        shell.apply(try json(#"{"kind":"snapshot","snapshot":{"snapshotSequence":5,"projects":[{"id":"p","title":"Current title","workspaceRoot":"/repo"},{"id":"other","workspaceRoot":"/other"}],"threads":[{"id":"t"}]}}"#))
        shell.apply(try json(#"{"kind":"snapshot","resolvedRepositoryIdentityRoots":["/repo"],"snapshot":{"snapshotSequence":20,"projects":[{"id":"p","title":"Stale title","workspaceRoot":"/repo","repositoryIdentity":{"name":"repo"}}],"threads":[]}}"#))
        XCTAssertEqual(shell.threads.count, 1)
        XCTAssertEqual(shell.projects.count, 2)
        XCTAssertEqual(shell.projects["p"]?["title"].string, "Current title")
        XCTAssertEqual(shell.projects["p"]?["repositoryIdentity"]["name"].string, "repo")
        XCTAssertEqual(shell.sequence, 5)
        shell.apply(try json(#"{"kind":"thread.updated","sequence":6,"location":"active","thread":{"id":"t","title":"Updated"}}"#))
        XCTAssertEqual(shell.threads["t"]?["title"].string, "Updated")
    }
    func testPreservesUnknownJSONFieldsAcrossRoundTrip() throws {
        let value = try json(#"{"future":{"values":[true,1,null,"x"]}}"#)
        XCTAssertEqual(try JSONValue.decode(value.data()), value)
    }
    func testWholeFrameBatchAndNestedFailure() async throws {
        let frame = try json(#"[{"_tag":"Pong"},{"_tag":"Chunk","requestId":"1","values":[]}]"#)
        XCTAssertEqual(RPCTransport.frames(frame).count, 2)
        let failure = try json(#"{"cause":{"reasons":[{"error":{"message":"Scope required"}}]}}"#)
        XCTAssertEqual(RPCTransport.failureMessage(failure), "Scope required")
    }
    func testUnclosedCodeFenceWhileStreaming() {
        let blocks = MarkdownBlock.parse("Text\n```swift\nlet value = 1")
        XCTAssertEqual(blocks.count, 2)
        guard case .code(let code, let language) = blocks[1] else { return XCTFail("Expected code") }
        XCTAssertEqual(code, "let value = 1"); XCTAssertEqual(language, "swift")
    }
    func testInboxLifecycleAndStableOrder() throws {
        let rows = try json(#"[{"id":"child","lineage":{"relationshipToParent":"subagent"}},{"id":"archived","archivedAt":"2026-01-01T00:00:00Z"},{"id":"settledPin","settledOverride":"settled","pinnedAt":"2026-01-01T00:00:00Z"},{"id":"pinned","pinnedAt":"2026-01-01T00:00:00Z"},{"id":"old","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-05T00:00:00Z"},{"id":"new","createdAt":"2026-01-02T00:00:00Z","updatedAt":"2026-01-02T00:00:00Z"},{"id":"arranged","activeOrderKey":"a0","createdAt":"2026-01-03T00:00:00Z"}]"#).array
        let index = ThreadIndex(threads: rows)
        XCTAssertEqual(index.matches.count, 5)
        XCTAssertEqual(index.pinned.map(\.id), ["pinned"])
        XCTAssertEqual(index.working.map(\.id), ["new", "old", "arranged"])
        XCTAssertEqual(index.settled.map(\.id), ["settledPin"])
    }
    func testPendingResponseWakesSnoozedPinnedThread() throws {
        let rows = try json(#"[{"id":"waiting","pinnedAt":"2026-01-01T00:00:00Z","snoozedUntil":"2030-01-01T00:00:00Z","pendingRuntimeRequest":{"kind":"user_input"}},{"id":"snoozedPin","pinnedAt":"2026-01-01T00:00:00Z","snoozedUntil":"2030-01-01T00:00:00Z"}]"#).array
        let index = ThreadIndex(threads: rows, now: Date(timeIntervalSince1970: 1767225600))
        XCTAssertEqual(index.pinned.map(\.id), ["waiting"])
        XCTAssertEqual(index.snoozed.map(\.id), ["snoozedPin"])
    }

}
