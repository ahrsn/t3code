import Foundation

extension AppStore {
    static func forLaunch() -> AppStore {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--host-removal-preview") { return HostRemovalFixtures.makeStore() }
        #endif
        return AppStore()
    }
}

#if DEBUG
@MainActor private enum HostRemovalFixtures {
    static func makeStore() -> AppStore {
        let suite = "com.ahrsn.t3native.removal-preview"
        let preferences = UserDefaults(suiteName: suite)!
        preferences.removePersistentDomain(forName: suite)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("t3-removal-preview-" + UUID().uuidString)
        let drafts = AttachmentDraftStore(root: root)
        let store = AppStore(attachmentDraftStore: drafts, preferences: preferences)
        let alpha = SavedHost(name: "Alpha server", origin: URL(string: "https://alpha.invalid")!)
        let beta = SavedHost(name: "Beta server", origin: URL(string: "https://beta.invalid")!)
        store.isDemo = true; store.hosts = [alpha, beta]; store.activeHostID = beta.id; store.phase = "Preparing preview"
        preferences.set(try? JSONEncoder().encode(store.hosts), forKey: "hosts")
        preferences.set(beta.id.uuidString, forKey: "activeHost")
        Task {
            do {
                let sample = try AttachmentPreviewFile(name: "Draft.txt")
                try Data("Server removal fixture".utf8).write(to: sample.url)
                let limits = AttachmentLimits(uploads: true, fileMaximum: 1024)
                for host in [alpha, beta] {
                    let key = "draft.\(host.id.uuidString).thread.attachments"
                    _ = try await drafts.importFile(sample.url, key: key, limits: limits)
                    preferences.set("Saved text", forKey: "draft.\(host.id.uuidString).thread")
                }
                if ProcessInfo.processInfo.arguments.contains("--legacy-removal-preview") {
                    _ = try await drafts.importFile(sample.url, key: "unassigned-legacy", limits: limits)
                }
                if ProcessInfo.processInfo.arguments.contains("--failed-removal-preview") {
                    // Preserve every fixture file while making the configured root unreadable as a directory.
                    try FileManager.default.moveItem(at: root, to: root.appendingPathExtension("preserved"))
                    try Data("Unavailable draft directory".utf8).write(to: root)
                }
                withExtendedLifetime(sample) {}
                store.phase = "Preview data"
            } catch { store.error = error.localizedDescription }
        }
        return store
    }
}
#endif
