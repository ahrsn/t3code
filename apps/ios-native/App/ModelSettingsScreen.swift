import SwiftUI

struct ModelSettingsScreen: View {
    @Bindable var store: AppStore
    let projectID: String
    let current: JSONValue
    let onSelect: (JSONValue?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var instanceID = ""
    @State private var modelID = ""
    @State private var options: [String: JSONValue] = [:]

    private var catalog: ModelCatalog { ModelCatalog(config: store.config, projectID: projectID) }
    private var selection: JSONValue { catalog.selection(instanceID: instanceID, modelID: modelID, options: options) }
    private var descriptors: [JSONValue] { catalog.model(for: selection)?["capabilities"]["optionDescriptors"].array ?? [] }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Provider", selection: $instanceID) {
                        if !catalog.providers.contains(where: { $0["instanceId"].string == instanceID }) {
                            Text(instanceID.isEmpty ? "Choose a provider" : "\(instanceID) · Unavailable").tag(instanceID)
                        }
                        ForEach(catalog.providers, id: \.providerID) { provider in
                            Text(ModelCatalog.label(provider)).tag(provider["instanceId"].string)
                        }
                    }.accessibilityIdentifier("conversation-provider")
                    Picker("Model", selection: $modelID) {
                        let models = catalog.models(for: instanceID, including: current["model"].string)
                        if !models.contains(where: { $0["slug"].string == modelID }) {
                            Text(modelID.isEmpty ? "Choose a model" : "\(modelID) · Unavailable").tag(modelID)
                        }
                        ForEach(models, id: \.modelID) { model in
                            Text(model["name"].string.isEmpty ? model["slug"].string : model["name"].string).tag(model["slug"].string)
                        }
                    }.accessibilityIdentifier("conversation-model")
                } footer: { Text("Applies to your next message. The current run keeps its settings.") }

                if !descriptors.isEmpty {
                    Section("Options") {
                        ForEach(descriptors, id: \.id) { descriptor in
                            Picker(descriptor["label"].string, selection: Binding(
                                get: { optionString(descriptor) },
                                set: { value in
                                    if value == "default" { options.removeValue(forKey: descriptor.id) }
                                    else if descriptor["type"].string == "boolean" { options[descriptor.id] = .bool(value == "true") }
                                    else { options[descriptor.id] = .string(String(value.dropFirst(7))) }
                                }
                            )) {
                                Text(defaultLabel(descriptor)).tag("default")
                                if descriptor["type"].string == "boolean" {
                                    Text("On").tag("true"); Text("Off").tag("false")
                                } else {
                                    ForEach(descriptor["options"].array, id: \.id) { choice in
                                        Text(choice["label"].string).tag("choice:\(choice.id)")
                                    }
                                }
                            }.accessibilityIdentifier("model-option-\(descriptor.id)")
                        }
                    }
                }
                if !catalog.canSelect(selection) {
                    Text("This model is unavailable for this project. Choose another model or update the provider in T3 Code on your Mac.")
                        .foregroundStyle(.secondary).font(T3Font.subheadline)
                }
                Section {
                    Button("Use conversation settings") { onSelect(nil); dismiss() }
                        .disabled(!store.canOperate && !store.isDemo)
                }
            }
            .navigationTitle("Model").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use model") { onSelect(selection); dismiss() }
                        .disabled(!catalog.canSelect(selection) || (!store.canOperate && !store.isDemo))
                }
            }
            .onChange(of: instanceID) { previous, _ in
                guard !previous.isEmpty else { return }
                options = [:]
                let candidates = catalog.models(for: instanceID)
                modelID = (candidates.first { $0["isDefault"].bool && !$0["isLegacy"].bool } ?? candidates.first)?["slug"].string ?? ""
            }
            .onChange(of: modelID) { previous, _ in if !previous.isEmpty { options = [:] } }
            .onAppear {
                instanceID = current["instanceId"].string
                modelID = current["model"].string
                options = ModelCatalog.optionValues(catalog.selection(instanceID: instanceID, modelID: modelID, options: ModelCatalog.optionValues(current)))
            }
        }
    }

    private func optionString(_ descriptor: JSONValue) -> String {
        guard let value = options[descriptor.id] else { return "default" }
        if descriptor["type"].string == "boolean" { return value.bool ? "true" : "false" }
        return "choice:\(value.string)"
    }
    private func defaultLabel(_ descriptor: JSONValue) -> String {
        let value = descriptor["currentValue"]
        if descriptor["type"].string == "boolean", !value.isNull { return "Default · \(value.bool ? "On" : "Off")" }
        let choice = descriptor["options"].array.first { $0["id"] == value } ?? descriptor["options"].array.first { $0["isDefault"].bool }
        return choice.map { "Default · \($0["label"].string)" } ?? "Default"
    }
}
