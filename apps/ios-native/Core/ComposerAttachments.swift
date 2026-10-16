import Foundation
import CryptoKit
import UniformTypeIdentifiers

struct DraftAttachment: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let mimeType: String
    let type: String
    let sizeBytes: Int
    var uploadedID: String?

    func reference(id: String) -> JSONValue {
        .object(["id": .string(id), "name": .string(name), "type": .string(type),
                 "mimeType": .string(mimeType), "sizeBytes": .number(Double(sizeBytes))])
    }
}

struct AttachmentLimits: Sendable {
    static let imageBytes = 10 * 1024 * 1024
    static let fileBytes = 50 * 1024 * 1024
    static let totalImageBytes = 80 * 1024 * 1024
    static let imageTypes: Set<String> = ["image/png", "image/jpeg", "image/gif", "image/webp"]
    let uploads: Bool
    let fileMaximum: Int?

    init(config: JSONValue) {
        let capabilities = config["environment"]["capabilities"]
        uploads = capabilities["attachmentUploads"].bool
        let advertised = capabilities["fileAttachments"]["maxUploadBytes"].int
        fileMaximum = advertised > 0 ? min(advertised, Self.fileBytes) : nil
    }
    init(uploads: Bool, fileMaximum: Int?) {
        self.uploads = uploads
        self.fileMaximum = fileMaximum.map { min($0, Self.fileBytes) }
    }
    func validate(_ attachments: [DraftAttachment]) throws {
        guard uploads else { throw ClientError("This server does not support attachment uploads.") }
        guard attachments.count <= 100 else { throw ClientError("You can attach up to 100 files per message.") }
        var images = 0
        for item in attachments {
            let maximum: Int
            if item.type == "image" {
                guard Self.imageTypes.contains(item.mimeType) else { throw ClientError("This image format is not supported.") }
                maximum = Self.imageBytes
            } else {
                guard item.type == "file", let fileMaximum else { throw ClientError("This server does not support file attachments.") }
                maximum = fileMaximum
            }
            guard item.sizeBytes > 0 else { throw ClientError("'\(item.name)' is empty.") }
            guard item.sizeBytes <= maximum else {
                throw ClientError("'\(item.name)' exceeds the \(ByteCountFormatter.string(fromByteCount: Int64(maximum), countStyle: .file)) attachment limit.")
            }
            if item.type == "image" { images += item.sizeBytes }
        }
        guard images <= Self.totalImageBytes else { throw ClientError("Images can total up to 80 MiB per message.") }
    }
}

struct AttachmentSendAttempt: Codable, Equatable, Sendable {
    let fingerprint: String
    let commandID: String
    let messageID: String
}

