import XCTest
import PDFKit
@testable import T3Native

final class AttachmentPreviewTests: XCTestCase {
    private func attachment(name: String = "Notes.txt", type: String = "file", size: Int = 20) -> AttachmentReference {
        AttachmentReference(.object(["id": .string("upload_1"), "type": .string(type), "name": .string(name), "mimeType": .string("text/plain"), "sizeBytes": .number(Double(size))]))
    }
    func testOnlySignedAssetPathsOnTheOriginalHostAreAccepted() throws {
        let origin = URL(string: "https://host.example:8443")!
        XCTAssertEqual(try AttachmentDownloads.assetURL(relative: "/api/assets/signed/notes.txt", origin: origin).host, "host.example")
        for path in ["https://other.example/api/assets/signed", "//other.example/api/assets/signed", "/api/other", "/api/assets/../../oauth/token", "/api/assets/\\other", "/api/assets/signed#fragment"] {
            XCTAssertThrowsError(try AttachmentDownloads.assetURL(relative: path, origin: origin), path)
        }
        XCTAssertFalse(AttachmentDownloads.sameOrigin(URL(string: "https://host.example")!, origin))
        XCTAssertFalse(AttachmentDownloads.sameOrigin(URL(string: "http://host.example:8443")!, origin))
        XCTAssertTrue(AttachmentDownloads.sameOrigin(URL(string: "https://HOST.example:8443")!, origin))
        XCTAssertTrue(AttachmentDownloads.sameOrigin(URL(string: "https://host.example:443")!, URL(string: "https://host.example")!))
    }
    func testMetadataNamesStayWithinTheOwnedPreviewDirectory() throws {
        let item = attachment(name: "../../folder\\Notes.txt")
        XCTAssertEqual(item.localName, "Notes.txt")
        XCTAssertEqual(item.resource["attachmentId"].string, "upload_1")
        XCTAssertEqual(item.resource["_tag"].string, "attachment")
        XCTAssertEqual(attachment(name: "..").localName, "Attachment.txt")
        XCTAssertLessThanOrEqual(attachment(name: String(repeating: "🧑🏾‍💻", count: 100)).localName.utf8.count, 210)
        XCTAssertFalse(attachment(type: "future").canPreview)
        XCTAssertThrowsError(try AttachmentPreviewFile(name: "../escape"))
    }
    func testReleasingPreviewDeletesOnlyItsOwnedFileAndEmptyDirectory() throws {
        var file: AttachmentPreviewFile? = try AttachmentPreviewFile(name: "notes.txt")
        let url = try XCTUnwrap(file?.url)
        try Data("Sample".utf8).write(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        file = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
    }
    @MainActor func testPDFPreviewFixtureContainsAnActualDocumentPage() throws {
        var attempts: Set<String> = []
        let item = AttachmentReference(.object(["id": .string("preview-pdf"), "name": .string("Notes.pdf"), "type": .string("file"), "mimeType": .string("application/pdf")]))
        let file = try AttachmentFixtures.preview(item, attempts: &attempts)
        let document = try XCTUnwrap(PDFDocument(url: file.url))
        XCTAssertEqual(document.pageCount, 1)
        XCTAssertTrue(document.string?.contains("Native attachment preview") == true)
    }
    func testOversizedMetadataIsRejectedBeforeConnecting() async throws {
        do {
            _ = try await AttachmentDownloads().download(url: URL(string: "http://127.0.0.1:1/api/assets/no-network")!, attachment: attachment(size: 52_428_801))
            XCTFail("Oversized attachment should not start a request")
        } catch { XCTAssertEqual(error.localizedDescription, "This attachment exceeds the 50 MB preview limit.") }
    }
    func testDownloadRedirectLimitsAndCleanupWhenFixtureHostIsProvided() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let address = env["T3_NATIVE_ATTACHMENT_TEST_ORIGIN"] ?? env["TEST_RUNNER_T3_NATIVE_ATTACHMENT_TEST_ORIGIN"], let origin = URL(string: address) else {
            throw XCTSkip("Opt-in local HTTP fixture download check.")
        }
        for path in ["ok", "redirect-local"] {
            var file: AttachmentPreviewFile? = try await AttachmentDownloads(byteLimit: 1024).download(url: origin.appendingPathComponent("api/assets/" + path), attachment: attachment())
            let url = try XCTUnwrap(file?.url)
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Native attachment download")
            file = nil
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
        for path in ["redirect-external", "too-large", "not-found"] {
            do {
                _ = try await AttachmentDownloads(byteLimit: 1024).download(url: origin.appendingPathComponent("api/assets/" + path), attachment: attachment())
                XCTFail("Invalid response accepted for \(path)")
            } catch { XCTAssertFalse(error is CancellationError) }
        }
    }
}
