import XCTest
@testable import T3Native

final class MarkdownTests: XCTestCase {
    private func text(_ value: AttributedString) -> String { String(value.characters) }

    func testHeadingsInlineStylesAndParagraphBoundaries() {
        let blocks = MarkdownBlock.parse("## Title\n\nA **bold** statement with `code`.\n\nAnother paragraph.")
        XCTAssertEqual(blocks.count, 3)
        guard case .heading(let title, 2) = blocks[0], case .prose(let prose) = blocks[1] else { return XCTFail("Missing block structure") }
        XCTAssertEqual(text(title), "Title")
        XCTAssertEqual(text(prose), "A bold statement with code.")
        XCTAssertTrue(prose.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        XCTAssertTrue(prose.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
    }
    func testNestedListsKeepTheirOwnStructureAndOrdinal() {
        let blocks = MarkdownBlock.parse("3. First\n4. Second\n   - Nested **item**\n\n> Quoted paragraph\n>\n> Another paragraph")
        guard case .list(let items, ordered: true) = blocks.first, items.count == 2,
              case .list(let nested, ordered: false) = items[1].blocks.last,
              case .quote(let quoted) = blocks.last else { return XCTFail("Missing list or quote") }
        XCTAssertEqual(items.map(\.ordinal), [3, 4])
        XCTAssertEqual(nested.count, 1); XCTAssertEqual(quoted.count, 2)
    }
    func testTablesKeepEmptyCellsAndColumnAlignment() {
        let blocks = MarkdownBlock.parse("| A | B | C |\n| :--- | :---: | ---: |\n| left | | right |")
        guard case .table(let table) = blocks.first else { return XCTFail("Expected table") }
        XCTAssertEqual(table.header.map(text), ["A", "B", "C"])
        XCTAssertEqual(table.rows.first?.map(text), ["left", "", "right"])
        XCTAssertEqual(table.columns.map(\.alignment), [.left, .center, .right])
    }
    func testLongFenceAllowsEmbeddedBackticksAndTildeFenceCloses() {
        let blocks = MarkdownBlock.parse("````md\n```swift\nlet x = 1\n```\n````\n\n~~~sh\necho done\n~~~")
        guard blocks.count == 2, case .code(let first, "md") = blocks[0], case .code(let second, "sh") = blocks[1] else { return XCTFail("Expected fenced code") }
        XCTAssertEqual(first, "```swift\nlet x = 1\n```"); XCTAssertEqual(second, "echo done")
    }
    func testQuotedCodeAndLinksRetainNativeSemantics() {
        let blocks = MarkdownBlock.parse("> ```sh\n> echo done\n> ```\n\n[Protocol](https://example.com/protocol)")
        guard case .quote(let quoted) = blocks.first, case .code(let code, "sh") = quoted.first,
              case .prose(let link) = blocks.last else { return XCTFail("Missing nested code or link") }
        XCTAssertEqual(code, "echo done")
        XCTAssertEqual(link.runs.first?.link?.absoluteString, "https://example.com/protocol")
    }
}
