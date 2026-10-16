import SwiftUI

struct ConnectionsScreen: View {
    @Bindable var store: AppStore
    let initialLink: String
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var name = ""
    @State private var code = ""
    @State private var removing: SavedHost?
    @State private var pairingError: String?
    @State private var removalError: String?
    @State private var removalNotice: String?

    var body: some View {
        NavigationStack {
            Form {
                if !store.hosts.isEmpty {
                    Section("Servers") {
                        ForEach(store.hosts) { host in
                            Button {
                                store.connect(host); dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(host.name).foregroundStyle(.primary)
                                        Text(host.origin.absoluteString).font(T3Font.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if store.activeHostID == host.id { Image(systemName: "checkmark").accessibilityLabel("Selected") }
                                }
                            }
                            .accessibilityValue(store.activeHostID == host.id ? "Selected" : "")
                            .swipeActions { Button("Remove", role: .destructive) { removing = host } }
                        }
                    }
                }
                if removalError != nil || removalNotice != nil {
                    Section {
                        if let removalError { Text(removalError).foregroundStyle(.red) }
                        if let removalNotice { Text(removalNotice).foregroundStyle(.secondary) }
                    }
                }
                Section {
                    TextField("Server name", text: $name).textContentType(.nickname)
                    TextField("Pairing link or server URL", text: $link, axis: .vertical)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .privacySensitive().accessibilityIdentifier("pairing-link")
                    SecureField("Pairing code, if separate", text: $code).textInputAutocapitalization(.never)
                    Button {
                        Task {
                            pairingError = nil
                            if await store.pair(link: link, code: code, name: name) { link = ""; code = ""; dismiss() }
                            else { pairingError = store.error; store.error = nil }
                        }
                    } label: {
                        HStack { Text(store.isPairing ? "Pairing…" : "Connect"); Spacer(); if store.isPairing { ProgressView() } }
                    }.disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isPairing)
                    if let pairingError { Text(pairingError).foregroundStyle(.red) }
                } header: { Text("Add a server") } footer: {
                    Text("In T3 Code on your computer, open Connections and create a pairing link. Direct LAN, Tailscale, and HTTPS server links are supported. T3 Connect account discovery is not available yet.")
                }
            }
            .disabled(store.removingHostID != nil)
            .navigationTitle("Connections").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(store.removingHostID != nil) } }
            .interactiveDismissDisabled(store.removingHostID != nil)
            .task { link = initialLink }
            .confirmationDialog("Remove this server, its credential, and unsent drafts?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Remove server", role: .destructive) {
                    guard let host = removing else { return }
                    removing = nil; removalError = nil; removalNotice = nil
                    Task {
                        do {
                            if try await store.removeHost(host) > 0 { removalNotice = "Older attachment drafts without server information were kept on this device." }
                        } catch { removalError = "Could not clear this server's attachment drafts. The server is still saved." }
                    }
                }
            }
        }
    }
}

struct AppearanceScreen: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("theme") private var themeID = "t3-code"
    @Environment(\.t3Theme) private var theme
    @AppStorage("messageSize") private var messageSize = 16.0
    @AppStorage("compactRows") private var compactRows = false
    @AppStorage("showReasoning") private var showReasoning = false

    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Appearance", selection: $appearance) {
                        Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                    }.pickerStyle(.menu).accessibilityIdentifier("appearance-choice")
                    Picker("Theme", selection: $themeID) { Text("T3 Code").tag("t3-code"); Text("T3 Chat").tag("t3-chat") }
                        .pickerStyle(.menu).accessibilityIdentifier("theme-choice")
                }
                Section("Conversations") {
                    HStack { Text("Text size"); Spacer(); Text("\(Int(messageSize)) pt").foregroundStyle(.secondary).monospacedDigit() }
                    Slider(value: $messageSize, in: 14...26, step: 1).accessibilityLabel("Conversation text size")
                    Text("The app is built. Let's look at the changes.")
                        .font(T3Font.fixed(messageSize)).padding(.vertical, 8)
                    Toggle("Compact spacing", isOn: $compactRows)
                    Toggle("Show reasoning", isOn: $showReasoning)
                }
                Section {
                    LabeledContent("Version", value: versionLabel)
                    Link("Source and upstream", destination: URL(string: "https://github.com/ahrsn/t3code/tree/feat/native-ios-client/apps/ios-native")!)
                }
            }
            .navigationTitle("Appearance").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct NewThreadScreen: View {
    @Bindable var store: AppStore
    var onCreate: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var projectID = ""
    @State private var title = ""
    @State private var modelID = ""
    @State private var instanceID = ""
    @State private var creating = false
    @State private var error: String?
    var catalog: ModelCatalog { ModelCatalog(config: store.config, projectID: projectID) }
    var providers: [JSONValue] { catalog.providers }
    var models: [JSONValue] { catalog.models(for: instanceID) }
    var selection: JSONValue { .object(["instanceId": .string(instanceID), "model": .string(modelID)]) }
    var body: some View {
        NavigationStack {
            Form {
                Picker("Project", selection: $projectID) {
                    Text("Choose a project").tag("")
                    ForEach(store.projects, id: \.id) { Text($0["title"].string).tag($0.id) }
                }
                TextField("Conversation title", text: $title)
                Section {
                    Picker("Provider", selection: $instanceID) {
                        Text("Choose a provider").tag("")
                        ForEach(providers, id: \.providerID) { provider in
                            Text(ModelCatalog.label(provider)).tag(provider["instanceId"].string)
                        }
                    }
                    Picker("Model", selection: $modelID) {
                        Text("Choose a model").tag("")
                        ForEach(models, id: \.modelID) { model in Text(model["name"].string).tag(model["slug"].string) }
                    }
                } header: { Text("Model") } footer: { Text("Uses the project's default model when available. New conversations request approval before agent actions.") }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("New conversation").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(creating ? "Creating…" : "Create") {
                        Task {
                            guard let project = store.shell.projects[projectID] else { return }
                            creating = true; defer { creating = false }
                            do {
                                let id = try await store.createThread(project: project, title: title, model: selection)
                                dismiss(); onCreate(id)
                            } catch { self.error = error.localizedDescription }
                        }
                    }.disabled(projectID.isEmpty || !catalog.canSelect(selection) || creating)
                }
            }
            .onChange(of: projectID) { _, id in
                let preferred = store.shell.projects[id]?["defaultModelSelection"] ?? store.config["settings"]["defaultModelSelection"]
                let model = catalog.defaultSelection(preferred: preferred)
                instanceID = model["instanceId"].string; modelID = model["model"].string
            }
            .onChange(of: instanceID) { _, _ in
                if !models.contains(where: { $0["slug"].string == modelID }) {
                    modelID = (models.first(where: { $0["isDefault"].bool }) ?? models.first)?["slug"].string ?? ""
                }
            }
        }
    }
}
