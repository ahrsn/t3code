import SwiftUI
import QuickLook

struct AttachmentPreviewRequest: Identifiable {
    let id = UUID()
    let attachment: AttachmentReference
    let hostID: UUID?
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
                        .navigationTitle(request.attachment.displayName).navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                }
            }
        }
        .task(id: revision) {
            error = nil
            do {
                let loaded = try await store.previewAttachment(request.attachment, hostID: request.hostID)
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
