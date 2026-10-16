import Foundation

struct TimelineRow: Identifiable, Equatable, Sendable {
    let value: JSONValue
    var markdown: MarkdownDocument? = nil
    var id: String { value.id }
    var type: String { value["type"].string }
    var text: String {
        for key in ["text", "markdown", "message", "prompt", "input", "fileName", "pattern", "summary"] {
            if !value[key].string.isEmpty { return value[key].string }
        }
        return value["failure"]["message"].string
    }
    var createdAt: String { value["createdAt"].string }
    var isUser: Bool { type == "user_message" }
    var isMessage: Bool { ["user_message", "assistant_message"].contains(type) }
}

struct ThreadProjection: Sendable {
    var thread: JSONValue = .null
    var items: [String: JSONValue] = [:]
    var itemSources: [String: TurnItemTarget] = [:]
    var itemOrder: [String] = []
    var requests: [String: JSONValue] = [:]
    var runs: [String: JSONValue] = [:]
    var sequence = -1
    var hasSnapshot = false
    var hasMoreHistory = false
    var historyCursor: String?

    mutating func apply(_ stream: JSONValue) {
        if stream["kind"].string == "snapshot" {
            let projection = stream["projection"]
            thread = projection["thread"]
            items = [:]; itemOrder = []; itemSources = [:]
            let visible = projection["visibleTurnItems"].array
            // Visible rows include inherited history from forked provider threads.
            for wrapper in visible.sorted(by: { $0["position"].int < $1["position"].int }) {
                let item = wrapper["item"]
                if !item.id.isEmpty, items[item.id] == nil {
                    itemOrder.append(item.id); items[item.id] = item
                    itemSources[item.id] = TurnItemTarget(item: item, wrapper: wrapper, threadID: thread.id)
                }
            }
            if visible.isEmpty {
                for item in projection["turnItems"].array where !item.id.isEmpty && items[item.id] == nil {
                    itemOrder.append(item.id); items[item.id] = item
                }
            }
            // Older servers can expose messages without the corresponding timeline rows.
            if items.isEmpty {
                for message in projection["messages"].array {
                    var item = message
                    item["type"] = .string(message["role"].string == "user" ? "user_message" : "assistant_message")
                    itemOrder.append(item.id); items[item.id] = item
                }
            }
            requests = Dictionary(projection["runtimeRequests"].array.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            runs = Dictionary(projection["runs"].array.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            sequence = stream["snapshotSequence"].int
            hasSnapshot = true
            hasMoreHistory = stream["hasMoreHistory"].bool
            historyCursor = stream["historyCursor"].string.isEmpty ? nil : stream["historyCursor"].string
            return
        }
        guard stream["kind"].string == "event", hasSnapshot, stream["sequence"].int > sequence else { return }
        sequence = stream["sequence"].int
        let event = stream["event"], payload = event["payload"]
        switch event["type"].string {
        case "turn-item.updated":
            if !payload.id.isEmpty {
                if items[payload.id] == nil { itemOrder.append(payload.id) }
                items[payload.id] = payload
            }
        case "runtime-request.created", "runtime-request.updated": requests[payload.id] = payload
        case "run.created", "run.updated": runs[payload.id] = payload
        case let type where type.hasPrefix("thread."):
            if payload.id == thread.id { thread = payload }
        default: break // Additive upstream events still advance the resume sequence.
        }
    }

    mutating func prependHistory(_ page: JSONValue) {
        var earlier: [String] = []
        for wrapper in page["items"].array {
            let item = wrapper["item"].isNull ? wrapper : wrapper["item"]
            if !item.id.isEmpty, items[item.id] == nil {
                items[item.id] = item; earlier.append(item.id)
                itemSources[item.id] = TurnItemTarget(item: item, wrapper: wrapper, threadID: thread.id)
            }
        }
        itemOrder = earlier + itemOrder
        hasMoreHistory = page["hasMoreHistory"].bool
        historyCursor = page["nextCursor"].string.isEmpty ? nil : page["nextCursor"].string
    }

    var rows: [TimelineRow] {
        itemOrder.compactMap { items[$0].map { TimelineRow(value: $0) } }
    }
    func target(for itemID: String) -> TurnItemTarget? {
        guard let item = items[itemID] else { return nil }
        return itemSources[itemID] ?? TurnItemTarget(item: item, wrapper: .null, threadID: thread.id)
    }
    var pendingRequests: [JSONValue] { requests.values.filter { $0["status"].string == "pending" } }
}

struct ShellProjection: Sendable {
    var projects: [String: JSONValue] = [:]
    var threads: [String: JSONValue] = [:]
    var sequence = -1
    var hasSnapshot = false
    mutating func apply(_ item: JSONValue) {
        let kind = item["kind"].string
        if kind == "snapshot" {
            let snapshot = item["snapshot"]
            if !item["resolvedRepositoryIdentityRoots"].isNull {
                // Upstream enrichment frames contain only repository identity metadata.
                // They must not replace projects, threads, or the event resume cursor.
                let roots = Set(item["resolvedRepositoryIdentityRoots"].array.map(\.string))
                for incoming in snapshot["projects"].array {
                    guard var existing = projects[incoming.id], roots.contains(existing["workspaceRoot"].string),
                          existing["workspaceRoot"] == incoming["workspaceRoot"] else { continue }
                    existing["repositoryIdentity"] = incoming["repositoryIdentity"]
                    projects[incoming.id] = existing
                }
                return
            }
            projects = Dictionary(snapshot["projects"].array.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            threads = Dictionary(snapshot["threads"].array.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            sequence = snapshot["snapshotSequence"].int; hasSnapshot = true
            return
        }
        guard hasSnapshot, item["sequence"].int > sequence else { return }
        sequence = item["sequence"].int
        switch kind {
        case "project.updated": projects[item["project"].id] = item["project"]
        case "project.removed": projects.removeValue(forKey: item["projectId"].string)
        case "thread.updated":
            if item["location"].string == "archive" { threads.removeValue(forKey: item["thread"].id) }
            else { threads[item["thread"].id] = item["thread"] }
        case "thread.removed": threads.removeValue(forKey: item["threadId"].string)
        default: break
        }
    }
}
