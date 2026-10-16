import Foundation

struct TurnItemTarget: Equatable, Sendable {
    let threadID: String
    let itemID: String
    init(item: JSONValue, wrapper: JSONValue, threadID: String) {
        self.threadID = !wrapper["sourceThreadId"].string.isEmpty ? wrapper["sourceThreadId"].string :
            !item["threadId"].string.isEmpty ? item["threadId"].string : threadID
        itemID = wrapper["sourceItemId"].string.isEmpty ? item.id : wrapper["sourceItemId"].string
    }
    func payload(revision: String) -> JSONValue {
        .object(["threadId": .string(threadID), "itemId": .string(itemID), "revision": .string(revision)])
    }
    func validate(_ result: JSONValue, type: String) throws -> JSONValue {
        let item = result["item"]
        guard !item.isNull else { throw ClientError("Output is no longer available.") }
        guard item.id == itemID, item["type"].string == type,
              item["threadId"].string.isEmpty || item["threadId"].string == threadID else {
            throw ClientError("The server returned output for a different item.")
        }
        guard !item["outputOmitted"].bool else { throw ClientError("The server did not return the full output. Try again when the run finishes.") }
        return item
    }
}

struct ToolOutputDocument: Equatable, Sendable {
    struct Section: Equatable, Sendable {
        let title: String
        let text: String
        let truncated: Bool
    }
    let sections: [Section]
    let status: String
    let failed: Bool
    static func needsFetch(_ item: JSONValue) -> Bool {
        item["outputOmitted"].bool || (item["input"]["truncated"].bool && !item["input"]["summary"].isNull)
    }
    static func isLive(_ item: JSONValue) -> Bool { ["idle", "pending", "running", "waiting"].contains(item["status"].string) }
    static func requestIdentity(_ item: JSONValue) -> JSONValue {
        guard needsFetch(item), isLive(item) else { return item }
        // Fetch once while active, then again on completion. Output streaming has
        // its own upstream subscription; timeline metadata is not a polling clock.
        return .object(["id": item["id"], "type": item["type"], "input": item["input"], "status": .string("live"), "outputOmitted": item["outputOmitted"]])
    }
}

actor ToolDocuments {
    static let shared = ToolDocuments()
    static let maximumTextBytes = 32 * 1024

    func document(for item: JSONValue) -> ToolOutputDocument {
        var sections: [ToolOutputDocument.Section] = []
        for (key, title) in [("input", item["type"].string == "command_execution" ? "Command" : "Input"), ("output", "Output")] {
            guard !item[key].isNull else { continue }
            var budget = TextBudget()
            let text: String
            if case .string(let value) = item[key] { text = budget.text(value) }
            else {
                let bounded = budget.value(item[key], depth: 0)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                text = (try? String(decoding: encoder.encode(bounded), as: UTF8.self)) ?? ""
            }
            var display = TextBudget()
            let visible = display.text(text)
            if !visible.isEmpty {
                let abbreviated = key == "output" ? item["outputOmitted"].bool : item["input"]["truncated"].bool
                sections.append(.init(title: title, text: visible, truncated: budget.truncated || display.truncated || abbreviated))
            }
        }
        let exit = item["exitCode"]
        let failed = item["status"].string == "failed" || item["outputIndicatesFailure"].bool || (!exit.isNull && exit.int != 0) || item["output"]["isError"].bool || item["output"]["is_error"].bool
        let status = !exit.isNull ? "Exit \(exit.int)" : failed ? "Failed" : item["status"].string.capitalized
        return ToolOutputDocument(sections: sections, status: status, failed: failed)
    }

    private struct TextBudget {
        var remaining = ToolDocuments.maximumTextBytes
        var nodes = 256
        var truncated = false
        mutating func text(_ string: String) -> String {
            var bytes = Array(string.utf8.prefix(remaining + 1))
            let cut = bytes.count > remaining
            if cut { bytes.removeLast(); truncated = true }
            remaining -= bytes.count
            while !bytes.isEmpty, String(bytes: bytes, encoding: .utf8) == nil { bytes.removeLast() }
            var result = String(decoding: bytes, as: UTF8.self)
            if cut, !result.isEmpty { result.removeLast() }
            return result
        }
        mutating func value(_ value: JSONValue, depth: Int) -> JSONValue {
            guard nodes > 0, remaining > 0, depth < 12 else { truncated = true; return .string("…") }
            nodes -= 1
            switch value {
            case .string(let string): return .string(text(string))
            case .array(let values):
                var result: [JSONValue] = []
                for element in values {
                    guard nodes > 0, remaining > 0 else { truncated = true; result.append(.string("…")); break }
                    result.append(self.value(element, depth: depth + 1))
                }
                return .array(result)
            case .object(let fields):
                // Binary payloads are not useful code text and can dwarf the timeline.
                if ["image", "audio"].contains(fields["type"]?.string ?? "") {
                    truncated = true
                    return .object(["type": fields["type"] ?? .null, "mimeType": .string(text(fields["mimeType"]?.string ?? "")),
                                    "content": .string("Binary result; inline viewing is not available.")])
                }
                var result: [String: JSONValue] = [:]
                let entries = fields.prefix(nodes).sorted { $0.key < $1.key }
                if entries.count < fields.count { truncated = true; result["…"] = .string("Additional fields not shown") }
                for (key, value) in entries {
                    guard nodes > 0, remaining > 0 else { truncated = true; result["…"] = .string("Additional fields not shown"); break }
                    let name = text(key)
                    result[name] = self.value(value, depth: depth + 1)
                }
                return .object(result)
            default: return value
            }
        }
    }
}
