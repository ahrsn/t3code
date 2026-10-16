import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct ConversationScreen: View {
    @Bindable var store: AppStore
    let threadID: String
    @Environment(\.t3Theme) private var theme
    @State private var draft = ""
    @State private var showAppearance = false
    @State private var showModelSettings = false
    @State private var draftModel: JSONValue?
    @State private var viewport = TimelineViewport()
    @State private var previewRequest: AttachmentPreviewRequest?
    @State private var attachmentDraft = ComposerAttachmentDraft()
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photoImportKey = ""
    @State private var photoImportLimits = AttachmentLimits(uploads: false, fileMaximum: nil)
    @State private var importKey = ""
    @State private var importLimits = AttachmentLimits(uploads: false, fileMaximum: nil)
    @FocusState private var focused: Bool
    @AppStorage("showReasoning") private var showReasoning = false
    @AppStorage("compactRows") private var compactRows = false
    @AppStorage("messageSize") private var messageSize = 16.0
    var thread: JSONValue { store.shell.threads[threadID] ?? store.conversation?.projection.thread ?? .null }
    var draftKey: String { "draft.\(store.activeHostID?.uuidString ?? "none").\(threadID)" }
    var attachmentKey: String { draftKey + (store.isDemo ? ".preview-attachments" : ".attachments") }

    var selectedModel: JSONValue { draftModel ?? thread["modelSelection"] }

    var body: some View {
        Group {
            if let detail = store.conversation, detail.id == threadID {
                timeline(detail)
            } else {
                ProgressView("Loading conversation")
            }
        }
        .background(theme.canvas)
        .navigationTitle(thread["title"].string.isEmpty ? "Thread" : thread["title"].string)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(thread["title"].string.isEmpty ? "Thread" : thread["title"].string)
                        .font(T3Font.scaled(14, weight: .medium)).lineLimit(1)
                    if let project = store.shell.projects[thread["projectId"].string] {
                        Text(project["title"].string).font(T3Font.caption).foregroundStyle(theme.muted).lineLimit(1)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Text and appearance", systemImage: "textformat.size") { showAppearance = true }
                    Button("Reconnect", systemImage: "arrow.clockwise") { store.retry() }
                    Button("Stop agent", systemImage: "stop.fill", role: .destructive) { Task { await store.stop(threadID) } }.disabled(!store.canOperate)
                } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Conversation actions")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .sheet(isPresented: $showAppearance) { AppearanceScreen().environment(\.t3Theme, theme) }
        .sheet(isPresented: $showModelSettings) {
            ModelSettingsScreen(store: store, projectID: thread["projectId"].string, current: selectedModel) { draftModel = $0 }
                .environment(\.t3Theme, theme)
        }
        .sheet(item: $previewRequest) { request in
            AttachmentPreviewScreen(request: request, store: store).environment(\.t3Theme, theme)
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                let key = importKey, limits = importLimits
                Task { await attachmentDraft.add(urls, limits: limits, expectedKey: key) }
            case .failure(let error): attachmentDraft.error = error.localizedDescription
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotos,
                      maxSelectionCount: max(1, 100 - attachmentDraft.items.count), selectionBehavior: .ordered,
                      matching: .images, preferredItemEncoding: .compatible)
        .task(id: selectedPhotos) {
            guard !selectedPhotos.isEmpty else { return }
            await attachmentDraft.addPhotos(selectedPhotos, limits: photoImportLimits, expectedKey: photoImportKey)
            selectedPhotos = []
        }
        .onChange(of: store.activeHostID) { _, _ in previewRequest = nil; showFileImporter = false; showPhotoPicker = false; selectedPhotos = [] }
        .task(id: draftKey) {
            draft = UserDefaults.standard.string(forKey: draftKey) ?? ""
            draftModel = UserDefaults.standard.data(forKey: draftKey + ".model").flatMap { try? JSONValue.decode($0) }
            viewport.frames.removeAll()
            await attachmentDraft.load(key: attachmentKey)
            #if DEBUG
            if store.isDemo && (ProcessInfo.processInfo.arguments.contains("--reset-demo-attachments") || ProcessInfo.processInfo.arguments.contains("--reset-demo-draft")) {
                for item in attachmentDraft.items { await attachmentDraft.remove(item) }
            }
            #endif
            await store.selectThread(threadID)
        }
        .onChange(of: draft) { _, value in UserDefaults.standard.set(value, forKey: draftKey) }
        .onChange(of: store.lastConfirmedSend) { _, confirmation in
            guard let confirmation, confirmation.draftKey == attachmentKey else { return }
            if draft == confirmation.text { draft = "" }
            let key = attachmentKey
            Task { await attachmentDraft.refresh(key: key) }
        }
        .onChange(of: draftModel) { _, value in
            if let value, let data = try? value.data() { UserDefaults.standard.set(data, forKey: draftKey + ".model") }
            else { UserDefaults.standard.removeObject(forKey: draftKey + ".model") }
        }
        .onDisappear { selectedPhotos = []; Task { await store.closeConversation(expectedID: threadID) } }
    }

    private func timeline(_ detail: Conversation) -> some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: compactRows ? 12 : 24) {
                    if !store.connected || store.isDemo {
                        Label(store.isDemo ? "Preview data" : "Offline. Your draft is saved.", systemImage: store.isDemo ? "eye" : "wifi.slash")
                            .font(T3Font.caption).foregroundStyle(theme.muted)
                    }
                    if let error = detail.error {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error).foregroundStyle(.red)
                            Button("Retry conversation") { Task { await store.selectThread(threadID) } }
                        }
                    }
                    if detail.projection.hasMoreHistory {
                        Button(detail.loadingHistory ? "Loading…" : detail.historyError == nil ? "Load earlier messages" : "Retry earlier messages") {
                            Task {
                                let firstID = detail.rows.first?.id
                                let loaded = await store.loadHistory(expectedID: threadID) { viewport.pendingAnchor = viewport.readingAnchor() }
                                if !loaded || detail.rows.first?.id == firstID { viewport.pendingAnchor = nil }
                            }
                        }
                            .disabled(detail.loadingHistory).font(T3Font.caption).frame(maxWidth: .infinity)
                        if let error = detail.historyError { Text(error).font(T3Font.caption).foregroundStyle(.red) }
                    }
                    ForEach(detail.rows.filter { showReasoning || $0.type != "reasoning" }) { row in
                        VStack(alignment: .leading, spacing: 0) {
                            Color.clear.frame(height: 1).id(TimelineViewport.anchorID(row.id))
                            if row.type == "approval_request" || row.type == "user_input_request" {
                                if let request = detail.projection.requests[row.value["requestId"].string] {
                                    RequestRow(row: row, request: request, store: store, threadID: threadID)
                                }
                            } else {
                                TimelineRowView(row: row, pointSize: messageSize) { attachment in
                                    previewRequest = AttachmentPreviewRequest(attachment: attachment, hostID: store.activeHostID)
                                }.equatable()
                            }
                        }
                        .id(row.id)
                        .onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: .named("conversation-viewport"))
                        } action: { viewport.frames[row.id] = $0 }
                        .onDisappear { viewport.frames.removeValue(forKey: row.id) }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding(.horizontal, 20).padding(.vertical, 18)
            }
            .coordinateSpace(name: "conversation-viewport")
            .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height } action: { _, height in viewport.height = height }
            .onChange(of: detail.rows.first?.id) { _, _ in
                guard let anchor = viewport.pendingAnchor else { return }
                viewport.pendingAnchor = nil
                reader.scrollTo(anchor.id, anchor: anchor.point)
            }
            .accessibilityIdentifier("conversation-timeline")
            .background(theme.canvas).scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .overlay {
                if !detail.projection.hasSnapshot && detail.error == nil { ProgressView("Loading conversation") }
                else if detail.rows.isEmpty && detail.projection.hasSnapshot { ContentUnavailableView("Start a conversation", systemImage: "bubble.left") }
            }
            .overlay(alignment: .bottomTrailing) {
                Button { focused = false; reader.scrollTo("bottom", anchor: .bottom) } label: {
                    Image(systemName: "arrow.down").frame(width: 36, height: 36)
                }.buttonStyle(.glass).accessibilityLabel("Jump to latest message").padding(12)
            }
            .task(id: detail.projection.hasSnapshot) {
                guard detail.projection.hasSnapshot else { return }
                // Snapshot rows arrive after the initial empty layout. Position once,
                // leaving subsequent streaming updates and history browsing alone.
                await Task.yield()
                reader.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = attachmentDraft.error {
                HStack(alignment: .top) {
                    Text(error).font(T3Font.caption).foregroundStyle(.red)
                    Spacer(minLength: 8)
                    Button { attachmentDraft.error = nil } label: { Image(systemName: "xmark") }.accessibilityLabel("Dismiss attachment error")
                }.padding(.horizontal, 4)
            }
            if !thread["activeRunId"].isNull {
                HStack {
                    Label("Working", systemImage: "circle.dashed").font(T3Font.caption).foregroundStyle(theme.muted)
                    Spacer()
                    Button("Stop", systemImage: "stop.fill") { Task { await store.stop(threadID) } }
                        .font(T3Font.caption).disabled(!store.canOperate)
                }.padding(.horizontal, 4)
            }
            VStack(alignment: .leading, spacing: 12) {
                if !attachmentDraft.items.isEmpty { ComposerAttachmentChips(draft: attachmentDraft, disabled: store.sending || attachmentDraft.busy) }
                if store.uploadDraftKey == attachmentKey, let name = store.uploadingName {
                    HStack(spacing: 8) {
                        ProgressView(value: store.uploadFraction).frame(width: 36)
                        Text("Uploading \(name)").font(T3Font.caption).lineLimit(1)
                        Spacer(minLength: 0)
                        Button("Cancel") { cancelUpload() }.font(T3Font.caption).accessibilityLabel("Cancel upload")
                    }
                } else if attachmentDraft.busy { ProgressView("Attaching…").font(T3Font.caption) }
                HStack(alignment: .bottom, spacing: 12) {
                    TextField("Ask anything…", text: $draft, axis: .vertical)
                        .lineLimit(1...7).font(T3Font.body).focused($focused)
                        .accessibilityLabel("Message").accessibilityIdentifier("message-input")
                    Button {
                        let submitted = draft
                        let submittedModel = draftModel
                        let key = attachmentKey, textKey = draftKey, files = attachmentDraft.items
                        store.composerSendTask = Task {
                            let sent = await store.send(text: submitted, threadID: threadID, model: submittedModel, attachments: files, draftKey: key)
                            if sent, UserDefaults.standard.string(forKey: textKey) == submitted { UserDefaults.standard.removeObject(forKey: textKey) }
                            if sent, attachmentKey == key, draft == submitted { draft = "" }
                            await attachmentDraft.refresh(key: key)
                            store.composerSendTask = nil
                        }
                    } label: {
                        Image(systemName: store.sending ? "ellipsis" : "arrow.up")
                            .font(.system(size: 15, weight: .semibold)).frame(width: 34, height: 34)
                    }.buttonStyle(.glassProminent).buttonBorderShape(.circle)
                        .disabled(!store.canOperate || (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachmentDraft.items.isEmpty) || store.sending || store.composerSendTask != nil || attachmentDraft.busy)
                        .accessibilityLabel("Send message").accessibilityIdentifier("send-message")
                }
                HStack(spacing: 8) {
                    Menu {
                        Button("Choose photos", systemImage: "photo") {
                            focused = false; photoImportKey = attachmentKey; photoImportLimits = AttachmentLimits(config: store.config); showPhotoPicker = true
                        }.disabled(attachmentDraft.items.count >= 100)
                        Button("Choose files", systemImage: "folder") {
                            focused = false; importKey = attachmentKey; importLimits = AttachmentLimits(config: store.config); showFileImporter = true
                        }
                        #if DEBUG
                        if store.isDemo && ProcessInfo.processInfo.arguments.contains("--attachment-draft-demo") {
                            Button("Sample text", systemImage: "doc.text") { Task { await addFixture(image: false) } }
                            Button("Sample image", systemImage: "photo") { Task { await addFixture(image: true) } }
                            Button("Empty sample", systemImage: "doc") { Task { await addFixture(image: false, empty: true) } }
                        }
                        #endif
                    } label: { Image(systemName: "paperclip").frame(width: 28, height: 28) }
                        .accessibilityLabel("Attach files").accessibilityIdentifier("attach-files")
                        .disabled((!store.canOperate && !store.isDemo) || !AttachmentLimits(config: store.config).uploads || store.sending || attachmentDraft.busy || attachmentDraft.key != attachmentKey)
                    Button { focused = false; showModelSettings = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkle").font(.system(size: 12))
                            Text(modelName.isEmpty ? "Choose model" : modelName).font(T3Font.caption).lineLimit(1)
                            Image(systemName: "chevron.down").font(.system(size: 9))
                        }.padding(.vertical, 4).contentShape(.rect)
                    }.buttonStyle(.plain).accessibilityLabel("Model settings")
                        .accessibilityValue(modelName).accessibilityIdentifier("model-settings")
                    Spacer(minLength: 0)
                    if !thread["runtimeMode"].string.isEmpty {
                        Label(thread["runtimeMode"].string == "full-access" ? "Full access" : "Approvals", systemImage: "lock.open")
                            .font(T3Font.caption)
                    }
                }.foregroundStyle(theme.muted)
            }.padding(14)
                .background(theme.surface, in: .rect(cornerRadius: 24))
                .overlay { RoundedRectangle(cornerRadius: 24).stroke(theme.border, lineWidth: 1) }
        }.padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
        .background { theme.canvas.opacity(0.96).ignoresSafeArea(edges: .bottom) }
    }
    private func cancelUpload() {
        store.composerSendTask?.cancel()
        #if DEBUG
        if store.isDemo { store.sending = false; store.uploadingName = nil; store.uploadDraftKey = nil }
        #endif
    }
    #if DEBUG
    private func addFixture(image: Bool, empty: Bool = false) async {
        do {
            let file = try AttachmentDraftFixtures.file(image: image, empty: empty)
            await attachmentDraft.add([file.url], limits: AttachmentLimits(config: store.config))
            withExtendedLifetime(file) {}
        } catch { attachmentDraft.error = error.localizedDescription }
    }
    #endif
    private var modelName: String {
        let selection = selectedModel
        let provider = store.config["providers"].array.first { $0["instanceId"] == selection["instanceId"] }
        let model = provider?["models"].array.first { $0["slug"] == selection["model"] }
        return model?["name"].string ?? selection["model"].string
    }
}

