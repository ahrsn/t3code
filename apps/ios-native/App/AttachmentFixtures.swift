import UIKit

#if DEBUG
@MainActor enum AttachmentFixtures {
    static let rows: [JSONValue] = [
        .object(["id": .string("attachment-message"), "type": .string("user_message"), "text": .string("Review these files."), "attachments": .array([
            attachment("preview-pdf", "Notes.pdf", "application/pdf", "file"),
            attachment("preview-image", "Layout.png", "image/png", "image"),
            attachment("preview-retry", "Connection.txt", "text/plain", "file"),
            attachment("preview-unknown", "Future attachment", "application/octet-stream", "future")
        ])])
    ]
    private static func attachment(_ id: String, _ name: String, _ mime: String, _ type: String) -> JSONValue {
        .object(["id": .string(id), "type": .string(type), "name": .string(name), "mimeType": .string(mime), "sizeBytes": .number(2048)])
    }
    static func preview(_ attachment: AttachmentReference, attempts: inout Set<String>) throws -> AttachmentPreviewFile {
        guard attachment.id.hasPrefix("preview-") else { throw ClientError("No preview fixture exists for this attachment.") }
        if attachment.id == "preview-retry", !attempts.contains(attachment.id) {
            attempts.insert(attachment.id)
            throw ClientError("The attachment is unavailable. Retry to request a fresh link.")
        }
        let file = try AttachmentPreviewFile(name: attachment.localName)
        let text = "T3 Code\n\nNative attachment preview\n\nThis document is fixture data.\n\nThe conversation remains connected while a file is open."
        if attachment.mimeType == "application/pdf" {
            try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).writePDF(to: file.url) { context in
                context.beginPage()
                (text as NSString).draw(in: CGRect(x: 48, y: 54, width: 516, height: 680), withAttributes: [.font: UIFont.systemFont(ofSize: 22), .foregroundColor: UIColor.black])
            }
        } else if attachment.type == "image" {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 400)).image { context in
                UIColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1).setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
                ("T3 Code\n\nAttachment fixture" as NSString).draw(in: CGRect(x: 40, y: 60, width: 520, height: 280), withAttributes: [.font: UIFont.systemFont(ofSize: 36, weight: .medium), .foregroundColor: UIColor.white])
            }
            try image.pngData()!.write(to: file.url)
        } else { try Data(text.utf8).write(to: file.url) }
        return file
    }
}
#endif
