import Foundation

/// Mirrors the upstream inbox's lifecycle precedence and stable arrangement.
struct ThreadIndex {
    var pinned: [JSONValue] = []
    var working: [JSONValue] = []
    var snoozed: [JSONValue] = []
    var settled: [JSONValue] = []
    var matches: [JSONValue] = []
    init(threads: [JSONValue], projectID: String = "", search: String = "", now: Date = .now) {
        for t in threads {
            guard t["deletedAt"].isNull, t["archivedAt"].isNull,
                  t["lineage"]["relationshipToParent"].string != "subagent",
                  projectID.isEmpty || t["projectId"].string == projectID,
                  search.isEmpty || t["title"].string.localizedCaseInsensitiveContains(search) || t["latestVisibleMessage"]["text"].string.localizedCaseInsensitiveContains(search) else { continue }
            matches.append(t)
            if Self.isSnoozed(t, now: now) { snoozed.append(t) }
            else if t["settledOverride"].string == "settled" { settled.append(t) }
            else if !t["pinnedAt"].isNull { pinned.append(t) }
            else { working.append(t) }
        }
        pinned = Self.ordered(pinned, key: "pinOrderKey", keyedFirst: true)
        working = Self.ordered(working, key: "activeOrderKey", keyedFirst: false)
        snoozed = Self.sortedByTime(snoozed, ascending: true) { Self.time($0["snoozedUntil"].string) }
        settled = Self.sortedByTime(settled, ascending: false) { Self.ended($0) }
        matches.sort { $0["updatedAt"].string == $1["updatedAt"].string ? $0.id < $1.id : $0["updatedAt"].string > $1["updatedAt"].string }
    }
    private static func sortedByTime(_ rows: [JSONValue], ascending: Bool, timestamp: (JSONValue) -> Double) -> [JSONValue] {
        let decorated: [(row: JSONValue, timestamp: Double)] = rows.map { (row: $0, timestamp: timestamp($0)) }
        let ordered = decorated.sorted { a, b in
            if a.timestamp == b.timestamp { return a.row.id < b.row.id }
            return ascending ? a.timestamp < b.timestamp : a.timestamp > b.timestamp
        }
        return ordered.map { $0.row }
    }
    private static func isSnoozed(_ t: JSONValue, now: Date) -> Bool {
        guard time(t["snoozedUntil"].string) > now.timeIntervalSince1970 else { return false }
        if !t["pendingRuntimeRequest"].isNull { return false }
        let since = time(t["snoozedAt"].string)
        if t["status"].string == "failed", t["snoozedAt"].isNull || time(t["updatedAt"].string) > since { return false }
        if !t["snoozedAt"].isNull, time(t["latestRunCompletedAt"].string) > since { return false }
        return true
    }
    private static func ordered(_ rows: [JSONValue], key: String, keyedFirst: Bool) -> [JSONValue] {
        rows.map { (row: $0, key: $0[key].string, anchor: anchor($0, pinned: keyedFirst)) }.sorted { a, b in
            if a.key.isEmpty != b.key.isEmpty { return keyedFirst ? !a.key.isEmpty : a.key.isEmpty }
            if !a.key.isEmpty { return a.key == b.key ? a.row.id < b.row.id : a.key < b.key }
            return a.anchor == b.anchor ? a.row.id < b.row.id : a.anchor > b.anchor
        }.map(\.row)
    }
    private static func anchor(_ t: JSONValue, pinned: Bool) -> Double {
        let created = time(t["createdAt"].string)
        return pinned ? created : max(created, time(t["unsettledAt"].string))
    }
    private static func ended(_ t: JSONValue) -> Double {
        if !t["settledAt"].isNull { return time(t["settledAt"].string) }
        return max(time(t["updatedAt"].string), time(t["latestUserMessageAt"].string), time(t["latestRunCompletedAt"].string))
    }
    private static func time(_ text: String) -> Double {
        let date = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text)) ?? (try? Date.ISO8601FormatStyle().parse(text))
        return date?.timeIntervalSince1970 ?? 0
    }
}