struct TimelineRowView: View, Equatable {
    let row: TimelineRow
    let pointSize: Double
    let openAttachment: (AttachmentReference) -> Void
    @Environment(\.t3Theme) private var theme
    @ScaledMetric(relativeTo: .body) private var dynamicScale = 1.0
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.row == rhs.row && lhs.pointSize == rhs.pointSize }
    var body: some View {
        if row.isMessage {
            VStack(alignment: .leading, spacing: 8) {
                NativeMarkdown(text: row.text, pointSize: pointSize * dynamicScale, streaming: row.value["streaming"].bool, preformatted: row.markdown)
                AttachmentLinks(attachments: row.value["attachments"].array, open: openAttachment)
            }
            .padding(row.isUser ? 14 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(row.isUser ? theme.color("messageForeground") : theme.text)
            .background(row.isUser ? theme.color("messageSurface") : .clear, in: .rect(cornerRadius: 18))
            .textSelection(.enabled)
        } else if row.type == "proposed_plan" {
            DisclosureGroup("Proposed plan") { NativeMarkdown(text: row.text, pointSize: pointSize * dynamicScale, streaming: row.value["streaming"].bool, preformatted: row.markdown) }
        } else if row.type == "todo_list" {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(row.value["steps"].array, id: \.id) { step in
                    Label(step["text"].string, systemImage: step["status"].string == "completed" ? "checkmark.circle.fill" : "circle")
                        .font(T3Font.subheadline).foregroundStyle(step["status"].string == "completed" ? .secondary : .primary)
                }
            }
        } else {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    Text(row.text).textSelection(.enabled)
                    if !row.value["output"].string.isEmpty { CodeBlock(code: row.value["output"].string, language: "Output", pointSize: 13) }
                    if !row.value["diffStr"].string.isEmpty { CodeBlock(code: row.value["diffStr"].string, language: "Diff", pointSize: 13) }
                    if row.value["outputOmitted"].bool { Text("Full output is available in the desktop app.").font(T3Font.caption).foregroundStyle(.secondary) }
                }.font(T3Font.subheadline).padding(.top, 8)
            } label: {
                Label(row.value["title"].string.isEmpty ? itemTitle : row.value["title"].string, systemImage: itemIcon)
                    .font(T3Font.subheadline).foregroundStyle(row.type == "error" ? .red : .secondary).lineLimit(2)
            }
        }
    }
    private var itemTitle: String {
        switch row.type {
        case "command_execution": "Command"
        case "file_change": row.value["fileName"].string
        case "reasoning": "Reasoning"
        case "file_search": "Search files"
        case "web_search": "Search the web"
        case "error": "Agent error"
        case "checkpoint": "Changes saved"
        case "secret_request": "Secret requested. Respond in the desktop app."
        default: row.type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    private var itemIcon: String {
        switch row.type {
        case "command_execution": "terminal"
        case "file_change": "doc.text"
        case "reasoning": "brain"
        case "error": "exclamationmark.triangle"
        case "web_search", "file_search": "magnifyingglass"
        default: "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct AttachmentLinks: View {
    let attachments: [JSONValue]
    let open: (AttachmentReference) -> Void
    var body: some View {
        ForEach(Array(attachments.enumerated()), id: \.offset) { _, value in
            let attachment = AttachmentReference(value)
            Button { open(attachment) } label: {
                HStack(spacing: 8) {
                    Image(systemName: attachment.type == "image" ? "photo" : "doc")
                    Text(attachment.displayName).lineLimit(2)
                    Spacer(minLength: 8)
                    if attachment.sizeBytes > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.sizeBytes), countStyle: .file))
                            .foregroundStyle(.secondary)
                    }
                    if attachment.canPreview { Image(systemName: "chevron.right").font(.system(size: 10)) }
                    else { Text("Unsupported").foregroundStyle(.secondary) }
                }.font(T3Font.caption).padding(.vertical, 8).contentShape(.rect)
            }.buttonStyle(.plain).disabled(!attachment.canPreview)
                .accessibilityLabel("Open " + attachment.displayName)
        }
    }
}