/// Imported bytes belong to one draft. Only UUID-named files in its hashed directory are removed.
actor AttachmentDraftStore {
    static let shared = AttachmentDraftStore()
    private let root: URL
    private var removedHosts: Set<UUID> = []
    private struct Manifest: Codable {
        var items: [DraftAttachment] = []
        var attempt: AttachmentSendAttempt?
        var hostID: UUID?
    }
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("T3AttachmentDrafts", isDirectory: true)
    }
    private func directory(_ key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(hash, isDirectory: true)
    }
    private func hostID(_ key: String) -> UUID? {
        guard key.hasPrefix("draft."), key.hasSuffix(".attachments") else { return nil }
        let part = key.dropFirst(6)
        guard part.count > 36, part.dropFirst(36).first == "." else { return nil }
        return UUID(uuidString: String(part.prefix(36)))
    }
    private func checkAvailable(_ key: String) throws {
        if let id = hostID(key), removedHosts.contains(id) { throw ClientError("This server was removed. Choose a connected server before attaching files.") }
    }
    private func file(_ item: DraftAttachment, key: String) throws -> URL {
        guard UUID(uuidString: item.id) != nil else { throw ClientError("The saved attachment is invalid. Remove it and attach the file again.") }
        return directory(key).appendingPathComponent(item.id)
    }
    private func read(_ key: String) throws -> Manifest {
        let path = directory(key).appendingPathComponent("draft.json")
        guard FileManager.default.fileExists(atPath: path.path) else { return Manifest() }
        let data = try Data(contentsOf: path)
        guard data.count <= 256 * 1024 else { throw ClientError("The saved attachment draft is invalid.") }
        var manifest = try JSONDecoder().decode(Manifest.self, from: data)
        // Earlier drafts did not record ownership. Attribute them only when their
        // original key is known, never by guessing from another server's files.
        if manifest.hostID == nil, let id = hostID(key) {
            manifest.hostID = id
            try write(manifest, key: key)
        }
        return manifest
    }
    private func write(_ manifest: Manifest, key: String) throws {
        try checkAvailable(key)
        var manifest = manifest; manifest.hostID = hostID(key)
        let dir = directory(key)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var excluded = dir; try excluded.setResourceValues(values)
        try JSONEncoder().encode(manifest).write(to: dir.appendingPathComponent("draft.json"), options: [.atomic, .completeFileProtection])
    }
    func items(key: String) throws -> [DraftAttachment] { try read(key).items }

    func importFile(_ source: URL, key: String, limits: AttachmentLimits) throws -> [DraftAttachment] {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<[DraftAttachment], Error>?
        NSFileCoordinator().coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { url in
            result = Result { try copyFile(url, key: key, limits: limits) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw ClientError("The selected file could not be opened.") }
        return try result.get()
    }
    private func copyFile(_ source: URL, key: String, limits: AttachmentLimits) throws -> [DraftAttachment] {
        try Task.checkCancellation()
        try checkAvailable(key)
        let info = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentTypeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true else { throw ClientError("Choose a regular file.") }
        let mime = info.contentType?.preferredMIMEType ?? UTType(filenameExtension: source.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let name = AttachmentReference(.object(["name": .string(source.lastPathComponent), "mimeType": .string(mime)])).localName
        let item = DraftAttachment(id: UUID().uuidString.lowercased(), name: name, mimeType: mime,
                                   type: AttachmentLimits.imageTypes.contains(mime) ? "image" : "file", sizeBytes: info.fileSize ?? 0)
        var manifest = try read(key)
        try limits.validate(manifest.items + [item])
        let target = try file(item, key: key)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        guard FileManager.default.createFile(atPath: target.path, contents: nil, attributes: [.protectionKey: FileProtectionType.complete]) else { throw ClientError("The attachment could not be saved.") }
        do {
            let input = try FileHandle(forReadingFrom: source); defer { try? input.close() }
            let output = try FileHandle(forWritingTo: target); defer { try? output.close() }
            var count = 0
            while let data = try input.read(upToCount: 64 * 1024), !data.isEmpty {
                try Task.checkCancellation()
                count += data.count
                guard count <= item.sizeBytes else { throw ClientError("The file changed while it was being attached. Choose it again.") }
                try output.write(contentsOf: data)
            }
            guard count == item.sizeBytes else { throw ClientError("The file changed while it was being attached. Choose it again.") }
            manifest.items.append(item); manifest.attempt = nil
            try write(manifest, key: key)
            return manifest.items
        } catch { try? FileManager.default.removeItem(at: target); throw error }
    }
    func uploadFile(_ item: DraftAttachment, key: String) throws -> URL {
        let url = try file(item, key: key)
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true, info.fileSize == item.sizeBytes else {
            throw ClientError("'\(item.name)' is no longer available. Remove it and attach the file again.")
        }
        return url
    }
    func markUploaded(_ item: DraftAttachment, uploadID: String, key: String) throws {
        var manifest = try read(key)
        guard let index = manifest.items.firstIndex(where: { $0.id == item.id }) else { throw CancellationError() }
        manifest.items[index].uploadedID = uploadID
        try write(manifest, key: key)
    }
    func attempt(key: String, text: String, model: JSONValue?, attachments: [DraftAttachment]) throws -> AttachmentSendAttempt {
        let payload = JSONValue.object(["text": .string(text), "model": model ?? .null, "files": .array(attachments.map { .string($0.id) })])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let fingerprint = SHA256.hash(data: try encoder.encode(payload)).map { String(format: "%02x", $0) }.joined()
        var manifest = try read(key)
        if let attempt = manifest.attempt, attempt.fingerprint == fingerprint { return attempt }
        let attempt = AttachmentSendAttempt(fingerprint: fingerprint, commandID: UUID().uuidString, messageID: UUID().uuidString)
        manifest.attempt = attempt; try write(manifest, key: key)
        return attempt
    }
    func remove(ids: Set<String>, key: String, confirmedAttempt: String? = nil) throws -> [DraftAttachment] {
        var manifest = try read(key)
        let removed = manifest.items.filter { ids.contains($0.id) }
        manifest.items.removeAll { ids.contains($0.id) }
        if confirmedAttempt == nil || manifest.attempt?.commandID == confirmedAttempt { manifest.attempt = nil }
        try write(manifest, key: key)
        for item in removed {
            let url = try file(item, key: key)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
        return manifest.items
    }

    /// Unlinks regular UUID-named files and our manifest, then only an empty directory.
    /// Unassigned legacy drafts and unrecognized files are preserved.
    func discard(hostID: UUID) throws -> Int {
        removedHosts.insert(hostID)
        do {
            guard FileManager.default.fileExists(atPath: root.path) else { return 0 }
            let directories = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            var unassigned = 0
            for directory in directories {
                let kind = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard directory.lastPathComponent.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
                      kind.isDirectory == true, kind.isSymbolicLink != true else { continue }
                let path = directory.appendingPathComponent("draft.json")
                guard FileManager.default.fileExists(atPath: path.path) else { continue }
                let info = try path.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard info.isRegularFile == true, info.isSymbolicLink != true, (info.fileSize ?? .max) <= 256 * 1024 else { continue }
                // A malformed or unassigned manifest cannot authorize a deletion.
                guard let manifest = try? JSONDecoder().decode(Manifest.self, from: Data(contentsOf: path)) else { unassigned += 1; continue }
                if manifest.hostID == nil { unassigned += manifest.items.count; continue }
                guard manifest.hostID == hostID else { continue }
                for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
                    guard UUID(uuidString: file.lastPathComponent) != nil else { continue }
                    let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    if info.isRegularFile == true, info.isSymbolicLink != true { try FileManager.default.removeItem(at: file) }
                }
                try FileManager.default.removeItem(at: path)
                if try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty { try FileManager.default.removeItem(at: directory) }
            }
            return unassigned
        } catch { removedHosts.remove(hostID); throw error }
    }
}

enum AttachmentUploads {
    static func uploadURL(relative: String, origin: URL) throws -> URL {
        guard relative.hasPrefix("/api/attachments/upload/"), !relative.contains("\\"),
              let url = URL(string: relative, relativeTo: origin)?.absoluteURL,
              AttachmentDownloads.sameOrigin(url, origin), url.path.hasPrefix("/api/attachments/upload/"),
              url.user == nil, url.password == nil, url.fragment == nil else { throw ClientError("The server returned an invalid upload address.") }
        return url
    }
    static func upload(file: URL, item: DraftAttachment, url: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        try Task.checkCancellation()
        let policy = AttachmentUploadPolicy(progress: progress)
        let config = URLSessionConfiguration.ephemeral; config.urlCache = nil; config.httpCookieStorage = nil
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
        request.httpMethod = "POST"; request.setValue(item.mimeType, forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.upload(for: request, fromFile: file, delegate: policy)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw ClientError("'\(item.name)' could not be uploaded. Try sending again.") }
    }
}

private final class AttachmentUploadPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let progress: @Sendable (Double) -> Void
    init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if totalBytesExpectedToSend > 0 { progress(min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend))) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
