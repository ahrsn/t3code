import SwiftUI

struct NativeMarkdown: View {
    let text: String
    let pointSize: Double
    let streaming: Bool
    @State private var blocks: [MarkdownBlock] = []
    private struct RenderKey: Hashable { let text: String; let streaming: Bool }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if streaming || blocks.isEmpty { Text(text).font(T3Font.fixed(pointSize)).lineSpacing(4) }
            ForEach(Array((streaming ? [] : blocks).enumerated()), id: \.offset) { _, block in
                switch block {
                case .prose(let attributed): Text(attributed).font(T3Font.fixed(pointSize)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                case .code(let code, let language): CodeBlock(code: code, language: language, pointSize: max(12, pointSize - 3))
                }
            }
        }
        .task(id: RenderKey(text: text, streaming: streaming)) {
            guard !streaming else { return }
            let source = text
            let parsed = await Task.detached(priority: .userInitiated) { MarkdownBlock.parse(source) }.value
            guard !Task.isCancelled else { return }; blocks = parsed
        }
    }
}

enum MarkdownBlock: Sendable {
    case prose(AttributedString), code(String, String)
    static func parse(_ text: String) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = [], buffer: [String] = []
        var language: String?, fence: String?
        func appendProse() {
            let source = buffer.joined(separator: "\n")
            if !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let value = (try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(source)
                result.append(.prose(value))
            }
            buffer = []
        }
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if fence == nil && (trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")) {
                appendProse(); fence = String(trimmed.prefix(3)); language = String(trimmed.dropFirst(3))
            } else if let opening = fence, trimmed.hasPrefix(opening) {
                result.append(.code(buffer.joined(separator: "\n"), language ?? "")); buffer = []; fence = nil; language = nil
            } else { buffer.append(line) }
        }
        if fence != nil { result.append(.code(buffer.joined(separator: "\n"), language ?? "")) }
        else { appendProse() }
        return result
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
