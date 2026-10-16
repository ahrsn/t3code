import XCTest
import Observation
@testable import T3Native

@MainActor final class PhoneConnectionTests: XCTestCase {
    /// Explicit device provisioning. The normal app pairer writes its own Keychain and preferences.
    func testConnectProvidedPersonalHost() async throws {
        let environment = ProcessInfo.processInfo.environment
        let link = environment["T3_NATIVE_PAIRING_URL"] ?? environment["TEST_RUNNER_T3_NATIVE_PAIRING_URL"] ?? ""
        let reuse = environment["T3_NATIVE_REUSE_SAVED_HOST"] == "1" || environment["TEST_RUNNER_T3_NATIVE_REUSE_SAVED_HOST"] == "1"
        guard !link.isEmpty || reuse else { throw XCTSkip("No personal host provisioning link provided.") }
        let store = AppStore()
        if reuse {
            let host = try XCTUnwrap(store.activeHost, "Expected the already provisioned personal host.")
            store.connect(host)
        } else {
            let paired = await store.pair(link: link, code: "", name: "MacBook Pro")
            XCTAssertTrue(paired, store.error ?? "Pairing failed")
            guard paired else { return }
        }
        let (events, continuation) = AsyncStream<Result<Bool, ClientError>>.makeStream()
        let observer = ConnectionObserver(store: store, continuation: continuation)
        observer.observe()
        let deadline = Task { try await Task.sleep(for: .seconds(30)); continuation.finish() }
        defer { deadline.cancel(); store.disconnect(); withExtendedLifetime(observer) {} }
        var connected = false
        for await event in events { connected = try event.get() }
        XCTAssertTrue(connected, "The saved connection did not load a server snapshot.")
        XCTAssertTrue(store.activeHost?.canOperate == true, "The connection must allow conversation actions.")
        XCTAssertFalse(store.projects.isEmpty, "Expected projects from the personal server.")
        XCTAssertFalse(store.threads.isEmpty, "Expected conversations from the personal server.")
        print("NATIVE_PHONE_CONNECTED projects=\(store.projects.count) conversations=\(store.threads.count)")
        let index = ThreadIndex(threads: store.threads)
        let thread = try XCTUnwrap(index.pinned.first ?? index.working.first ?? index.settled.first)
        await store.selectThread(thread.id)
        try await waitForDetail(store, id: thread.id)
        store.disconnect()
        store.resume()
        XCTAssertEqual(store.conversation?.id, thread.id, "Foreground reconnect must preserve the open conversation.")
        try await waitForDetail(store, id: thread.id)
        print("NATIVE_PHONE_RECONNECTED_DETAIL")

    }
    func testLoadEarlierFromSavedRealHostWhenRequested() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["T3_NATIVE_REUSE_SAVED_HOST"] == "1" || env["TEST_RUNNER_T3_NATIVE_REUSE_SAVED_HOST"] == "1" else { throw XCTSkip("Opt-in real-host history read.") }
        let store = AppStore()
        store.connect(try XCTUnwrap(store.activeHost))
        let (events, continuation) = AsyncStream<Result<Bool, ClientError>>.makeStream()
        let observer = ConnectionObserver(store: store, continuation: continuation)
        observer.observe()
        let deadline = Task { try await Task.sleep(for: .seconds(30)); continuation.finish() }
        defer { deadline.cancel(); store.disconnect(); withExtendedLifetime(observer) {} }
        for await event in events { _ = try event.get() }
        XCTAssertTrue(store.connected)
        let index = ThreadIndex(threads: store.threads)
        let candidates = Array((index.pinned + index.working + index.settled).prefix(8))
        for thread in candidates {
            await store.selectThread(thread.id)
            try await waitForDetail(store, id: thread.id)
            guard let detail = store.conversation, detail.projection.hasMoreHistory else { continue }
            let before = detail.rows.map(\.id)
            let cursor = detail.projection.historyCursor
            let loaded = await store.loadHistory()
            XCTAssertTrue(loaded, detail.historyError ?? "History page failed")
            XCTAssertNil(detail.historyError)
            XCTAssertNotEqual(detail.projection.historyCursor, cursor)
            XCTAssertGreaterThan(detail.rows.count, before.count)
            XCTAssertEqual(Set(detail.rows.map(\.id)).count, detail.rows.count)
            let priorIDs = Set(before)
            XCTAssertEqual(detail.rows.map(\.id).filter { priorIDs.contains($0) }, before)
            let firstOld = try XCTUnwrap(detail.rows.firstIndex { $0.id == before.first })
            XCTAssertGreaterThan(firstOld, 0)
            XCTAssertTrue(detail.rows.prefix(firstOld).filter { $0.isMessage && !$0.value["streaming"].bool }.allSatisfy { $0.markdown?.source == $0.text })
            print("NATIVE_HISTORY_REAL_PAGE before=\(before.count) after=\(detail.rows.count)")
            return
        }
        throw XCTSkip("No pageable snapshot among the sampled conversations.")
    }

    func testPreviewAttachmentFromSavedRealHostWhenRequested() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["T3_NATIVE_REUSE_SAVED_HOST"] == "1" || env["TEST_RUNNER_T3_NATIVE_REUSE_SAVED_HOST"] == "1" else { throw XCTSkip("Opt-in real-host attachment read.") }
        let store = AppStore()
        store.connect(try XCTUnwrap(store.activeHost))
        let (events, continuation) = AsyncStream<Result<Bool, ClientError>>.makeStream()
        let observer = ConnectionObserver(store: store, continuation: continuation)
        observer.observe()
        let deadline = Task { try await Task.sleep(for: .seconds(30)); continuation.finish() }
        defer { deadline.cancel(); store.disconnect(); withExtendedLifetime(observer) {} }
        for await event in events { _ = try event.get() }
        XCTAssertTrue(store.connected)
        let index = ThreadIndex(threads: store.threads)
        for thread in (index.pinned + index.working + index.settled).prefix(12) {
            await store.selectThread(thread.id)
            try await waitForDetail(store, id: thread.id)
            let attachments = store.conversation?.rows.flatMap { $0.value["attachments"].array }.map(AttachmentReference.init) ?? []
            guard let attachment = attachments.first(where: { $0.canPreview && $0.sizeBytes < 10 * 1024 * 1024 }) else { continue }
            let file = try await store.previewAttachment(attachment, hostID: store.activeHostID)
            let bytes = try file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            XCTAssertTrue(file.url.isFileURL)
            XCTAssertGreaterThan(bytes, 0)
            XCTAssertLessThanOrEqual(Int64(bytes), AttachmentDownloads.maximumBytes)
            print("NATIVE_ATTACHMENT_REAL_DOWNLOAD bytes=\(bytes)")
            return
        }
        throw XCTSkip("No supported attachment in the sampled conversation snapshots.")
    }

    private func waitForDetail(_ store: AppStore, id: String) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while ContinuousClock.now < deadline {
            if store.connected && store.conversation?.id == id && store.conversation?.projection.hasSnapshot == true { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail(store.error ?? store.conversation?.error ?? "The open conversation did not reload.")
    }

    func testSendNativeDraftAttachmentsOnIsolatedHostWhenProvided() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let link = env["T3_NATIVE_ATTACHMENT_PAIRING_URL"] ?? env["TEST_RUNNER_T3_NATIVE_ATTACHMENT_PAIRING_URL"],
              try PairingTarget(link).origin.host == "127.0.0.1" else { throw XCTSkip("Opt-in isolated-host attachment send.") }
        let (host, token) = try await HostAuthenticator().pair(target: PairingTarget(link), name: "Native attachment test")
        let previous = UserDefaults.standard.string(forKey: "activeHost")
        let store = AppStore()
        try CredentialVault.save(token, for: host.id)
        defer {
            store.disconnect(); CredentialVault.remove(host.id)
            if let previous { UserDefaults.standard.set(previous, forKey: "activeHost") }
            else { UserDefaults.standard.removeObject(forKey: "activeHost") }
        }
        store.hosts.append(host); store.connect(host)
        let (events, continuation) = AsyncStream<Result<Bool, ClientError>>.makeStream()
        let observer = ConnectionObserver(store: store, continuation: continuation, requireConfig: true); observer.observe()
        let deadline = Task { try await Task.sleep(for: .seconds(30)); continuation.finish() }
        defer { deadline.cancel(); withExtendedLifetime(observer) {} }
        for await event in events { _ = try event.get() }
        XCTAssertTrue(store.connected)
        let project = try XCTUnwrap(store.projects.first)
        let provider = try XCTUnwrap(store.config["providers"].array.first { $0["driver"].string == "codex" })
        let model = try XCTUnwrap(provider["models"].array.first { $0["isDefault"].bool } ?? provider["models"].array.first)
        let selected = ModelCatalog(config: store.config, projectID: project.id).selection(instanceID: provider["instanceId"].string, modelID: model["slug"].string, options: [:])
        let thread = try await store.createThread(project: project, title: "Native attachment send verification", model: selected)
        await store.selectThread(thread); try await waitForDetail(store, id: thread)
        let key = "draft.\(host.id.uuidString).\(thread).attachments"
        let source = try AttachmentDraftFixtures.file(image: false), image = try AttachmentDraftFixtures.file(image: true)
        let limits = AttachmentLimits(config: store.config)
        _ = try await AttachmentDraftStore.shared.importFile(source.url, key: key, limits: limits)
        let files = try await AttachmentDraftStore.shared.importFile(image.url, key: key, limits: limits)
        var localURLs: [URL] = []
        for file in files { localURLs.append(try await AttachmentDraftStore.shared.uploadFile(file, key: key)) }
        let refused = await store.send(text: "Review these attachments.", threadID: thread, model: .object(["instanceId": .string("unavailable"), "model": .string("missing")]), attachments: files, draftKey: key)
        XCTAssertFalse(refused)
        let retained = try await AttachmentDraftStore.shared.items(key: key)
        XCTAssertEqual(retained, files)
        store.error = nil
        let (responses, responseSink) = AsyncStream<Bool>.makeStream()
        let responseObserver = AttachmentResponseObserver(store: store, continuation: responseSink); responseObserver.observe()
        let responseDeadline = Task { try await Task.sleep(for: .seconds(90)); responseSink.finish() }
        defer { responseDeadline.cancel(); withExtendedLifetime(responseObserver) {} }
        let sent = await store.send(text: "Read the attached text file and look at the image. Reply with one short sentence mentioning the text is fixture data and the image says T3 attachment draft. Do not change files.", threadID: thread, model: selected, attachments: files, draftKey: key)
        XCTAssertTrue(sent, store.error ?? "Attachment dispatch failed")
        let remaining = try await AttachmentDraftStore.shared.items(key: key)
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertTrue(localURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        var completed = false
        for await response in responses { completed = response }
        XCTAssertTrue(completed, "No completed assistant response from isolated host")
        let message = try XCTUnwrap(store.conversation?.rows.last { $0.isUser && $0.value["attachments"].array.count == 2 })
        XCTAssertEqual(Set(message.value["attachments"].array.map { $0["type"].string }), ["image", "file"])
        XCTAssertEqual(message.value["attachments"].array.map { $0["sizeBytes"].int }, files.map(\.sizeBytes))
        for (attachment, source) in zip(message.value["attachments"].array, [source, image]) {
            let downloaded = try await store.previewAttachment(AttachmentReference(attachment), hostID: host.id)
            XCTAssertEqual(try Data(contentsOf: downloaded.url), try Data(contentsOf: source.url), "The server must retain the exact uploaded bytes.")
        }
        print("NATIVE_ATTACHMENT_SEND_CONFIRMED files=2 localCopiesCleared=true assistantCompleted=\(completed)")
        withExtendedLifetime([source, image]) {}
    }

}

