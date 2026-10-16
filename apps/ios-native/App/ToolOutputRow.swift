import SwiftUI

struct ToolOutputRow: View {
    let item: JSONValue
    let contextID: String
    let pointSize: Double
    let load: ((JSONValue) async throws -> JSONValue)?
    @State private var expanded = false
    @State private var revision = 0
    @State private var presentation: Presentation?
    private struct Request: Equatable {
        let context: String
        let item: JSONValue
        let expanded: Bool
        let revision: Int
    }
    private struct Presentation {
        let request: Request
        let document: ToolOutputDocument?
        let error: String?
        let loading: Bool
    }
    private var request: Request { Request(context: contextID, item: ToolOutputDocument.requestIdentity(item), expanded: expanded, revision: revision) }
    private var title: String {
        if !item["title"].string.isEmpty { return item["title"].string }
        if !item["toolName"].string.isEmpty { return item["toolName"].string }
        return item["type"].string == "command_execution" ? "Command" : "Tool"
    }
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                if let presentation, presentation.request == request {
                    if let document = presentation.document {
                        if !document.status.isEmpty {
                            Text(ToolOutputDocument.isLive(item) && !document.status.hasPrefix("Exit ") ? item["status"].string.capitalized : document.status)
                                .font(T3Font.caption).foregroundStyle(document.failed ? .red : .secondary)
                        }
                        ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                            CodeBlock(code: section.text, language: section.title, pointSize: max(12, pointSize * 0.85), maximumTextHeight: 260)
                            if section.truncated {
                                Text("Showing a shortened result. Copy includes only the displayed portion.")
                                    .font(T3Font.caption).foregroundStyle(.secondary)
                            }
                        }
                        if document.sections.isEmpty && !presentation.loading && presentation.error == nil { Text("No output.").font(T3Font.caption).foregroundStyle(.secondary) }
                    }
                    if presentation.loading { ProgressView("Loading output").font(T3Font.caption) }
                    if let error = presentation.error {
                        Text(error).font(T3Font.subheadline).textSelection(.enabled)
                        Button("Retry output") { revision += 1 }.font(T3Font.subheadline).buttonStyle(.borderless)
                    }
                    if ToolOutputDocument.isLive(item), ToolOutputDocument.needsFetch(item), !presentation.loading, presentation.error == nil {
                        Button("Refresh output") { revision += 1 }.font(T3Font.subheadline).buttonStyle(.borderless)
                    }
                } else { ProgressView("Loading output").font(T3Font.caption) }
            }.padding(.top, 8)
        } label: {
            Label(title, systemImage: item["type"].string == "command_execution" ? "terminal" : "chevron.left.forwardslash.chevron.right")
                .font(T3Font.subheadline).foregroundStyle(item["status"].string == "failed" ? .red : .secondary).lineLimit(2)
        }
        .accessibilityIdentifier("tool-" + item.id)
        .task(id: request) {
            let current = request
            presentation = nil
            guard expanded else { return }
            let base = await ToolDocuments.shared.document(for: item)
            guard !Task.isCancelled else { return }
            do {
                let full: JSONValue
                if ToolOutputDocument.needsFetch(item) {
                    guard let load else { throw ClientError("Output cannot be loaded from this view.") }
                    presentation = Presentation(request: current, document: base, error: nil, loading: true)
                    full = try await load(item)
                } else { full = item }
                let document = await ToolDocuments.shared.document(for: full)
                try Task.checkCancellation()
                presentation = Presentation(request: current, document: document, error: nil, loading: false)
            } catch {
                if !Task.isCancelled { presentation = Presentation(request: current, document: base, error: error.localizedDescription, loading: false) }
            }
        }
    }
}
