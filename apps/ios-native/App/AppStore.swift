import SwiftUI
import Observation

struct ComposerSendConfirmation: Equatable {
    let id = UUID()
    let draftKey: String
    let text: String
}

@MainActor @Observable final class Conversation {
    let id: String
    var projection = ThreadProjection()
    var rows: [TimelineRow] = []
    var error: String?
    var loadingHistory = false
    var historyError: String?
    @ObservationIgnored var historyDocuments: [String: MarkdownDocument] = [:]
    init(id: String) { self.id = id }
    func apply(_ item: JSONValue) {
        if item["kind"].string == "client.error" { error = item["message"].string; return }
        projection.apply(item)
        refreshRows()
    }
    func refreshRows() {
        rows = projection.rows.map { row in
            var row = row
            if let document = historyDocuments[row.id], document.source == row.text { row.markdown = document }
            return row
        }
    }
}

@MainActor @Observable final class AppStore {
    var hosts: [SavedHost] = []
    var activeHostID: UUID?
    var phase = "Disconnected"
    var connected = false
    var shell = ShellProjection()
    var config: JSONValue = .null
    var error: String?
    var isPairing = false
    var isDemo = false
    var sending = false
    var composerSendTask: Task<Void, Never>?
    var lastConfirmedSend: ComposerSendConfirmation?
    var uploadingName: String?
    var uploadDraftKey: String?
    var uploadFraction = 0.0
    var conversation: Conversation?
    var pendingActions: Set<String> = []
    #if DEBUG
    @ObservationIgnored var demoAttachmentAttempts: Set<String> = []
    #endif
    @ObservationIgnored private let authenticator = HostAuthenticator()
    @ObservationIgnored private var transport = RPCTransport()
    @ObservationIgnored private var connectionTask: Task<Void, Never>?
    @ObservationIgnored private var detailSubscription: String?
    @ObservationIgnored private var selectionGeneration = UUID()
    @ObservationIgnored private var connectionGeneration = UUID()
    @ObservationIgnored private var detailBuffer: [JSONValue] = []
    @ObservationIgnored private var flushTask: Task<Void, Never>?

