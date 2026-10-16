import XCTest
@testable import T3Native

final class ComposerAttachmentTests: XCTestCase {
    private let limits = AttachmentLimits(uploads: true, fileMaximum: AttachmentLimits.fileBytes)
    private func storeRoot() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("t3-draft-test-" + UUID().uuidString) }
    private func sample(_ name: String = "Notes.txt", text: String = "Native T3 upload\n") throws -> AttachmentPreviewFile {
        let file = try AttachmentPreviewFile(name: name)
        try Data(text.utf8).write(to: file.url)
        return file
    }
    private func item(type: String, bytes: Int, mime: String = "text/plain") -> DraftAttachment {
        DraftAttachment(id: UUID().uuidString, name: "File", mimeType: mime, type: type, sizeBytes: bytes)
    }
    func testDraftPreviewOwnsSnapshotAndPreservesSendState() async throws {
        let store = AttachmentDraftStore(root: storeRoot()), source = try sample()
        let key = "preview/thread"
        let imported = try await store.importFile(source.url, key: key, limits: limits)
        let item = try XCTUnwrap(imported.first)
        try await store.markUploaded(item, uploadID: "pending_preview", key: key)
        let attempt = try await store.attempt(key: key, text: "Send", model: nil, attachments: imported)
        var preview: AttachmentPreviewFile? = try await store.previewFile(id: item.id, key: key)
        let url = try XCTUnwrap(preview?.url)
        let durable = try await store.uploadFile(item, key: key)
        XCTAssertNotEqual(url, durable)
        XCTAssertEqual(url.lastPathComponent, "Notes.txt")
        XCTAssertEqual(try Data(contentsOf: url), try Data(contentsOf: durable))
        try Data("Edited preview".utf8).write(to: url)
        XCTAssertEqual(try Data(contentsOf: durable), Data("Native T3 upload\n".utf8))
        let saved = try await store.items(key: key)
        XCTAssertEqual(saved.first?.uploadedID, "pending_preview")
        let retried = try await store.attempt(key: key, text: "Send", model: nil, attachments: saved)
        XCTAssertEqual(retried, attempt)
        _ = try await store.remove(ids: [item.id], key: key)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "An open preview survives confirmed-send or draft removal.")
        preview = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
        withExtendedLifetime(source) {}
    }
    func testDraftPreviewRejectsOtherDraftAndRemovedOrChangedFiles() async throws {
        let store = AttachmentDraftStore(root: storeRoot()), source = try sample()
        let items = try await store.importFile(source.url, key: "original", limits: limits)
        let item = try XCTUnwrap(items.first)
        do { _ = try await store.previewFile(id: item.id, key: "other"); XCTFail("Another draft must not expose this attachment") }
        catch { XCTAssertTrue(error is ClientError) }
        let durable = try await store.uploadFile(item, key: "original")
        try Data("Changed".utf8).write(to: durable)
        do { _ = try await store.previewFile(id: item.id, key: "original"); XCTFail("Changed bytes must not be previewed") }
        catch { XCTAssertTrue(error is ClientError) }
        _ = try await store.remove(ids: [item.id], key: "original")
        do { _ = try await store.previewFile(id: item.id, key: "original"); XCTFail("Removed attachment accepted") }
        catch { XCTAssertEqual(error.localizedDescription, "This attachment was removed from the draft.") }
        withExtendedLifetime(source) {}
    }
    func testCancellingDraftPreviewLeavesTheDurableCopy() async throws {
        let store = AttachmentDraftStore(root: storeRoot()), source = try sample()
        let items = try await store.importFile(source.url, key: "cancel", limits: limits)
        let item = try XCTUnwrap(items.first)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.previewFile(id: item.id, key: "cancel")
        }
        do { _ = try await task.value; XCTFail("Cancelled preview completed") }
        catch { XCTAssertTrue(error is CancellationError) }
        let durable = try await store.uploadFile(item, key: "cancel")
        XCTAssertEqual(try Data(contentsOf: durable), Data("Native T3 upload\n".utf8))
        _ = try await store.remove(ids: [item.id], key: "cancel")
        withExtendedLifetime(source) {}
    }
    func testImportedBytesAndUploadedReferencesSurviveRestoringTheDraft() async throws {
        let root = storeRoot(), store = AttachmentDraftStore(root: root)
        let source = try sample()
        let imported = try await store.importFile(source.url, key: "host/thread", limits: limits)
        let file = try XCTUnwrap(imported.first)
        XCTAssertEqual(file.type, "file"); XCTAssertEqual(file.mimeType, "text/plain")
        XCTAssertEqual(file.name, "Notes.txt")
        try await store.markUploaded(file, uploadID: "pending_1", key: "host/thread")
        let restored = AttachmentDraftStore(root: root)
        let items = try await restored.items(key: "host/thread")
        XCTAssertEqual(items.first?.uploadedID, "pending_1")
        let url = try await restored.uploadFile(file, key: "host/thread")
        XCTAssertEqual(try Data(contentsOf: url), Data("Native T3 upload\n".utf8))
        XCTAssertNotEqual(url, source.url)
        _ = try await restored.remove(ids: [file.id], key: "host/thread")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.url.path), "Removing a draft must not remove the picked source.")
        withExtendedLifetime(source) {}
    }
    func testSameNamesAndDifferentHostsOwnSeparateCopies() async throws {
        let store = AttachmentDraftStore(root: storeRoot())
        let first = try sample(text: "First"), second = try sample(text: "Second")
        let a = try await store.importFile(first.url, key: "hostA/thread", limits: limits)
        let b = try await store.importFile(second.url, key: "hostB/thread", limits: limits)
        XCTAssertNotEqual(a[0].id, b[0].id)
        _ = try await store.remove(ids: [a[0].id], key: "hostA/thread")
        let other = try await store.items(key: "hostB/thread")
        XCTAssertEqual(other, b)
        let url = try await store.uploadFile(b[0], key: "hostB/thread")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Second")
        _ = try await store.remove(ids: [b[0].id], key: "hostB/thread")
        withExtendedLifetime([first, second]) {}
    }
    func testEmptyAndOversizedImportsLeaveTheExistingDraftIntact() async throws {
        let store = AttachmentDraftStore(root: storeRoot())
        let source = try sample(text: "Kept"), empty = try sample("Empty.txt", text: ""), large = try sample("Large.txt", text: "Too many bytes")
        let original = try await store.importFile(source.url, key: "draft", limits: limits)
        for candidate in [empty, large] {
            do { _ = try await store.importFile(candidate.url, key: "draft", limits: AttachmentLimits(uploads: true, fileMaximum: 5)); XCTFail("Invalid file imported") }
            catch { XCTAssertTrue(error is ClientError) }
        }
        let restored = try await store.items(key: "draft")
        XCTAssertEqual(restored, original)
        _ = try await store.remove(ids: [original[0].id], key: "draft")
        withExtendedLifetime([source, empty, large]) {}
    }
    func testLimitsFollowServerCapabilityAndImageBudgets() throws {
        let image = item(type: "image", bytes: AttachmentLimits.imageBytes, mime: "image/png")
        XCTAssertNoThrow(try limits.validate(Array(repeating: image, count: 8)))
        XCTAssertThrowsError(try limits.validate(Array(repeating: image, count: 9)))
        XCTAssertThrowsError(try limits.validate([item(type: "image", bytes: AttachmentLimits.imageBytes + 1, mime: "image/jpeg")]))
        XCTAssertThrowsError(try limits.validate([item(type: "image", bytes: 10, mime: "image/heic")]))
        XCTAssertThrowsError(try AttachmentLimits(uploads: false, fileMaximum: nil).validate([image]))
        XCTAssertNoThrow(try AttachmentLimits(uploads: true, fileMaximum: nil).validate([image]))
        XCTAssertThrowsError(try AttachmentLimits(uploads: true, fileMaximum: nil).validate([item(type: "file", bytes: 1)]))
        XCTAssertThrowsError(try AttachmentLimits(uploads: true, fileMaximum: 50).validate([item(type: "file", bytes: 51)]))
        XCTAssertThrowsError(try limits.validate(Array(repeating: item(type: "file", bytes: 1), count: 101)))
        XCTAssertEqual(AttachmentLimits(config: .object(["environment": .object(["capabilities": .object(["attachmentUploads": .bool(true), "fileAttachments": .object(["maxUploadBytes": .number(100_000_000)])])])])).fileMaximum, AttachmentLimits.fileBytes)
    }
    func testIdenticalRetryKeepsItsCommandAndMessageIDsAcrossRestart() async throws {
        let root = storeRoot(), store = AttachmentDraftStore(root: root), source = try sample()
        let files = try await store.importFile(source.url, key: "draft", limits: limits)
        let first = try await store.attempt(key: "draft", text: "Review", model: .object(["model": .string("m")]), attachments: files)
        try await store.markUploaded(files[0], uploadID: "pending_id", key: "draft")
        let restored = AttachmentDraftStore(root: root)
        let retry = try await restored.attempt(key: "draft", text: "Review", model: .object(["model": .string("m")]), attachments: files)
        XCTAssertEqual(first, retry)
        let edited = try await restored.attempt(key: "draft", text: "Different", model: .object(["model": .string("m")]), attachments: files)
        XCTAssertNotEqual(first.commandID, edited.commandID)
        _ = try await restored.remove(ids: [files[0].id], key: "draft", confirmedAttempt: edited.commandID)
        let remaining = try await restored.items(key: "draft")
        XCTAssertTrue(remaining.isEmpty)
        withExtendedLifetime(source) {}
    }
    func testMissingLocalFileCanBeRemovedAndManifestCannotEscapeItsDirectory() async throws {
        let store = AttachmentDraftStore(root: storeRoot()), source = try sample()
        let files = try await store.importFile(source.url, key: "../../draft", limits: limits)
        let url = try await store.uploadFile(files[0], key: "../../draft")
        try FileManager.default.removeItem(at: url)
        do { _ = try await store.uploadFile(files[0], key: "../../draft"); XCTFail("Missing file accepted") } catch {}
        _ = try await store.remove(ids: [files[0].id], key: "../../draft")
        let invalid = DraftAttachment(id: "../../escape", name: "Invalid", mimeType: "text/plain", type: "file", sizeBytes: 1)
        do { _ = try await store.uploadFile(invalid, key: "draft"); XCTFail("Invalid path accepted") } catch { XCTAssertTrue(error is ClientError) }
        withExtendedLifetime(source) {}
    }
    func testSignedUploadAddressAndTypedMissingAssetFailures() throws {
        let origin = URL(string: "https://host.example")!
        XCTAssertEqual(try AttachmentUploads.uploadURL(relative: "/api/attachments/upload/signed?token=test", origin: origin).host, origin.host)
        for path in ["https://other.example/api/attachments/upload/x", "//other.example/api/attachments/upload/x", "/api/attachments/upload/../../oauth/token", "/api/assets/x", "/api/attachments/upload/x#fragment"] {
            XCTAssertThrowsError(try AttachmentUploads.uploadURL(relative: path, origin: origin))
        }
        let error = RPCFailure(value: .object(["_tag": .string("Failure"), "cause": .object(["_tag": .string("Fail"), "error": .object(["_tag": .string("AssetAttachmentNotFoundError"), "message": .string("Missing")])])]))
        XCTAssertTrue(error.contains(tag: "AssetAttachmentNotFoundError"))
        XCTAssertFalse(error.contains(tag: "PermissionError"))
        XCTAssertEqual(error.localizedDescription, "Missing")
    }
    @MainActor func testPickerResultCannotMoveIntoAnotherConversationDraft() async throws {
        let draft = ComposerAttachmentDraft(), source = try sample()
        let old = "picker-origin." + UUID().uuidString, current = "picker-current." + UUID().uuidString
        await draft.load(key: old)
        await draft.load(key: current)
        await draft.add([source.url], limits: limits, expectedKey: old)
        XCTAssertTrue(draft.items.isEmpty)
        XCTAssertEqual(draft.error, "The conversation changed. Choose the files again.")
        let stored = try await AttachmentDraftStore.shared.items(key: current)
        XCTAssertTrue(stored.isEmpty)
        withExtendedLifetime(source) {}
    }
    func testUploadsExactFileBytesWithoutBearerOrRedirectsWhenFixtureHostIsProvided() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let address = env["T3_NATIVE_ATTACHMENT_TEST_ORIGIN"] ?? env["TEST_RUNNER_T3_NATIVE_ATTACHMENT_TEST_ORIGIN"], let origin = URL(string: address) else { throw XCTSkip("Opt-in local upload transport test.") }
        let source = try sample(), item = item(type: "file", bytes: 17)
        try await AttachmentUploads.upload(file: source.url, item: item, url: origin.appendingPathComponent("api/attachments/upload/ok")) { _ in }
        for path in ["redirect", "reject"] {
            do { try await AttachmentUploads.upload(file: source.url, item: item, url: origin.appendingPathComponent("api/attachments/upload/" + path)) { _ in }; XCTFail("Invalid upload response accepted") }
            catch { XCTAssertTrue(error is ClientError) }
        }
        withExtendedLifetime(source) {}
    }
    func testCancellingAnInFlightUploadStopsTheRequestAndPreservesLocalBytesWhenFixtureHostIsProvided() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let address = env["T3_NATIVE_ATTACHMENT_TEST_ORIGIN"] ?? env["TEST_RUNNER_T3_NATIVE_ATTACHMENT_TEST_ORIGIN"], let origin = URL(string: address) else { throw XCTSkip("Opt-in local upload cancellation test.") }
        let source = try sample(), item = item(type: "file", bytes: 17)
        let (progress, sink) = AsyncStream<Bool>.makeStream()
        let upload = Task {
            try await AttachmentUploads.upload(file: source.url, item: item, url: origin.appendingPathComponent("api/attachments/upload/wait")) { _ in sink.yield(true); sink.finish() }
        }
        let deadline = Task { try await Task.sleep(for: .seconds(10)); sink.finish() }
        defer { deadline.cancel(); upload.cancel() }
        var began = false
        for await value in progress { began = value }
        XCTAssertTrue(began, "Expected a byte-transfer progress callback before cancellation")
        upload.cancel()
        do { try await upload.value; XCTFail("Cancelled upload completed") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        XCTAssertEqual(try Data(contentsOf: source.url), Data("Native T3 upload\n".utf8))
        withExtendedLifetime(source) {}
    }
}
