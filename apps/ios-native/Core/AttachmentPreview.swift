import Foundation
import UniformTypeIdentifiers

struct AttachmentReference: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let mimeType: String
    let sizeBytes: Int
    let type: String

    init(_ value: JSONValue) {
        id = value.id; name = value["name"].string
        mimeType = value["mimeType"].string; sizeBytes = value["sizeBytes"].int
        type = value["type"].string
    }
    var canPreview: Bool { !id.isEmpty && ["image", "file"].contains(type) }
    var displayName: String { name.isEmpty ? "Attachment" : name }
    var resource: JSONValue {
        var fields: [String: JSONValue] = ["_tag": .string("attachment"), "attachmentId": .string(id), "disposition": .string("attachment")]
        if !name.isEmpty { fields["fileName"] = .string(String(name.prefix(255))) }
        if !mimeType.isEmpty { fields["mimeType"] = .string(String(mimeType.prefix(100))) }
        return .object(fields)
    }
    var localName: String {
        let base = name.replacingOccurrences(of: "\\", with: "/").components(separatedBy: "/").last ?? ""
        let cleaned = String(base.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(200))
        var safe = ["", ".", ".."].contains(cleaned) ? "Attachment" : cleaned
        while safe.utf8.count > 200 { safe.removeLast() }
        if (safe as NSString).pathExtension.isEmpty,
           let suffix = UTType(mimeType: mimeType)?.preferredFilenameExtension { return safe + "." + suffix }
        return safe
    }
}

/// A preview owns only its downloaded file and the empty directory created for it.
final class AttachmentPreviewFile: @unchecked Sendable {
    let url: URL
    init(name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", (name as NSString).lastPathComponent == name else {
            throw ClientError("The attachment filename is invalid.")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("t3-preview-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.protectionKey: FileProtectionType.complete])
        url = directory.appendingPathComponent(name)
    }
    deinit {
        try? FileManager.default.removeItem(at: url)
        let directory = url.deletingLastPathComponent()
        if (try? FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty) == true {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

actor AttachmentDownloads {
    static let maximumBytes: Int64 = 50 * 1024 * 1024
    private let byteLimit: Int64
    init(byteLimit: Int64 = AttachmentDownloads.maximumBytes) { self.byteLimit = byteLimit }

    static func assetURL(relative: String, origin: URL) throws -> URL {
        guard relative.hasPrefix("/api/assets/"), !relative.contains("\\"),
              let url = URL(string: relative, relativeTo: origin)?.absoluteURL,
              sameOrigin(url, origin), url.path.hasPrefix("/api/assets/"),
              url.user == nil, url.password == nil, url.fragment == nil else {
            throw ClientError("The server returned an invalid attachment address.")
        }
        return url
    }
    static func sameOrigin(_ left: URL, _ right: URL) -> Bool {
        func port(_ url: URL) -> Int? { url.port ?? (url.scheme == "https" ? 443 : url.scheme == "http" ? 80 : nil) }
        return ["https", "http"].contains(left.scheme) && left.scheme == right.scheme && left.host?.lowercased() == right.host?.lowercased() && port(left) == port(right)
    }
    func download(url: URL, attachment: AttachmentReference) async throws -> AttachmentPreviewFile {
        guard attachment.canPreview else { throw ClientError("This attachment type is not supported by this build.") }
        try Task.checkCancellation()
        guard attachment.sizeBytes <= byteLimit else { throw ClientError("This attachment exceeds the 50 MB preview limit.") }
        let policy = AttachmentDownloadPolicy(origin: url, maximumBytes: byteLimit)
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.setValue("application/octet-stream, */*", forHTTPHeaderField: "Accept")
        let temporary: URL
        let response: URLResponse
        do { (temporary, response) = try await session.download(for: request, delegate: policy) }
        catch {
            if Task.isCancelled { throw CancellationError() }
            throw ClientError("The attachment download failed. Try again.")
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ClientError("The attachment is unavailable. Retry to request a fresh link.")
        }
        let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= byteLimit else { throw ClientError("This attachment exceeds the 50 MB preview limit.") }
        let file = try AttachmentPreviewFile(name: attachment.localName)
        try FileManager.default.moveItem(at: temporary, to: file.url)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: file.url.path)
        try Task.checkCancellation()
        return file
    }
}

private final class AttachmentDownloadPolicy: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let origin: URL
    let maximumBytes: Int64
    init(origin: URL, maximumBytes: Int64) { self.origin = origin; self.maximumBytes = maximumBytes }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url.map { AttachmentDownloads.sameOrigin($0, origin) } == true ? request : nil)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > maximumBytes || totalBytesExpectedToWrite > maximumBytes { downloadTask.cancel() }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