@MainActor private final class AttachmentResponseObserver {
    let store: AppStore
    let continuation: AsyncStream<Bool>.Continuation
    init(store: AppStore, continuation: AsyncStream<Bool>.Continuation) { self.store = store; self.continuation = continuation }
    func observe() {
        withObservationTracking {
            let rows = store.conversation?.rows ?? []
            if rows.contains(where: { $0.type == "assistant_message" && !$0.text.isEmpty && !$0.value["streaming"].bool }) { continuation.yield(true); continuation.finish() }
            else if rows.contains(where: { $0.type == "error" }) { continuation.yield(false); continuation.finish() }
        } onChange: { [weak self] in Task { @MainActor in self?.observe() } }
    }
}

@MainActor private final class ConnectionObserver {
    let store: AppStore
    let continuation: AsyncStream<Result<Bool, ClientError>>.Continuation
    let requireConfig: Bool
    init(store: AppStore, continuation: AsyncStream<Result<Bool, ClientError>>.Continuation, requireConfig: Bool = false) {
        self.store = store; self.continuation = continuation; self.requireConfig = requireConfig
    }
    func observe() {
        withObservationTracking {
            if store.connected && (!requireConfig || !store.config["providers"].array.isEmpty) { continuation.yield(.success(true)); continuation.finish() }
            else if let error = store.error { continuation.yield(.failure(ClientError(error))); continuation.finish() }
        } onChange: { [weak self] in Task { @MainActor in self?.observe() } }
    }
}
