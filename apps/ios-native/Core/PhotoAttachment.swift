import Foundation
import CoreTransferable
import UniformTypeIdentifiers
import ImageIO

struct PhotoTransfer: Transferable, Sendable {
    let result: Result<PhotoAttachment, ClientError>

    // Validation failures are values here: Photos wraps errors thrown by an
    // importer, which otherwise hides the actionable size/format message.
    static func receive(_ source: URL) throws -> PhotoTransfer {
        do { return PhotoTransfer(result: .success(try PhotoAttachment.receive(source))) }
        catch is CancellationError { throw CancellationError() }
        catch { return PhotoTransfer(result: .failure(ClientError(error.localizedDescription))) }
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .png) { try receive($0.file) }
        FileRepresentation(importedContentType: .jpeg) { try receive($0.file) }
        FileRepresentation(importedContentType: .gif) { try receive($0.file) }
        FileRepresentation(importedContentType: .webP) { try receive($0.file) }
    }
}

struct PhotoAttachment: Sendable {
    let file: AttachmentPreviewFile

    // The provider's URL is temporary. Own a bounded disk copy before returning
    // from the transfer callback, then release it after the durable draft import.
    static func receive(_ source: URL) throws -> PhotoAttachment {
        try Task.checkCancellation()
        let info = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true else { throw ClientError("The selected photo could not be opened.") }
        let size = info.fileSize ?? 0
        guard size > 0, size <= AttachmentLimits.imageBytes else { throw ClientError("Choose a photo no larger than 10 MiB.") }
        guard let image = CGImageSourceCreateWithURL(source as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(image) > 0, let identifier = CGImageSourceGetType(image),
              let type = UTType(identifier as String), let mime = type.preferredMIMEType,
              AttachmentLimits.imageTypes.contains(mime), let suffix = type.preferredFilenameExtension else {
            throw ClientError("This photo format is unavailable. Choose a JPEG, PNG, GIF, or WebP image.")
        }
        let name = AttachmentReference(.object(["name": .string(source.deletingPathExtension().lastPathComponent + "." + suffix), "mimeType": .string(mime)])).localName
        let file = try AttachmentPreviewFile(name: name)
        try FileManager.default.copyItem(at: source, to: file.url)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: file.url.path)
        try Task.checkCancellation()
        guard try file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize == size else { throw ClientError("The photo changed while loading. Choose it again.") }
        return PhotoAttachment(file: file)
    }
}
