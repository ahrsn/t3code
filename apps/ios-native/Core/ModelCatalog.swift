import Foundation

/// The catalog is scoped to the thread's project, including provider overrides.
struct ModelCatalog {
    let config: JSONValue
    let projectID: String

    var providers: [JSONValue] {
        config["providers"].array.filter { provider in
            return enabled(provider) && provider["installed"].bool &&
                provider["auth"]["status"].string != "unauthenticated" &&
                !(provider["driver"].string == "antigravity" && provider["availability"].string == "unavailable") &&
                !provider["models"].array.isEmpty
        }
    }

    func enabled(_ provider: JSONValue) -> Bool {
        let settings = config["settings"]
        guard !settings.isNull else { return provider["enabled"].bool }
        let id = provider["instanceId"].string
        let override = settings["projectSettingsOverrides"][projectID]["providerInstances"][id]["enabled"]
        if !override.isNull { return override.bool }
        let instance = settings["providerInstances"][id]
        guard !instance.isNull else { return ["codex", "claudeAgent"].contains(id) }
        if instance["enabled"] == .bool(false) || instance["config"]["enabled"] == .bool(false) { return false }
        if !instance["enabled"].isNull { return instance["enabled"].bool }
        if !instance["config"]["enabled"].isNull { return instance["config"]["enabled"].bool }
        return !["cursor", "grok", "muse", "pi", "opencode", "antigravity"].contains(instance["driver"].string)
    }

    func models(for instanceID: String, including current: String = "") -> [JSONValue] {
        let provider = config["providers"].array.first { $0["instanceId"].string == instanceID }
        let preferences = config["settings"]["providerModelPreferences"][instanceID]
        let hidden = Set(preferences["hiddenModels"].array.map(\.string))
        let order = preferences["modelOrder"].array.map(\.string)
        return (provider?["models"].array ?? []).enumerated().filter { _, model in
            model["isCustom"].bool || model["slug"].string == current || !hidden.contains(model["slug"].string)
        }.sorted { lhs, rhs in
            let a = order.firstIndex(of: lhs.element["slug"].string) ?? Int.max
            let b = order.firstIndex(of: rhs.element["slug"].string) ?? Int.max
            return a == b ? lhs.offset < rhs.offset : a < b
        }.map(\.element)
    }

    func model(for selection: JSONValue) -> JSONValue? {
        models(for: selection["instanceId"].string, including: selection["model"].string).first { $0["slug"] == selection["model"] }
    }

    func canSelect(_ selection: JSONValue) -> Bool {
        guard let provider = providers.first(where: { $0["instanceId"] == selection["instanceId"] }), model(for: selection) != nil else { return false }
        return !provider["updateRequiredModels"].array.contains { $0["slug"] == selection["model"] }
    }

    func defaultSelection(preferred: JSONValue = .null) -> JSONValue {
        let preferredProvider = config["providers"].array.first { $0["instanceId"] == preferred["instanceId"] }
        if canSelect(preferred), preferredProvider?["driver"].string == "antigravity" || model(for: preferred)?["isLegacy"].bool != true { return preferred }
        for provider in providers {
            let models = models(for: provider["instanceId"].string).filter { model in
                !model["isLegacy"].bool && !provider["updateRequiredModels"].array.contains { $0["slug"] == model["slug"] }
            }
            if let model = models.first(where: { $0["isDefault"].bool }) ?? models.first {
                return .object(["instanceId": provider["instanceId"], "model": model["slug"]])
            }
        }
        return .null
    }

    static func label(_ provider: JSONValue) -> String {
        provider["displayName"].string.isEmpty ? provider["driver"].string.capitalized : provider["displayName"].string
    }

    static func optionValues(_ selection: JSONValue) -> [String: JSONValue] {
        if case .object(let values) = selection["options"] { return values }
        return selection["options"].array.reduce(into: [:]) { $0[$1.id] = $1["value"] }
    }

    /// Keep explicit choices only when the selected model advertises them.
    func selection(instanceID: String, modelID: String, options: [String: JSONValue]) -> JSONValue {
        var selection: JSONValue = .object(["instanceId": .string(instanceID), "model": .string(modelID)])
        let descriptors = model(for: selection)?["capabilities"]["optionDescriptors"].array ?? []
        let explicit: [JSONValue] = descriptors.compactMap { descriptor in
            guard let value = options[descriptor.id] else { return nil }
            let valid: Bool
            switch descriptor["type"].string {
            case "boolean": if case .bool = value { valid = true } else { valid = false }
            case "select": valid = descriptor["options"].array.contains { $0["id"] == value }
            default: valid = false
            }
            return valid ? .object(["id": descriptor["id"], "value": value]) : nil
        }
        if !explicit.isEmpty { selection["options"] = .array(explicit) }
        return selection
    }
}
