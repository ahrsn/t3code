import XCTest
import Observation
@testable import T3Native

@MainActor final class PhoneConnectionTests: XCTestCase {
    /// Explicit device provisioning. The normal app pairer writes its own Keychain and preferences.
    func testConnectProvidedPersonalHost() async throws {
        let environment = ProcessInfo.processInfo.environment
        let link = environment["T3_NATIVE_PAIRING_URL"] ?? environment["TEST_RUNNER_T3_NATIVE_PAIRING_URL"] ?? ""
        let reuse = environment["T3_NATIVE_REUSE_SAVED_HOST"] == "1" || environment["TEST_RUNNER_T3_NATIVE_REUSE_SAVED_HOST"] == "1"
        guard !link.isEmpty || reuse else { throw XCTSkip("No personal host provisioning link provided.") }
        let store = AppStore()
        if reuse {
            let host = try XCTUnwrap(store.activeHost, "Expected the already provisioned personal host.")
            store.connect(host)
        } else {
            let paired = await store.pair(link: link, code: "", name: "MacBook Pro")
            XCTAssertTrue(paired, store.error ?? "Pairing failed")
            guard paired else { return }
        }
        let (events, continuation) = AsyncStream<Result<Bool, ClientError>>.makeStream()
        let observer = ConnectionObserver(store: store, continuation: continuation)
        observer.observe()
        let deadline = Task { try await Task.sleep(for: .seconds(30)); continuation.finish() }
        defer { deadline.cancel(); store.disconnect(); withExtendedLifetime(observer) {} }
        var connected = false
        for await event in events { connected = try event.get() }
        XCTAssertTrue(connected, "The saved connection did not load a server snapshot.")
        XCTAssertTrue(store.activeHost?.canOperate == true, "The connection must allow conversation actions.")
        XCTAssertFalse(store.projects.isEmpty, "Expected projects from the personal server.")
        XCTAssertFalse(store.threads.isEmpty, "Expected conversations from the personal server.")
        print("NATIVE_PHONE_CONNECTED projects=\(store.projects.count) conversations=\(store.threads.count)")
        let index = ThreadIndex(threads: store.threads)
        let thread = try XCTUnwrap(index.pinned.first ?? index.working.first ?? index.settled.first)
        await store.selectThread(thread.id)
        try await waitForDetail(store, id: thread.id)
        store.disconnect()
        store.resume()
        XCTAssertEqual(store.conversation?.id, thread.id, "Foreground reconnect must preserve the open conversation.")
        try await waitForDetail(store, id: thread.id)
        print("NATIVE_PHONE_RECONNECTED_DETAIL")

    }
    private func waitForDetail(_ store: AppStore, id: String) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while ContinuousClock.now < deadline {
            if store.connected && store.conversation?.id == id && store.conversation?.projection.hasSnapshot == true { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail(store.error ?? store.conversation?.error ?? "The open conversation did not reload.")
    }

}

@MainActor private final class ConnectionObserver {
    let store: AppStore
    let continuation: AsyncStream<Result<Bool, ClientError>>.Continuation
    init(store: AppStore, continuation: AsyncStream<Result<Bool, ClientError>>.Continuation) {
        self.store = store; self.continuation = continuation
    }
    func observe() {
        withObservationTracking {
            if store.connected { continuation.yield(.success(true)); continuation.finish() }
            else if let error = store.error { continuation.yield(.failure(ClientError(error))); continuation.finish() }
        } onChange: { [weak self] in Task { @MainActor in self?.observe() } }
    }
}
