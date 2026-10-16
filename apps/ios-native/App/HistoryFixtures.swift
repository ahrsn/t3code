import Foundation

#if DEBUG
enum HistoryFixtures {
    static func items(_ range: Range<Int>) -> [JSONValue] {
        range.map { index in
            let tall = index == 16 && ProcessInfo.processInfo.arguments.contains("--history-tall-demo")
            let source = "History marker \(index)\n\n" + String(repeating: "This preview message gives the timeline a stable reading position. ", count: tall ? 24 : index % 3 + 1)
            return .object(["id": .string("history-\(index)"), "type": .string("assistant_message"), "text": .string(source)])
        }
    }
}
extension AppStore {
    func loadDemoHistory(beforeApplying: () -> Void) async -> Bool {
        guard let detail = conversation, let end = Int(detail.projection.historyCursor ?? "") else { return false }
        if end == 16 && detail.historyError == nil && ProcessInfo.processInfo.arguments.contains("--history-error-demo") {
            detail.historyError = "The server returned HTTP 503."
            return false
        }
        let start = max(0, end - 8)
        let page: JSONValue = .object([
            "items": .array(HistoryFixtures.items(start..<end)),
            "hasMoreHistory": .bool(start > 0), "nextCursor": start > 0 ? .string(String(start)) : .null
        ])
        let documents = await MarkdownDocuments.shared.documents(for: page["items"].array)
        guard conversation === detail else { return false }
        beforeApplying()
        detail.historyError = nil
        detail.historyDocuments.merge(documents) { _, new in new }
        detail.projection.prependHistory(page); detail.refreshRows()
        return true
    }
}
#endif
