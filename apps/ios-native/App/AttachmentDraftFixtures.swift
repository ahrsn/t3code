import UIKit

#if DEBUG
enum AttachmentDraftFixtures {
    @MainActor static func file(image: Bool, empty: Bool = false) throws -> AttachmentPreviewFile {
        let file = try AttachmentPreviewFile(name: empty ? "Composer empty.txt" : image ? "Composer image.png" : "Composer notes.txt")
        let bytes: Data
        if image {
            let rendered = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 160)).image { context in
                UIColor.systemIndigo.setFill(); context.fill(CGRect(x: 0, y: 0, width: 240, height: 160))
                ("T3 attachment draft" as NSString).draw(at: CGPoint(x: 16, y: 64), withAttributes: [.font: UIFont.systemFont(ofSize: 20), .foregroundColor: UIColor.white])
            }
            bytes = rendered.pngData()!
        } else { bytes = empty ? Data() : Data("Native T3 attachment draft. This is fixture data.\n".utf8) }
        try bytes.write(to: file.url, options: .completeFileProtection)
        return file
    }
}
#endif
