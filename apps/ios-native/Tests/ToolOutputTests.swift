import XCTest
@testable import T3Native

final class ToolOutputTests: XCTestCase {
    func testStructuredResultsKeepTypesAndReadableInput() async throws {
        let item = try JSONValue.decode(Data(#"{"type":"dynamic_tool","input":{"flag":false,"path":"a.swift"},"output":{"count":0,"missing":null,"labels":["one","two"]},"status":"completed"}"#.utf8))
        let document = await ToolDocuments.shared.document(for: item)
        XCTAssertEqual(document.sections.map(\.title), ["Input", "Output"])
        let input = try JSONValue.decode(Data(document.sections[0].text.utf8))
        let output = try JSONValue.decode(Data(document.sections[1].text.utf8))
        XCTAssertEqual(input, item["input"]); XCTAssertEqual(output, item["output"])
        XCTAssertFalse(document.failed); XCTAssertEqual(document.status, "Completed")
        XCTAssertTrue(document.sections.allSatisfy { !$0.truncated })
    }
    func testCommandExitCodesAndErrorResultsRemainVisible() async {
        let failed = await ToolDocuments.shared.document(for: .object(["type": .string("command_execution"), "input": .string("swift test"), "output": .string("Failed"), "exitCode": .number(2)]))
        XCTAssertTrue(failed.failed); XCTAssertEqual(failed.status, "Exit 2")
        XCTAssertEqual(failed.sections.map(\.text), ["swift test", "Failed"])
        let jsonError = await ToolDocuments.shared.document(for: .object(["output": .object(["isError": .bool(true)])]))
        XCTAssertTrue(jsonError.failed)
        let success = await ToolDocuments.shared.document(for: .object(["exitCode": .number(0)]))
        XCTAssertFalse(success.failed); XCTAssertEqual(success.status, "Exit 0")
    }
    func testUnicodeOutputIsBoundedWithoutBreakingCharacters() async {
        let text = String(repeating: "🧑🏽‍💻", count: 10_000)
        let document = await ToolDocuments.shared.document(for: .object(["output": .string(text)]))
        let section = document.sections[0]
        XCTAssertTrue(section.truncated)
        XCTAssertLessThanOrEqual(section.text.utf8.count, ToolDocuments.maximumTextBytes)
        XCTAssertFalse(section.text.contains("�")); XCTAssertTrue(text.hasPrefix(section.text))
    }
    func testLargeCollectionsAndBinaryBlocksHaveBoundedPresentation() async throws {
        let block = JSONValue.object(["type": .string("image"), "mimeType": .string("image/png"), "data": .string(String(repeating: "A", count: 1_000_000))])
        let document = await ToolDocuments.shared.document(for: .object(["output": .object(["content": .array([block]), "values": .array(Array(repeating: .number(1), count: 10_000))])]))
        let section = document.sections[0]
        XCTAssertTrue(section.truncated); XCTAssertLessThan(section.text.utf8.count, 20_000)
        let output = try JSONValue.decode(Data(section.text.utf8))
        XCTAssertTrue(output["content"].array[0]["data"].isNull)
        XCTAssertEqual(output["content"].array[0]["mimeType"].string, "image/png")
    }
    func testSummarizedInputAndOmittedOutputRequestFullDetail() {
        XCTAssertTrue(ToolOutputDocument.needsFetch(.object(["outputOmitted": .bool(true)])))
        XCTAssertTrue(ToolOutputDocument.needsFetch(.object(["input": .object(["summary": .string("Read"), "truncated": .bool(true)])])))
        XCTAssertFalse(ToolOutputDocument.needsFetch(.object(["input": .object(["truncated": .bool(false)])])))
    }
    func testInheritedSnapshotAndHistoryUseOriginalItemTargets() {
        var projection = ThreadProjection()
        let wrapper = JSONValue.object(["sourceThreadId": .string("parent"), "sourceItemId": .string("original"), "position": .number(0),
                                        "item": .object(["id": .string("inherited"), "type": .string("command_execution"), "threadId": .string("parent")])])
        projection.apply(.object(["kind": .string("snapshot"), "projection": .object(["thread": .object(["id": .string("child")]), "visibleTurnItems": .array([wrapper])])]))
        XCTAssertEqual(projection.target(for: "inherited")?.threadID, "parent")
        XCTAssertEqual(projection.target(for: "inherited")?.itemID, "original")
        var earlier = wrapper; earlier["item"]["id"] = .string("earlier"); earlier["sourceItemId"] = .string("old-original")
        projection.prependHistory(.object(["items": .array([earlier, wrapper])]))
        XCTAssertEqual(projection.itemOrder, ["earlier", "inherited"])
        XCTAssertEqual(projection.target(for: "earlier")?.itemID, "old-original")
        XCTAssertEqual(projection.target(for: "inherited")?.itemID, "original")
    }
    func testDetailRejectsMissingAndMismatchedItems() throws {
        let item = JSONValue.object(["id": .string("one"), "threadId": .string("thread"), "type": .string("dynamic_tool")])
        let target = TurnItemTarget(item: item, wrapper: .null, threadID: "fallback")
        XCTAssertEqual(try target.validate(.object(["item": item]), type: "dynamic_tool"), item)
        XCTAssertEqual(target.payload(revision: "v1")["revision"], .string("v1"))
        var wrong = item; wrong["id"] = .string("two")
        XCTAssertThrowsError(try target.validate(.object(["item": wrong]), type: "dynamic_tool"))
        wrong = item; wrong["threadId"] = .string("other")
        XCTAssertThrowsError(try target.validate(.object(["item": wrong]), type: "dynamic_tool"))
        XCTAssertThrowsError(try target.validate(.object(["item": item]), type: "command_execution"))
        XCTAssertThrowsError(try target.validate(.object(["item": .null]), type: "dynamic_tool"))
    }
}
