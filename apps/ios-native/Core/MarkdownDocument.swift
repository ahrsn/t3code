import Foundation

struct MarkdownDocument: Sendable, Equatable {
    let source: String
    let blocks: [MarkdownBlock]
    // Parsing is deterministic; the source identifies the presentation.
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.source == rhs.source }
}

struct MarkdownListItem: Sendable {
    let ordinal: Int
    let blocks: [MarkdownBlock]
}
struct MarkdownTable: Sendable {
    let columns: [PresentationIntent.TableColumn]
    let header: [AttributedString]
    let rows: [[AttributedString]]
}

enum MarkdownBlock: Sendable {
    case prose(AttributedString), heading(AttributedString, Int), code(String, String)
    case list([MarkdownListItem], ordered: Bool), quote([MarkdownBlock]), table(MarkdownTable), rule

    /// Foundation parses block structure and inline styling in one pass.
    static func parse(_ text: String) -> [MarkdownBlock] {
        guard let attributed = try? AttributedString(markdown: text, options: .init(failurePolicy: .returnPartiallyParsedIfPossible)) else {
            return [.prose(AttributedString(text))]
        }
        let root = Node(kind: .paragraph)
        var nodes: [Int: Node] = [:]
        for run in attributed.runs {
            guard !Task.isCancelled else { return [] }
            var parent = root
            for intent in (run.presentationIntent?.components ?? []).reversed() {
                if let existing = nodes[intent.identity] { parent = existing }
                else {
                    let node = Node(kind: intent.kind)
                    parent.children.append(node); nodes[intent.identity] = node; parent = node
                }
            }
            var inline = AttributedString(attributed[run.range])
            inline.presentationIntent = nil
            parent.text.append(inline)
        }
        if root.children.isEmpty { return root.text.characters.isEmpty ? [] : [.prose(root.text)] }
        return root.children.flatMap(\.blocks)
    }

    private final class Node {
        let kind: PresentationIntent.Kind
        var text = AttributedString()
        var children: [Node] = []
        init(kind: PresentationIntent.Kind) { self.kind = kind }
        var blocks: [MarkdownBlock] {
            switch kind {
            case .paragraph: return [.prose(text)]
            case .header(let level): return [.heading(text, level)]
            case .codeBlock(let language):
                var code = String(text.characters)
                if code.hasSuffix("\n") { code.removeLast() }
                return [.code(code, language ?? "")]
            case .orderedList, .unorderedList:
                let items = children.compactMap { node -> MarkdownListItem? in
                    guard case .listItem(let ordinal) = node.kind else { return nil }
                    return MarkdownListItem(ordinal: ordinal, blocks: node.children.flatMap(\.blocks))
                }
                return [.list(items, ordered: kind == .orderedList)]
            case .blockQuote: return [.quote(children.flatMap(\.blocks))]
            case .thematicBreak: return [.rule]
            case .table(let columns):
                var header: [AttributedString] = [], rows: [[AttributedString]] = []
                for row in children {
                    var cells = Array(repeating: AttributedString(), count: columns.count)
                    for cell in row.children {
                        if case .tableCell(let index) = cell.kind, cells.indices.contains(index) { cells[index] = cell.text }
                    }
                    if row.kind == .tableHeaderRow { header = cells } else { rows.append(cells) }
                }
                return [.table(MarkdownTable(columns: columns, header: header, rows: rows))]
            default: return children.isEmpty ? [.prose(text)] : children.flatMap(\.blocks)
            }
        }
    }
}

/// Completed message parses survive lazy-row recreation, bounded by source bytes.
/// Live token updates bypass this cache and the Markdown parser entirely.
actor MarkdownDocuments {
    static let shared = MarkdownDocuments()
    private var documents: [String: [MarkdownBlock]] = [:]
    private var order: [String] = []
    private var sourceBytes = 0
    private let byteLimit = 512_000

    func documents(for items: [JSONValue]) -> [String: MarkdownDocument] {
        var result: [String: MarkdownDocument] = [:]
        for wrapper in items {
            guard !Task.isCancelled else { return [:] }
            let row = TimelineRow(value: wrapper["item"].isNull ? wrapper : wrapper["item"])
            guard row.isMessage || row.type == "proposed_plan", !row.value["streaming"].bool else { continue }
            result[row.id] = MarkdownDocument(source: row.text, blocks: blocks(for: row.text))
        }
        return result
    }

    func blocks(for source: String) -> [MarkdownBlock] {
        guard !Task.isCancelled else { return [] }
        if let cached = documents[source] { return cached }
        let blocks = MarkdownBlock.parse(source)
        let cost = source.utf8.count
        guard !Task.isCancelled, cost <= byteLimit else { return blocks }
        while (sourceBytes + cost > byteLimit || order.count >= 128), !order.isEmpty {
            let oldest = order.removeFirst()
            documents.removeValue(forKey: oldest); sourceBytes -= oldest.utf8.count
        }
        documents[source] = blocks; order.append(source); sourceBytes += cost
        return blocks
    }
}
