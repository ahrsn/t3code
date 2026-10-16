import SwiftUI

struct NativeMarkdown: View {
    let text: String
    let pointSize: Double
    let streaming: Bool
    @State private var document: RenderedDocument?
    private struct RenderedDocument { let source: String; let blocks: [MarkdownBlock] }
    private struct RenderKey: Hashable { let text: String; let streaming: Bool }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !streaming, let document, document.source == text {
                MarkdownBlocksView(blocks: document.blocks, pointSize: pointSize)
            } else { Text(text).font(T3Font.fixed(pointSize)).lineSpacing(4) }
        }
        .task(id: RenderKey(text: text, streaming: streaming)) {
            guard !streaming else { return }
            let source = text
            let blocks = await MarkdownDocuments.shared.blocks(for: source)
            guard !Task.isCancelled else { return }
            document = RenderedDocument(source: source, blocks: blocks)
        }
    }
}

private struct MarkdownBlocksView: View {
    let blocks: [MarkdownBlock]
    let pointSize: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block, pointSize: pointSize)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let pointSize: Double
    @Environment(\.t3Theme) private var theme
    var body: some View {
        switch block {
        case .prose(let text):
            Text(text).font(T3Font.fixed(pointSize)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        case .heading(let text, let level):
            Text(text).font(T3Font.fixed(pointSize + (level == 1 ? 6 : level == 2 ? 3 : 1), weight: .bold))
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
        case .code(let code, let language):
            CodeBlock(code: code, language: language, pointSize: max(12, pointSize - 3))
        case .list(let items, let ordered):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ordered ? "\(item.ordinal)." : "•")
                            .font(T3Font.fixed(pointSize)).foregroundStyle(theme.muted)
                            .frame(minWidth: 16, alignment: .trailing)
                        MarkdownBlocksView(blocks: item.blocks, pointSize: pointSize)
                    }
                }
            }
        case .quote(let blocks):
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.border).frame(width: 3)
                MarkdownBlocksView(blocks: blocks, pointSize: pointSize).foregroundStyle(theme.text)
            }.fixedSize(horizontal: false, vertical: true)
        case .table(let table):
            MarkdownTableView(table: table, pointSize: pointSize)
        case .rule: Divider().overlay(theme.border).padding(.vertical, 4)
        }
    }
}

private struct MarkdownTableView: View {
    let table: MarkdownTable
    let pointSize: Double
    @Environment(\.t3Theme) private var theme
    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                if !table.header.isEmpty {
                    row(table.header, header: true)
                    Divider().overlay(theme.border).gridCellUnsizedAxes(.horizontal)
                }
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, cells in row(cells, header: false) }
            }.padding(.vertical, 8)
        }.accessibilityIdentifier("markdown-table")
    }
    private func row(_ cells: [AttributedString], header: Bool) -> some View {
        GridRow {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, text in
                Text(text).font(T3Font.fixed(pointSize, weight: header ? .bold : .regular))
                    .fixedSize(horizontal: true, vertical: false)
                    .gridColumnAlignment(alignment(index))
            }
        }
    }
    private func alignment(_ index: Int) -> HorizontalAlignment {
        guard table.columns.indices.contains(index) else { return .leading }
        switch table.columns[index].alignment {
        case .center: return .center
        case .right: return .trailing
        default: return .leading
        }
    }
}

struct CodeBlock: View {
    let code: String
    let language: String
    let pointSize: Double
    @State private var copied = false
    @Environment(\.t3Theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(language.isEmpty ? "Code" : language).font(T3Font.caption).foregroundStyle(.secondary)
                Spacer()
                Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.string = code; copied = true
                }.font(T3Font.caption).buttonStyle(.borderless)
            }
            ScrollView(.horizontal) {
                Text(code).font(.custom("Menlo-Regular", fixedSize: pointSize)).textSelection(.enabled).fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(12).background(theme.color("codeBackground"), in: .rect(cornerRadius: 12))
    }
}
