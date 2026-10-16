import XCTest
@testable import T3Native

@MainActor final class AttachmentLifecycleTests: XCTestCase {
    private let limits = AttachmentLimits(uploads: true, fileMaximum: 1024)
    private func key(_ host: UUID) -> String { "draft.\(host.uuidString).thread.attachments" }
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("t3-lifecycle-test-" + UUID().uuidString) }
    private func sample() throws -> AttachmentPreviewFile {
        let source = try AttachmentPreviewFile(name: "Notes.txt")
        try Data("Native T3 upload\n".utf8).write(to: source.url)
        return source
    }
    func testDiscardUnlinksOnlyTheChosenHostAndRejectsLateImports() async throws {
        let drafts = AttachmentDraftStore(root: root()), source = try sample(), a = UUID(), b = UUID()
        let first = try await drafts.importFile(source.url, key: key(a), limits: limits)[0]
        let second = try await drafts.importFile(source.url, key: key(b), limits: limits)[0]
        let firstURL = try await drafts.uploadFile(first, key: key(a))
        let secondURL = try await drafts.uploadFile(second, key: key(b))
        let neighbor = firstURL.deletingLastPathComponent().appendingPathComponent("Unrecognized.txt")
        try Data("Keep this file".utf8).write(to: neighbor)
        let nested = firstURL.deletingLastPathComponent().appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        let nestedFile = nested.appendingPathComponent("Keep.txt")
        try Data("Keep the directory".utf8).write(to: nestedFile)
        let unknown = try await drafts.discard(hostID: a)
        XCTAssertEqual(unknown, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertEqual(try String(contentsOf: secondURL, encoding: .utf8), "Native T3 upload\n")
        XCTAssertEqual(try String(contentsOf: neighbor, encoding: .utf8), "Keep this file")
        XCTAssertEqual(try String(contentsOf: nestedFile, encoding: .utf8), "Keep the directory")
        do { _ = try await drafts.importFile(source.url, key: key(a), limits: limits); XCTFail("Removed host accepted a late picker result") }
        catch { XCTAssertTrue(error is ClientError) }
        _ = try await drafts.discard(hostID: b)
        try FileManager.default.removeItem(at: neighbor)
        try FileManager.default.removeItem(at: nestedFile)
        if try FileManager.default.contentsOfDirectory(atPath: nested.path).isEmpty { try FileManager.default.removeItem(at: nested) }
        withExtendedLifetime(source) {}
    }
    func testLegacyOwnershipIsMigratedOnlyWithTheOriginalKey() async throws {
        let drafts = AttachmentDraftStore(root: root()), source = try sample(), host = UUID()
        let item = try await drafts.importFile(source.url, key: key(host), limits: limits)[0]
        let url = try await drafts.uploadFile(item, key: key(host))
        let manifest = url.deletingLastPathComponent().appendingPathComponent("draft.json")
        var old = try JSONValue.decode(Data(contentsOf: manifest)).object
        old.removeValue(forKey: "hostID")
        try JSONValue.object(old).data().write(to: manifest)
        let unknown = try await drafts.discard(hostID: UUID())
        XCTAssertEqual(unknown, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        _ = try await drafts.items(key: key(host))
        XCTAssertEqual(try JSONValue.decode(Data(contentsOf: manifest))["hostID"].string, host.uuidString)
        _ = try await drafts.discard(hostID: host)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        withExtendedLifetime(source) {}
    }
    func testRemovingAnInactiveHostPreservesSelectedServerAndItsDrafts() async throws {
        let suite = "t3-lifecycle-preferences-" + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let drafts = AttachmentDraftStore(root: root()), source = try sample()
        let a = SavedHost(name: "A", origin: URL(string: "https://a.invalid")!), b = SavedHost(name: "B", origin: URL(string: "https://b.invalid")!)
        let store = AppStore(attachmentDraftStore: drafts, preferences: preferences)
        store.hosts = [a, b]; store.activeHostID = b.id
        preferences.set(b.id.uuidString, forKey: "activeHost")
        preferences.set("A text", forKey: "draft.\(a.id.uuidString).thread")
        preferences.set("A model", forKey: "draft.\(a.id.uuidString).thread.model")
        preferences.set("B text", forKey: "draft.\(b.id.uuidString).thread")
        preferences.set("dark", forKey: "appearance")
        _ = try await drafts.importFile(source.url, key: key(a.id), limits: limits)
        let kept = try await drafts.importFile(source.url, key: key(b.id), limits: limits)
        _ = try await store.removeHost(a)
        XCTAssertEqual(store.hosts.map(\.id), [b.id]); XCTAssertEqual(store.activeHostID, b.id)
        XCTAssertNil(preferences.object(forKey: "draft.\(a.id.uuidString).thread"))
        XCTAssertNil(preferences.object(forKey: "draft.\(a.id.uuidString).thread.model"))
        XCTAssertEqual(preferences.string(forKey: "draft.\(b.id.uuidString).thread"), "B text")
        XCTAssertEqual(preferences.string(forKey: "activeHost"), b.id.uuidString)
        XCTAssertEqual(preferences.string(forKey: "appearance"), "dark")
        let remaining = try await drafts.items(key: key(b.id)); XCTAssertEqual(remaining, kept)
        let saved = try JSONDecoder().decode([SavedHost].self, from: XCTUnwrap(preferences.data(forKey: "hosts")))
        XCTAssertEqual(saved.map(\.id), [b.id])
        _ = try await drafts.discard(hostID: b.id)
        withExtendedLifetime(source) {}
    }
    func testDisconnectDoesNotCancelADispatchWhoseUploadPhaseHasEnded() async {
        let store = AppStore(preferences: UserDefaults(suiteName: "t3-dispatch-test-" + UUID().uuidString)!)
        let (release, sink) = AsyncStream<Void>.makeStream()
        let task = Task { for await _ in release { break }; XCTAssertFalse(Task.isCancelled) }
        store.composerSendTask = task; store.uploadingName = nil
        store.disconnect(); sink.yield(()); sink.finish()
        await task.value; store.composerSendTask = nil
    }
    func testRemovingSelectedHostClearsSelectionAndSavedMetadata() async throws {
        let suite = "t3-selected-removal-" + UUID().uuidString, preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let host = SavedHost(name: "Selected", origin: URL(string: "https://selected.invalid")!)
        let store = AppStore(attachmentDraftStore: AttachmentDraftStore(root: root()), preferences: preferences)
        store.hosts = [host]; store.activeHostID = host.id; store.connected = true; store.conversation = Conversation(id: "thread")
        preferences.set(host.id.uuidString, forKey: "activeHost")
        _ = try await store.removeHost(host)
        XCTAssertNil(store.activeHostID); XCTAssertNil(store.conversation); XCTAssertFalse(store.connected)
        XCTAssertTrue(store.hosts.isEmpty); XCTAssertNil(preferences.object(forKey: "activeHost"))
        XCTAssertNil(store.removingHostID)
    }
    func testCleanupFailureKeepsServerAndItsSavedTextAvailableForRetry() async throws {
        let suite = "t3-failed-removal-" + UUID().uuidString, preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let source = try sample(), host = SavedHost(name: "Kept", origin: URL(string: "https://kept.invalid")!)
        let store = AppStore(attachmentDraftStore: AttachmentDraftStore(root: source.url), preferences: preferences)
        store.hosts = [host]; store.activeHostID = host.id
        preferences.set("Saved text", forKey: "draft.\(host.id.uuidString).thread")
        do { _ = try await store.removeHost(host); XCTFail("Invalid cleanup root removed a server") } catch {}
        XCTAssertEqual(store.hosts.map(\.id), [host.id]); XCTAssertEqual(store.activeHostID, host.id)
        XCTAssertEqual(preferences.string(forKey: "draft.\(host.id.uuidString).thread"), "Saved text")
        XCTAssertNil(store.removingHostID)
        XCTAssertEqual(try String(contentsOf: source.url, encoding: .utf8), "Native T3 upload\n")
        withExtendedLifetime(source) {}
    }
    func testDisconnectCancelsAnActualByteTransferAndKeepsTheDraftWhenFixtureHostIsProvided() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let address = env["T3_NATIVE_ATTACHMENT_TEST_ORIGIN"] ?? env["TEST_RUNNER_T3_NATIVE_ATTACHMENT_TEST_ORIGIN"], let origin = URL(string: address) else { throw XCTSkip("Opt-in upload disconnect test.") }
        let source = try sample(), drafts = AttachmentDraftStore(root: root()), host = UUID()
        let item = try await drafts.importFile(source.url, key: key(host), limits: limits)[0]
        let local = try await drafts.uploadFile(item, key: key(host))
        let store = AppStore(attachmentDraftStore: drafts, preferences: UserDefaults(suiteName: "t3-upload-test-" + UUID().uuidString)!)
        let (started, sink) = AsyncStream<Void>.makeStream()
        var cancelled = false
        let task = Task {
            do { try await AttachmentUploads.upload(file: local, item: item, url: origin.appendingPathComponent("api/attachments/upload/wait")) { _ in sink.yield(()); sink.finish() }; XCTFail("Disconnected upload completed") }
            catch { cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled }
        }
        store.composerSendTask = task; store.uploadingName = item.name
        let deadline = Task { try await Task.sleep(for: .seconds(10)); sink.finish() }
        defer { deadline.cancel(); task.cancel() }
        for await _ in started { break }
        store.disconnect(); await task.value
        XCTAssertTrue(cancelled)
        XCTAssertEqual(try String(contentsOf: local, encoding: .utf8), "Native T3 upload\n")
        let retained = try await drafts.items(key: key(host)); XCTAssertEqual(retained, [item])
        store.composerSendTask = nil; _ = try await drafts.discard(hostID: host)
        withExtendedLifetime(source) {}
    }
}
