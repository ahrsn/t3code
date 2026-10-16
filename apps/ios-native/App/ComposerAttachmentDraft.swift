import SwiftUI
import Observation
import PhotosUI

@MainActor @Observable final class ComposerAttachmentDraft {
    var items: [DraftAttachment] = []
    var error: String?
    var busy = false
    @ObservationIgnored private(set) var key = ""
    @ObservationIgnored private var generation = UUID()

    func load(key: String) async {
        let token = UUID(); generation = token; self.key = key
        items = []; error = nil
        do {
            let loaded = try await AttachmentDraftStore.shared.items(key: key)
            if generation == token { items = loaded }
        } catch { if generation == token { self.error = error.localizedDescription } }
    }
    func add(_ urls: [URL], limits: AttachmentLimits, expectedKey: String? = nil) async {
        guard !busy else { return }
        guard expectedKey == nil || expectedKey == key else { error = "The conversation changed. Choose the files again."; return }
        busy = true; defer { busy = false }
        let key = key, token = generation
        for url in urls {
            do {
                let loaded = try await AttachmentDraftStore.shared.importFile(url, key: key, limits: limits)
                if generation == token { items = loaded; error = nil }
            } catch { if generation == token { self.error = error.localizedDescription }; break }
        }
    }
    func addPhotos(_ selection: [PhotosPickerItem], limits: AttachmentLimits, expectedKey: String) async {
        guard !busy else { return }
        guard expectedKey == key else { error = "The conversation changed. Choose the photos again."; return }
        busy = true; defer { busy = false }
        let token = generation, key = key
        for item in selection {
            do {
                let photo = try await PhotoSelection.load(item)
                try Task.checkCancellation()
                guard generation == token else { return }
                let loaded = try await AttachmentDraftStore.shared.importFile(photo.file.url, key: key, limits: limits)
                if generation == token { items = loaded; error = nil }
                withExtendedLifetime(photo) {}
            } catch {
                if generation == token && !Task.isCancelled { self.error = error.localizedDescription }
                break
            }
        }
    }
    func remove(_ item: DraftAttachment) async {
        let key = key, token = generation
        do {
            let loaded = try await AttachmentDraftStore.shared.remove(ids: [item.id], key: key)
            if generation == token { items = loaded; error = nil }
        } catch {
            if generation == token {
                items = (try? await AttachmentDraftStore.shared.items(key: key)) ?? items
                self.error = error.localizedDescription
            }
        }
    }
    func refresh(key: String) async {
        guard self.key == key else { return }
        let token = generation
        do {
            let loaded = try await AttachmentDraftStore.shared.items(key: key)
            if generation == token { items = loaded }
        } catch { if generation == token { self.error = error.localizedDescription } }
    }
}

struct ComposerAttachmentChips: View {
    let draft: ComposerAttachmentDraft
    let disabled: Bool
    @Environment(\.t3Theme) private var theme
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(draft.items) { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.type == "image" ? "photo" : "doc")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).lineLimit(1)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(item.sizeBytes), countStyle: .file)).foregroundStyle(.secondary)
                        }
                        Button { Task { await draft.remove(item) } } label: { Image(systemName: "xmark.circle.fill").frame(width: 28, height: 32).contentShape(.rect) }
                            .accessibilityLabel("Remove \(item.name)").disabled(disabled)
                    }.font(T3Font.caption).padding(8)
                        .background(theme.canvas, in: .rect(cornerRadius: 10))
                        .overlay { RoundedRectangle(cornerRadius: 10).stroke(theme.border, lineWidth: 1).allowsHitTesting(false) }
                }
            }
        }.scrollIndicators(.hidden).accessibilityIdentifier("draft-attachments")
    }
}