    init() {
        if let data = UserDefaults.standard.data(forKey: "hosts"), let saved = try? JSONDecoder().decode([SavedHost].self, from: data) { hosts = saved }
        if let id = UserDefaults.standard.string(forKey: "activeHost") { activeHostID = UUID(uuidString: id) }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo") {
            if ProcessInfo.processInfo.arguments.contains("--reset-demo-draft") {
                UserDefaults.standard.removeObject(forKey: "draft.\(activeHostID?.uuidString ?? "none").t0")
                UserDefaults.standard.removeObject(forKey: "draft.\(activeHostID?.uuidString ?? "none").t0.model")
            }
            loadDemo()
        }
        #endif
    }
    var activeHost: SavedHost? { hosts.first { $0.id == activeHostID } }
    var canOperate: Bool { connected && !isDemo && activeHost?.canOperate == true }
    var projects: [JSONValue] { shell.projects.values.sorted { $0["title"].string.localizedStandardCompare($1["title"].string) == .orderedAscending } }
    var threads: [JSONValue] { shell.threads.values.sorted { $0["updatedAt"].string > $1["updatedAt"].string } }

    func pair(link: String, code: String, name: String) async -> Bool {
        isPairing = true; defer { isPairing = false }
        do {
            let target = try PairingTarget(link, code: code)
            var (host, token) = try await authenticator.pair(target: target, name: name)
            if let old = hosts.first(where: { $0.origin == host.origin }) {
                host = SavedHost(id: old.id, name: host.name, origin: host.origin, expiresAt: host.expiresAt, scopes: host.scopes)
            }
            try CredentialVault.save(token, for: host.id)
            hosts.removeAll { $0.id == host.id }; hosts.append(host)
            persistHosts(); connect(host)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func connect(_ host: SavedHost) {
        let openThreadID = activeHostID == host.id ? conversation?.id : nil
        disconnect()
        isDemo = false; activeHostID = host.id
        UserDefaults.standard.set(host.id.uuidString, forKey: "activeHost")
        shell = ShellProjection(); config = .null
        conversation = openThreadID.map { Conversation(id: $0) }
        let generation = UUID(); connectionGeneration = generation
        let rpc = RPCTransport(); transport = rpc
        connectionTask = Task {
            defer { if connectionGeneration == generation { connectionTask = nil } }
            var attempt = 0
            while !Task.isCancelled {
                guard connectionGeneration == generation else { return }
                phase = attempt == 0 ? "Connecting" : "Reconnecting"
                do {
                    let token = try CredentialVault.token(for: host.id)
                    let url = try await authenticator.socketURL(host: host, token: token)
                    try Task.checkCancellation()
                    try await rpc.run(url: url) { [self] in
                        try await subscribe(rpc: rpc, generation: generation)
                    }
                } catch {
                    guard !Task.isCancelled, connectionGeneration == generation else { return }
                    connected = false; phase = "Disconnected"; self.error = error.localizedDescription
                    // Authentication failures need a new user pairing, not a retry storm.
                    if error is ClientError { return }
                }
                attempt += 1
                do { try await Task.sleep(for: .seconds(min(30, pow(2, Double(min(attempt, 5)))))) } catch { return }
            }
        }
    }

    private func subscribe(rpc: RPCTransport, generation: UUID) async throws {
        _ = try await rpc.subscribe("subscribeServerConfig") { [weak self] item in
            await self?.receiveConfig(item, generation: generation)
        }
        _ = try await rpc.subscribe("orchestration.subscribeShell") { [weak self] item in
            await self?.receiveShell(item, generation: generation)
        }
        if let id = conversation?.id { await selectThread(id) }
    }
    private func receiveConfig(_ item: JSONValue, generation: UUID) {
        guard connectionGeneration == generation else { return }
        if !item["config"].isNull { config = item["config"] }
        if item["kind"].string == "client.error" { error = item["message"].string }
    }
    private func receiveShell(_ item: JSONValue, generation: UUID) {
        guard connectionGeneration == generation else { return }
        if item["kind"].string == "client.error" { error = item["message"].string; return }
        shell.apply(item)
        if shell.hasSnapshot { connected = true; phase = "Connected"; error = nil }
    }
    func disconnect() {
        connectionGeneration = UUID(); selectionGeneration = UUID()
        connectionTask?.cancel(); connectionTask = nil
        let rpc = transport; Task { await rpc.close() }
        flushTask?.cancel(); flushTask = nil; detailBuffer.removeAll()
        detailSubscription = nil; connected = false; phase = "Disconnected"
    }
    func resume() { if !isDemo, let host = activeHost, connectionTask == nil { connect(host) } }
    func retry() { if let host = activeHost { connect(host) } }
    func removeHost(_ host: SavedHost) {
        if activeHostID == host.id { disconnect(); activeHostID = nil; conversation = nil; shell = ShellProjection() }
        CredentialVault.remove(host.id); hosts.removeAll { $0.id == host.id }; persistHosts()
    }
    private func persistHosts() { UserDefaults.standard.set(try? JSONEncoder().encode(hosts), forKey: "hosts") }

    func selectThread(_ id: String) async {
        #if DEBUG
        if isDemo { loadDemo(threadID: id); return }
        #endif
        let generation = UUID(); selectionGeneration = generation
        flushTask?.cancel(); flushTask = nil; detailBuffer.removeAll()
        if conversation?.id != id { conversation = Conversation(id: id) }
        let rpc = transport
        await rpc.unsubscribe(detailSubscription); detailSubscription = nil
        guard selectionGeneration == generation else { return }
        do {
            let subscription = try await rpc.subscribe("orchestration.subscribeThread", payload: .object([
                "threadId": .string(id), "acceptBoundedSnapshot": .bool(true)
            ])) { [weak self] item in await self?.bufferDetail(item, generation: generation) }
            if selectionGeneration == generation { detailSubscription = subscription }
            else { await rpc.unsubscribe(subscription) }
        } catch { if selectionGeneration == generation { conversation?.error = error.localizedDescription } }
    }
    func closeConversation(expectedID: String? = nil) async {
        if let expectedID, conversation?.id != expectedID { return }
        selectionGeneration = UUID(); flushTask?.cancel(); flushTask = nil; detailBuffer.removeAll()
        let id = detailSubscription; detailSubscription = nil; conversation = nil
        await transport.unsubscribe(id)
    }
    private func bufferDetail(_ item: JSONValue, generation: UUID) {
        guard generation == selectionGeneration else { return }
        detailBuffer.append(item)
        guard flushTask == nil else { return }
        // Coalesce streaming deltas to at most 20 UI updates/sec; never animate each token.
        flushTask = Task {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            guard generation == selectionGeneration else { return }
            let batch = detailBuffer; detailBuffer.removeAll(); flushTask = nil
            guard let conversation else { return }
            for item in batch { conversation.projection.apply(item) }
            if let failure = batch.last(where: { $0["kind"].string == "client.error" }) { conversation.error = failure["message"].string }
            conversation.refreshRows()
        }
    }

    func dispatch(_ fields: [String: JSONValue]) async throws {
        guard canOperate else { throw ClientError("This connection cannot change conversations. Pair with an operate permission link.") }
        var fields = fields; fields["commandId"] = .string(UUID().uuidString)
        _ = try await transport.call("orchestration.dispatchCommand", payload: .object(fields))
    }
    func send(text: String, threadID: String, model: JSONValue? = nil, attachments: [DraftAttachment] = [], draftKey: String? = nil) async -> Bool {
        guard !sending, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty,
              canOperate, let host = activeHost else { return false }
        let rpc = transport
        let generation = connectionGeneration
        sending = true; uploadDraftKey = draftKey
        defer { sending = false; uploadingName = nil; uploadDraftKey = nil; uploadFraction = 0 }
        do {
            if let model {
                let projectID = shell.threads[threadID]?["projectId"].string ?? ""
                guard ModelCatalog(config: config, projectID: projectID).canSelect(model) else {
                    throw ClientError("This model is no longer available for this project. Choose another model before sending.")
                }
            }
            let attempt: AttachmentSendAttempt?
            var references: [JSONValue] = []
            if !attachments.isEmpty {
                guard let draftKey else { throw ClientError("The attachment draft could not be loaded.") }
                // Read saved upload IDs, including those retained by an earlier failed send.
                let current = try await AttachmentDraftStore.shared.items(key: draftKey)
                let ids = Set(attachments.map(\.id))
                let selected = current.filter { ids.contains($0.id) }
                guard selected.map(\.id) == attachments.map(\.id) else { throw ClientError("The attachments changed. Review the draft before sending.") }
                try AttachmentLimits(config: config).validate(selected)
                attempt = try await AttachmentDraftStore.shared.attempt(key: draftKey, text: text, model: model, attachments: selected)
                for item in selected {
                    try Task.checkCancellation()
                    guard connectionGeneration == generation, activeHostID == host.id, canOperate else { throw ClientError("The connection changed. Your attachments are saved.") }
                    uploadingName = item.name; uploadFraction = 0
                    if let id = item.uploadedID {
                        do {
                            _ = try await rpc.call("assets.createUrl", payload: .object(["resource": .object(["_tag": .string("attachment"), "attachmentId": .string(id)])]))
                            references.append(item.reference(id: id)); continue
                        } catch {
                            guard let failure = error as? RPCFailure, failure.contains(tag: "AssetAttachmentNotFoundError") else { throw error }
                        }
                    }
                    let file = try await AttachmentDraftStore.shared.uploadFile(item, key: draftKey)
                    var metadata = item.reference(id: "").object; metadata.removeValue(forKey: "id")
                    let minted = try await rpc.call("attachments.createUploadUrl", payload: .object(metadata))
                    let uploadID = minted["attachmentId"].string
                    guard !uploadID.isEmpty, uploadID.count <= 128, uploadID.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil else { throw ClientError("The server returned an invalid attachment ID.") }
                    guard connectionGeneration == generation, activeHostID == host.id, canOperate else { throw ClientError("The connection changed. Your attachments are saved.") }
                    let url = try AttachmentUploads.uploadURL(relative: minted["relativeUrl"].string, origin: host.origin)
                    try await AttachmentUploads.upload(file: file, item: item, url: url) { [weak self] progress in
                        Task { @MainActor in
                            guard let self, self.connectionGeneration == generation else { return }
                            self.uploadFraction = progress
                        }
                    }
                    try await AttachmentDraftStore.shared.markUploaded(item, uploadID: uploadID, key: draftKey)
                    references.append(item.reference(id: uploadID))
                }
            } else { attempt = nil }
            uploadingName = nil
            try Task.checkCancellation()
            guard connectionGeneration == generation, activeHostID == host.id, canOperate else { throw ClientError("The connection changed. Your draft is saved.") }
            var fields: [String: JSONValue] = ["type": .string("message.dispatch"), "createdBy": .string("user"), "creationSource": .string("mobile"),
                                "threadId": .string(threadID), "messageId": .string(UUID().uuidString), "text": .string(text),
                                "attachments": .array(references), "deliveryIntent": .string("auto"),
                                "dispatchMode": .object(["type": .string("queue_after_active")])]
            if let model {
                let catalog = ModelCatalog(config: config, projectID: shell.threads[threadID]?["projectId"].string ?? "")
                fields["modelSelection"] = catalog.selection(instanceID: model["instanceId"].string, modelID: model["model"].string, options: ModelCatalog.optionValues(model))
            }
            fields["commandId"] = .string(attempt?.commandID ?? UUID().uuidString)
            if let attempt { fields["messageId"] = .string(attempt.messageID) }
            _ = try await rpc.call("orchestration.dispatchCommand", payload: .object(fields))
            if let draftKey, let attempt {
                do { _ = try await AttachmentDraftStore.shared.remove(ids: Set(attachments.map(\.id)), key: draftKey, confirmedAttempt: attempt.commandID) }
                catch { self.error = "Message sent, but the saved attachment copies could not be cleared: " + error.localizedDescription }
            }
            if let draftKey { lastConfirmedSend = ComposerSendConfirmation(draftKey: draftKey, text: text) }
            return true
        } catch {
            if !Task.isCancelled, activeHostID == host.id { self.error = error.localizedDescription }
            return false
        }
    }
    func stop(_ threadID: String) async {
        do {
            let projection = try await transport.call("orchestration.getThreadProjection", payload: .object(["threadId": .string(threadID)]))
            let runs = projection["runs"].array
            let active = runs.last(where: { ["preparing", "starting", "running", "waiting"].contains($0["status"].string) })
            let background = shell.threads[threadID]?["pendingBackgroundTasks"].array.isEmpty == false
            guard let run = active ?? (background ? runs.last : nil) else { return }
            try await dispatch(["type": .string("run.interrupt"), "threadId": .string(threadID), "runId": run["id"], "holdQueue": .bool(true)])
        }
        catch { self.error = error.localizedDescription }
    }
    func previewAttachment(_ attachment: AttachmentReference, hostID: UUID?) async throws -> AttachmentPreviewFile {
        #if DEBUG
        if isDemo { return try AttachmentFixtures.preview(attachment, attempts: &demoAttachmentAttempts) }
        #endif
        guard let host = activeHost, host.id == hostID, connected else { throw ClientError("Reconnect to this server before opening the attachment.") }
        let result = try await transport.call("assets.createUrl", payload: .object(["resource": attachment.resource]))
        guard activeHostID == hostID else { throw CancellationError() }
        let url = try AttachmentDownloads.assetURL(relative: result["relativeUrl"].string, origin: host.origin)
        let file = try await AttachmentDownloads().download(url: url, attachment: attachment)
        guard activeHostID == hostID else { throw CancellationError() }
        return file
    }
    func loadHistory(expectedID: String? = nil, beforeApplying: () -> Void = {}) async -> Bool {
        if let expectedID, conversation?.id != expectedID { return false }
        #if DEBUG
        if isDemo { return await loadDemoHistory(beforeApplying: beforeApplying) }
        #endif
        guard let detail = conversation, !detail.loadingHistory, let cursor = detail.projection.historyCursor, let host = activeHost else { return false }
        detail.loadingHistory = true; defer { detail.loadingHistory = false }
        do {
            let token = try CredentialVault.token(for: host.id)
            let page = try await authenticator.history(host: host, token: token, threadID: detail.id, cursor: cursor)
            guard conversation === detail else { return false }
            let documents = await MarkdownDocuments.shared.documents(for: page["items"].array)
            guard conversation === detail else { return false }
            beforeApplying()
            detail.historyDocuments.merge(documents) { _, new in new }
            detail.historyError = nil
            detail.projection.prependHistory(page); detail.refreshRows()
            return true
        } catch { detail.historyError = error.localizedDescription; return false }
    }
    func respond(request: JSONValue, threadID: String, decision: String? = nil, answers: JSONValue? = nil) async {
        guard !pendingActions.contains(request.id) else { return }
        pendingActions.insert(request.id); defer { pendingActions.remove(request.id) }
        do {
            var fields: [String: JSONValue] = ["type": .string("runtime-request.respond"), "threadId": .string(threadID), "requestId": .string(request.id)]
            if let decision { fields["decision"] = .string(decision) }
            if let answers { fields["answers"] = answers }
            try await dispatch(fields)
        } catch { self.error = error.localizedDescription }
    }
    func createThread(project: JSONValue, title: String, model: JSONValue) async throws -> String {
        guard canOperate else { throw ClientError("Connect with operate permission first.") }
        guard ModelCatalog(config: config, projectID: project.id).canSelect(model) else { throw ClientError("Choose a model available for this project.") }
        let result = try await transport.call("orchestration.launchThread", payload: .object([
            "commandId": .string(UUID().uuidString), "creationSource": .string("mobile"),
            "projectId": project["id"], "title": .string(title.isEmpty ? "New conversation" : title),
            "modelSelection": model, "runtimeMode": .string("approval-required"), "interactionMode": .string("default"),
            "workspaceStrategy": .object(["type": .string("root")])
        ]))
        guard !result["threadId"].string.isEmpty else { throw ClientError("The server returned no conversation ID.") }
        return result["threadId"].string
    }
    func setThreadState(_ id: String, type: String) async {
        do { try await dispatch(["type": .string(type), "threadId": .string(id)]) }
        catch { self.error = error.localizedDescription }
    }
}
