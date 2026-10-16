import XCTest
@testable import T3Native

@MainActor final class HistoryPresentationTests: XCTestCase {
    func testPreparedPageKeepsLiveOverlapAndDropsStalePresentation() async throws {
        let detail = Conversation(id: "t")
        detail.apply(try .decode(Data(###"{"kind":"snapshot","snapshotSequence":1,"projection":{"thread":{"id":"t"},"turnItems":[{"id":"live","type":"assistant_message","text":"Live text"}]}}"###.utf8)))
        let page = try JSONValue.decode(Data(###"{"items":[{"item":{"id":"earlier","type":"assistant_message","text":"## Earlier"}},{"item":{"id":"live","type":"assistant_message","text":"Stale text"}}],"hasMoreHistory":false,"nextCursor":null}"###.utf8))
        detail.historyDocuments = await MarkdownDocuments.shared.documents(for: page["items"].array)
        detail.projection.prependHistory(page); detail.refreshRows()
        XCTAssertEqual(detail.rows.map(\.id), ["earlier", "live"])
        XCTAssertEqual(detail.rows[0].markdown?.source, "## Earlier")
        XCTAssertEqual(detail.rows[1].text, "Live text")
        XCTAssertNil(detail.rows[1].markdown)
        detail.apply(try .decode(Data(###"{"kind":"event","sequence":2,"event":{"type":"turn-item.updated","payload":{"id":"earlier","type":"assistant_message","text":"Edited text"}}}"###.utf8)))
        XCTAssertEqual(detail.rows[0].text, "Edited text")
        XCTAssertNil(detail.rows[0].markdown)
    }
    func testStreamingHistoryIsNotPreformatted() async {
        let documents = await MarkdownDocuments.shared.documents(for: [.object(["id": .string("live"), "type": .string("assistant_message"), "text": .string("Still streaming"), "streaming": .bool(true)])])
        XCTAssertTrue(documents.isEmpty)
    }
}
