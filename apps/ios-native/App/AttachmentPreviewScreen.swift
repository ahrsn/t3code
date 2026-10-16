import SwiftUI
import QuickLook

struct AttachmentPreviewRequest: Identifiable {
    enum Source {
        case sent(AttachmentReference)
        case draft(DraftAttachment, key: String)
    }
    let id = UUID()
    let source: Source
    let hostID: UUID?
    init(attachment: AttachmentReference, hostID: UUID?) { source = .sent(attachment); self.hostID = hostID }
    init(draft: DraftAttachment, key: String, hostID: UUID?) { source = .draft(draft, key: key); self.hostID = hostID }
    var name: String {
        switch source {
        case .sent(let attachment): attachment.displayName
        case .draft(let attachment, _): attachment.name
        }
    }
}

struct AttachmentPreviewScreen: View {
    let request: AttachmentPreviewRequest
    let store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.t3Theme) private var theme
    @State private var file: AttachmentPreviewFile?
    @State private var error: String?
    @State private var revision = 0

    var body: some View {
        ZStack {
            if let file {
                NativeFilePreview(file: file) { dismiss() }.ignoresSafeArea()
            } else {
                NavigationStack {
                    VStack(spacing: 16) {
                        if let error {
                            Text(error).font(T3Font.body).multilineTextAlignment(.center)
                            Button("Retry") { revision += 1 }.buttonStyle(.glass)
                        } else { ProgressView("Loading attachment") }
                    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(theme.canvas).foregroundStyle(theme.text)
                        .navigationTitle(request.name).navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                }
            }
        }
        .task(id: revision) {
            error = nil
            do {
                let loaded: AttachmentPreviewFile
                switch request.source {
                case .sent(let attachment): loaded = try await store.previewAttachment(attachment, hostID: request.hostID)
                case .draft(let attachment, let key): loaded = try await AttachmentDraftStore.shared.previewFile(id: attachment.id, key: key)
                }
                guard !Task.isCancelled else { return }
                file = loaded
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
}

private struct NativeFilePreview: UIViewControllerRepresentable {
    let file: AttachmentPreviewFile
    let close: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(file: file, close: close) }
    func makeUIViewController(context: Context) -> UINavigationController {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        preview.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: context.coordinator, action: #selector(Coordinator.done))
        return UINavigationController(rootViewController: preview)
    }
    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let file: AttachmentPreviewFile
        let close: () -> Void
        init(file: AttachmentPreviewFile, close: @escaping () -> Void) { self.file = file; self.close = close }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { file.url as NSURL }
        @objc func done() { close() }
    }
}
