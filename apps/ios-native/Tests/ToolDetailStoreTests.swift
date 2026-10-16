import XCTest
@testable import T3Native

@MainActor final class ToolDetailStoreTests: XCTestCase {
    func testDisconnectedOrStaleScreensCannotRequestToolDetail() async throws {
        let suite = "T3ToolDetailTest." + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = AppStore(preferences: preferences), detail = Conversation(id: "current")
        let item = JSONValue.object(["id": .string("command"), "type": .string("command_execution"), "input": .string("swift test")])
        detail.apply(.object(["kind": .string("snapshot"), "projection": .object(["thread": .object(["id": .string("current")]), "turnItems": .array([item])])]))
        store.conversation = detail
        do { _ = try await store.loadTurnItem(item, threadID: "current", hostID: nil); XCTFail("Disconnected fetch accepted") }
        catch { XCTAssertEqual(error.localizedDescription, "Reconnect to this server to load output.") }
        do { _ = try await store.loadTurnItem(item, threadID: "previous", hostID: nil); XCTFail("Stale screen accepted") }
        catch { XCTAssertTrue(error is CancellationError) }
        var removed = item; removed["id"] = .string("removed")
        do { _ = try await store.loadTurnItem(removed, threadID: "current", hostID: nil); XCTFail("Removed row accepted") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(store.error)
        XCTAssertTrue(store.conversation === detail)
    }
}