struct RequestRow: View {
    let row: TimelineRow
    let request: JSONValue
    @Bindable var store: AppStore
    let threadID: String
    @State private var answers: [String: String] = [:]
    @State private var multiple: [String: Set<String>] = [:]
    var pending: Bool { request["status"].string == "pending" }
    var canRespond: Bool { pending && store.canOperate && request["responseCapability"]["type"].string != "not_resumable" && !store.pendingActions.contains(request.id) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(row.type == "approval_request" ? "Approval requested" : "Your response", systemImage: "hand.raised")
                .font(T3Font.headline)
            if row.type == "approval_request" {
                if !row.text.isEmpty { Text(row.text).font(T3Font.subheadline).textSelection(.enabled) }
                if pending {
                    let options = row.value["options"].array
                    if options.isEmpty {
                        HStack {
                            Button("Allow once") { respond("accept") }.buttonStyle(.glassProminent)
                            Button("Decline", role: .destructive) { respond("decline") }.buttonStyle(.glass)
                        }.disabled(!canRespond)
                    } else {
                        ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                            Button(option["label"].string) { respond(option["decision"].string) }.buttonStyle(.glass).disabled(!canRespond)
                            if !option["warning"].string.isEmpty { Text(option["warning"].string).font(T3Font.caption).foregroundStyle(.orange) }
                        }
                    }
                }
            } else {
                ForEach(row.value["questions"].array, id: \.id) { question in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(question["question"].string).font(T3Font.subheadline.weight(.medium))
                        ForEach(Array(question["options"].array.enumerated()), id: \.offset) { _, option in
                            let value = option["value"].string.isEmpty ? option["label"].string : option["value"].string
                            Button {
                                if question["multiSelect"].bool {
                                    var set = multiple[question.id] ?? []
                                    if set.contains(value) { set.remove(value) } else { set.insert(value) }
                                    multiple[question.id] = set
                                } else { answers[question.id] = value }
                            } label: {
                                HStack(alignment: .top) {
                                    Image(systemName: isSelected(question, value) ? "checkmark.circle.fill" : "circle")
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(option["label"].string)
                                        if !option["description"].string.isEmpty { Text(option["description"].string).font(T3Font.caption).foregroundStyle(.secondary) }
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.disabled(!canRespond)
                        }
                        if question["allowCustomAnswer"].isNull || question["allowCustomAnswer"].bool || question["options"].array.isEmpty {
                            TextField("Your answer", text: Binding(get: { answers[question.id] ?? question["initialAnswer"].string }, set: { answers[question.id] = $0 }), axis: .vertical)
                                .textFieldStyle(.roundedBorder).disabled(!canRespond)
                        }
                    }
                }
                if pending {
                    Button("Submit response") {
                        var payload = answers.mapValues(JSONValue.string)
                        for (key, values) in multiple {
                            var combined = values.sorted()
                            if let custom = answers[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty, !combined.contains(custom) { combined.append(custom) }
                            payload[key] = .array(combined.map(JSONValue.string))
                        }
                        for question in row.value["questions"].array where payload[question.id] == nil && !question["initialAnswer"].isNull { payload[question.id] = question["initialAnswer"] }
                        Task { await store.respond(request: request, threadID: threadID, answers: .object(payload)) }
                    }.buttonStyle(.glassProminent).disabled(!canRespond || !hasRequiredAnswers)
                }
            }
            if !pending { Text(request["status"].string.capitalized).font(T3Font.caption).foregroundStyle(.secondary) }
            else if request["responseCapability"]["type"].string == "not_resumable" { Text(request["responseCapability"]["reason"].string).font(T3Font.caption).foregroundStyle(.secondary) }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.06), in: .rect(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(.orange.opacity(0.25)) }
    }
    private func respond(_ decision: String) { Task { await store.respond(request: request, threadID: threadID, decision: decision) } }
    private func isSelected(_ question: JSONValue, _ value: String) -> Bool { question["multiSelect"].bool ? multiple[question.id]?.contains(value) == true : answers[question.id] == value }
    private var hasRequiredAnswers: Bool {
        row.value["questions"].array.allSatisfy { question in
            if question["required"] == .bool(false) { return true }
            return !(answers[question.id] ?? question["initialAnswer"].string).isEmpty || !(multiple[question.id] ?? []).isEmpty
        }
    }
}
