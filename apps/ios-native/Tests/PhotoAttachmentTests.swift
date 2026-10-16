import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import T3Native

@MainActor final class PhotoAttachmentTests: XCTestCase {
    private func image() -> CGImage {
        UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20)).image { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        }.cgImage!
    }
    private func source(type: UTType = .png, name: String = "Photo.png", frames: Int = 1) throws -> AttachmentPreviewFile {
        let file = try AttachmentPreviewFile(name: name)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(file.url as CFURL, type.identifier as CFString, frames, nil))
        for _ in 0..<frames { CGImageDestinationAddImage(destination, image(), [kCGImagePropertyOrientation: 6] as CFDictionary) }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return file
    }
    func testTemporaryProviderFileIsCopiedAndDurableDraftSurvivesItsRelease() async throws {
        let file = try source(type: .jpeg, name: "Photo.jpeg")
        let original = try Data(contentsOf: file.url)
        var photo: PhotoAttachment? = try PhotoAttachment.receive(file.url)
        let owned = try XCTUnwrap(photo?.file.url)
        XCTAssertNotEqual(owned, file.url)
        XCTAssertEqual(try Data(contentsOf: owned), original)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("photo-draft-test-" + UUID().uuidString)
        let drafts = AttachmentDraftStore(root: root)
        let key = "draft.\(UUID().uuidString).photo.attachments"
        let items = try await drafts.importFile(owned, key: key, limits: AttachmentLimits(uploads: true, fileMaximum: nil))
        XCTAssertEqual(items.first?.mimeType, "image/jpeg"); XCTAssertEqual(items.first?.type, "image")
        photo = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path))
        let durable = try await drafts.uploadFile(try XCTUnwrap(items.first), key: key)
        XCTAssertEqual(try Data(contentsOf: durable), original)
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(try XCTUnwrap(CGImageSourceCreateWithURL(durable as CFURL, nil)), 0, nil) as? [String: Any])
        XCTAssertEqual(properties[kCGImagePropertyOrientation as String] as? Int, 6)
        _ = try await drafts.remove(ids: Set(items.map(\.id)), key: key)
        withExtendedLifetime(file) {}
    }
    func testContentDeterminesImageExtensionAndAnimatedGIFBytesArePreserved() throws {
        let png = try source(name: "Misnamed.txt")
        let renamed = try PhotoAttachment.receive(png.url)
        XCTAssertEqual(renamed.file.url.lastPathComponent, "Misnamed.png")
        XCTAssertEqual(try Data(contentsOf: renamed.file.url), try Data(contentsOf: png.url))
        let gif = try source(type: .gif, name: "Animation.gif", frames: 2)
        let photo = try PhotoAttachment.receive(gif.url)
        let decoder = try XCTUnwrap(CGImageSourceCreateWithURL(photo.file.url as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(decoder), 2)
        XCTAssertEqual(try Data(contentsOf: photo.file.url), try Data(contentsOf: gif.url))
        withExtendedLifetime([png, gif, renamed.file, photo.file]) {}
    }
    func testInvalidEmptyOversizedAndSymbolicLinkSourcesAreRejected() throws {
        let invalid = try AttachmentPreviewFile(name: "Invalid.jpg")
        try Data("Not a photo".utf8).write(to: invalid.url)
        XCTAssertThrowsError(try PhotoAttachment.receive(invalid.url))
        let empty = try AttachmentPreviewFile(name: "Empty.png")
        try Data().write(to: empty.url)
        XCTAssertThrowsError(try PhotoAttachment.receive(empty.url))
        let oversized = try AttachmentPreviewFile(name: "Large.png")
        XCTAssertTrue(FileManager.default.createFile(atPath: oversized.url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: oversized.url)
        try handle.truncate(atOffset: UInt64(AttachmentLimits.imageBytes + 1)); try handle.close()
        XCTAssertThrowsError(try PhotoAttachment.receive(oversized.url))
        let original = try source(), link = try AttachmentPreviewFile(name: "Link.png")
        try FileManager.default.createSymbolicLink(at: link.url, withDestinationURL: original.url)
        XCTAssertThrowsError(try PhotoAttachment.receive(link.url))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.url.path))
        withExtendedLifetime([invalid, empty, oversized, original, link]) {}
    }
    func testCancelledTransferDoesNotCopyTheProviderFile() async throws {
        let original = try source()
        let task = Task { try PhotoAttachment.receive(original.url) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled transfer copied a photo") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.url.path))
        withExtendedLifetime(original) {}
    }
    func testCancellingAProviderRequestReleasesALatePhotoAndCancelsProgress() async throws {
        let (requests, sink) = AsyncStream<(PhotoSelection.Completion, Progress)>.makeStream()
        let task = Task { try await PhotoSelection.load { completion in
            let progress = Progress(totalUnitCount: 1)
            sink.yield((completion, progress)); sink.finish()
            return progress
        } }
        var received: (PhotoSelection.Completion, Progress)?
        for await request in requests { received = request; break }
        let (completion, progress) = try XCTUnwrap(received)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled photo request completed") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(progress.isCancelled)
        let original = try source()
        var late: PhotoAttachment? = try PhotoAttachment.receive(original.url)
        let path = try XCTUnwrap(late?.file.url)
        completion(.success(late)); late = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.url.path))
        withExtendedLifetime(original) {}
    }
    func testProviderErrorsAndMissingRepresentationsRemainRecoverable() async {
        do {
            _ = try await PhotoSelection.load { completion in completion(.failure(ClientError("Photo is offline"))); return Progress(totalUnitCount: 1) }
            XCTFail("Provider error was lost")
        } catch { XCTAssertEqual(error.localizedDescription, "Photo is offline") }
        do {
            _ = try await PhotoSelection.load { completion in completion(.success(nil)); return Progress(totalUnitCount: 1) }
            XCTFail("Missing representation was accepted")
        } catch { XCTAssertTrue(error.localizedDescription.contains("Files")) }
    }
    func testTransferRetainsTheActionableValidationFailure() throws {
        let file = try AttachmentPreviewFile(name: "Large.png")
        XCTAssertTrue(FileManager.default.createFile(atPath: file.url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: file.url)
        try handle.truncate(atOffset: UInt64(AttachmentLimits.imageBytes + 1)); try handle.close()
        let transfer = try PhotoTransfer.receive(file.url)
        switch transfer.result {
        case .success: XCTFail("Oversized transfer was accepted")
        case .failure(let error): XCTAssertEqual(error.localizedDescription, "Choose a photo no larger than 10 MiB.")
        }
        withExtendedLifetime(file) {}
    }
}
