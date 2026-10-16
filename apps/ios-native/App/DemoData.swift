import Foundation

#if DEBUG
extension AppStore {
    func loadDemo(threadID: String = "t0") {
        isDemo = true; phase = "Preview data"
        config = try! JSONValue.decode(Data(#"""
        {"providers":[{"instanceId":"codex","driver":"codex","displayName":"Codex","enabled":true,"installed":true,"auth":{"status":"authenticated"},"models":[
          {"slug":"gpt-6.1-sol","name":"GPT-6.1 Sol","isDefault":true,"capabilities":{"optionDescriptors":[
            {"id":"effort","label":"Reasoning effort","type":"select","currentValue":"high","options":[{"id":"low","label":"Low"},{"id":"high","label":"High","isDefault":true},{"id":"max","label":"Max"}]},
            {"id":"fastMode","label":"Fast mode","type":"boolean","currentValue":false}]}},
          {"slug":"gpt-6-astra","name":"GPT-6 Astra","capabilities":{"optionDescriptors":[]}}]},
          {"instanceId":"claudeAgent","driver":"claudeAgent","displayName":"Claude","enabled":true,"installed":true,"auth":{"status":"authenticated"},"models":[{"slug":"claude-sonnet-4-6","name":"Claude Sonnet 4.6"}]}]}
        """#.utf8))
        let projects = [
            JSONValue.object(["id": .string("p1"), "title": .string("t3code")]),
            .object(["id": .string("p2"), "title": .string("Personal website")])
        ]
        let entries: [(String, String, String, String)] = [
            ("Build a native iOS client", "Keep the T3 layout and typography.", "running", "p1"),
            ("Review the reconnect behavior", "Can I run the reconnect test against your development server?", "waiting", "p1"),
            ("Simplify the project navigation", "Project filters and search are ready to try.", "completed", "p1"),
            ("Update the homepage", "The new layout is ready for a first look.", "completed", "p2")
        ]
        var threads: [JSONValue] = []
        for (index, entry) in entries.enumerated() {
            threads.append(.object(["id": .string("t\(index)"), "title": .string(entry.0), "projectId": .string(entry.3), "status": .string(entry.2),
                                    "modelSelection": .object(["instanceId": .string("codex"), "model": .string("gpt-6.1-sol")]),
                                    "latestVisibleMessage": .object(["text": .string(entry.1)]),
                                    "updatedAt": .string("2026-10-16T00:10:00Z"), "activeRunId": index == 0 ? .string("r1") : .null,
                                    "branch": .string(index == 3 ? "main" : "feat/native-ios-client"), "settledOverride": index > 1 ? .string("settled") : .null, "settledAt": index > 1 ? .string("2026-10-16T00:00:00Z") : .null, "runtimeMode": .string("approval-required"),
                                    "pendingRuntimeRequest": index == 1 ? .object(["id": .string("request1")]) : .null]))
        }
        shell.apply(.object(["kind": .string("snapshot"), "snapshot": .object(["snapshotSequence": .number(10), "projects": .array(projects), "threads": .array(threads)])]))
        let detail = Conversation(id: threadID)
        var rows: [JSONValue] = [
            .object(["id": .string("i1"), "type": .string("user_message"), "text": .string("Keep the T3 branding and fonts. I want the same threads and conversations, with native iOS controls.")]),
            .object(["id": .string("i2"), "type": .string("assistant_message"), "text": .string("The client uses the same T3 protocol and DM Sans. Threads stay grouped into Working and Settled.\n\nYou can adjust the text size and spacing in Appearance. The composer stays above the keyboard, and code blocks scroll horizontally.\n\n```swift\nText(message.text)\n    .font(T3Font.body)\n    .textSelection(.enabled)\n```\n\nThe server connection stays compatible with your existing T3 hosts.")]),
            .object(["id": .string("i3"), "type": .string("command_execution"), "title": .string("Build iOS app"), "input": .string("xcodebuild -scheme T3Native build"), "output": .string("BUILD SUCCEEDED")]),
            .object(["id": .string("i4"), "type": .string("approval_request"), "requestId": .string("request1"), "prompt": .string("Run the connection tests against the development server?")])
        ]
        if ProcessInfo.processInfo.arguments.contains("--markdown-demo") {
            rows = [
                .object(["id": .string("md-user"), "type": .string("user_message"), "text": .string("Show the reconnect implementation and verification notes.")]),
                .object(["id": .string("md-assistant"), "type": .string("assistant_message"), "text": .string(MarkdownFixtures.document)])
            ]
        }
        if ProcessInfo.processInfo.arguments.contains("--attachments-demo") { rows = AttachmentFixtures.rows }
        let historyDemo = ProcessInfo.processInfo.arguments.contains("--history-demo")
        if historyDemo { rows = HistoryFixtures.items(16..<24) }
        detail.apply(.object(["hasMoreHistory": .bool(historyDemo), "historyCursor": historyDemo ? .string("16") : .null, "kind": .string("snapshot"), "snapshotSequence": .number(10), "projection": .object([
            "thread": threads.first(where: { $0.id == threadID }) ?? threads[0], "turnItems": .array(rows), "runtimeRequests": .array([
                .object(["id": .string("request1"), "status": .string("pending"), "responseCapability": .object(["type": .string("live")])])
            ])
        ])]))
        conversation = detail
    }
}
#endif
