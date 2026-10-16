import XCTest
@testable import T3Native

final class ModelCatalogTests: XCTestCase {
    private func config() throws -> JSONValue {
        try .decode(Data(#"""
        {"providers":[
          {"instanceId":"codex","driver":"codex","enabled":true,"installed":true,"auth":{"status":"authenticated"},"models":[
            {"slug":"sol","name":"Sol","isDefault":true,"capabilities":{"optionDescriptors":[
              {"id":"effort","type":"select","options":[{"id":"high"},{"id":"max"}]},
              {"id":"fastMode","type":"boolean"}]}},
            {"slug":"astra","name":"Astra"},{"slug":"custom","isCustom":true}]},
          {"instanceId":"other","driver":"fork-driver","enabled":true,"installed":true,"auth":{"status":"authenticated"},"models":[{"slug":"model"}]}],
         "settings":{"providerInstances":{"codex":{"driver":"codex"},"other":{"driver":"fork-driver"}},"projectSettingsOverrides":{}}}
        """#.utf8))
    }
    func testProjectOverrideWinsOverBothMachineFlags() throws {
        var source = try config()
        source["settings"]["providerInstances"]["codex"]["enabled"] = .bool(false)
        source["settings"]["providerInstances"]["codex"]["config"] = .object(["enabled": .bool(false)])
        var catalog = ModelCatalog(config: source, projectID: "p")
        XCTAssertEqual(catalog.providers.map(\.providerID), ["other"])
        source["settings"]["projectSettingsOverrides"]["p"]["providerInstances"]["codex"]["enabled"] = .bool(true)
        catalog = ModelCatalog(config: source, projectID: "p")
        XCTAssertEqual(catalog.providers.map(\.providerID), ["codex", "other"])
        source["settings"]["projectSettingsOverrides"]["p"]["providerInstances"]["other"]["enabled"] = .bool(false)
        XCTAssertEqual(ModelCatalog(config: source, projectID: "p").providers.map(\.providerID), ["codex"])
    }
    func testSignedOutMissingAndUpdateGatedModelsCannotBeSelected() throws {
        var source = try config()
        let selection: JSONValue = .object(["instanceId": .string("codex"), "model": .string("sol")])
        XCTAssertTrue(ModelCatalog(config: source, projectID: "p").canSelect(selection))
        var providers = source["providers"].array
        providers[0]["auth"]["status"] = .string("unauthenticated"); source["providers"] = .array(providers)
        XCTAssertFalse(ModelCatalog(config: source, projectID: "p").canSelect(selection))
        providers[0]["auth"]["status"] = .string("authenticated")
        providers[0]["installed"] = .bool(false); source["providers"] = .array(providers)
        XCTAssertFalse(ModelCatalog(config: source, projectID: "p").canSelect(selection))
        providers[0]["installed"] = .bool(true)
        providers[0]["updateRequiredModels"] = .array([.object(["slug": .string("sol")])]); source["providers"] = .array(providers)
        let catalog = ModelCatalog(config: source, projectID: "p")
        XCTAssertFalse(catalog.canSelect(selection))
        XCTAssertEqual(catalog.defaultSelection(preferred: selection)["model"].string, "astra")
    }
    func testHiddenModelsKeepCurrentSelectionAndCustomEntriesAndOrder() throws {
        var source = try config()
        source["settings"]["providerModelPreferences"]["codex"] = .object([
            "hiddenModels": .array([.string("sol"), .string("custom")]),
            "modelOrder": .array([.string("custom"), .string("astra"), .string("sol")])])
        let catalog = ModelCatalog(config: source, projectID: "p")
        XCTAssertEqual(catalog.models(for: "codex").map(\.modelID), ["custom", "astra"])
        XCTAssertEqual(catalog.models(for: "codex", including: "sol").map(\.modelID), ["custom", "astra", "sol"])
        XCTAssertTrue(catalog.canSelect(.object(["instanceId": .string("codex"), "model": .string("sol")])))
    }
    func testImplicitDefaultSkipsLegacyModels() throws {
        var source = try config()
        var providers = source["providers"].array
        var models = providers[0]["models"].array
        models[0]["isLegacy"] = .bool(true)
        providers[0]["models"] = .array(models); source["providers"] = .array(providers)
        let catalog = ModelCatalog(config: source, projectID: "p")
        let preferred: JSONValue = .object(["instanceId": .string("codex"), "model": .string("sol")])
        XCTAssertTrue(catalog.canSelect(preferred), "Legacy models remain explicitly selectable.")
        XCTAssertEqual(catalog.defaultSelection(preferred: preferred)["model"].string, "astra")
    }
    func testExplicitOptionsDropUnsupportedValuesAndKeepFalse() throws {
        let catalog = ModelCatalog(config: try config(), projectID: "p")
        let selected = catalog.selection(instanceID: "codex", modelID: "sol", options: ["effort": .string("max"), "fastMode": .bool(false), "unknown": .string("value")])
        XCTAssertEqual(ModelCatalog.optionValues(selected), ["effort": .string("max"), "fastMode": .bool(false)])
        XCTAssertTrue(catalog.selection(instanceID: "codex", modelID: "sol", options: ["effort": .string("removed"), "fastMode": .string("true")])["options"].isNull)
        XCTAssertTrue(catalog.selection(instanceID: "other", modelID: "model", options: ModelCatalog.optionValues(selected))["options"].isNull)
        XCTAssertEqual(ModelCatalog.optionValues(.object(["options": .object(["effort": .string("high")])])), ["effort": .string("high")])
    }
}
