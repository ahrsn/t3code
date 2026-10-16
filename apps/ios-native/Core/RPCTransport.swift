import Foundation

/// Effect RPC JSON framing, matching packages/effect/src/rpc/RpcMessage.ts.
actor RPCTransport {
    typealias Sink = @Sendable (JSONValue) async -> Void
    private var socket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var handlers: [String: Sink] = [:]
    private var pending: [String: CheckedContinuation<JSONValue, Error>] = [:]
    private var timeouts: [String: Task<Void, Never>] = [:]
    private var sequence = 0
    private var heartbeat: Task<Void, Never>?
    private var lastFrameAt = Date()
    private var interruption: (any Error)?

    func run(url: URL, ready: @escaping @Sendable () async throws -> Void) async throws {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        let session = URLSession(configuration: config)
        self.session = session
        let socket = session.webSocketTask(with: url)
        socket.maximumMessageSize = 32 * 1024 * 1024
        self.socket = socket
        interruption = nil; lastFrameAt = Date()
        socket.resume()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(5))
                    try await self?.tick()
                } catch { return }
            }
        }
        // Start subscriptions concurrently with the receive loop; RPC replies need it.
        let startup = Task {
            do { try await ready() }
            catch { self.interruption = error; socket.cancel(with: .goingAway, reason: nil) }
        }
        defer { startup.cancel(); close() }
        try await withTaskCancellationHandler {
            while !Task.isCancelled {
                let message: URLSessionWebSocketTask.Message
                do { message = try await socket.receive() }
                catch { throw interruption ?? error }
                lastFrameAt = Date()
                let data: Data
                switch message {
                case .data(let d): data = d
                case .string(let s): data = Data(s.utf8)
                @unknown default: continue
                }
                let decoded = try JSONValue.decode(data)
                for frame in Self.frames(decoded) { try await receive(frame) }
            }
        } onCancel: { socket.cancel(with: .goingAway, reason: nil) }
    }

    static func frames(_ value: JSONValue) -> [JSONValue] {
        if case .array(let frames) = value { frames } else { [value] }
    }

    func subscribe(_ method: String, payload: JSONValue = .object([:]), sink: @escaping Sink) async throws -> String {
        let id = nextID(); handlers[id] = sink
        do { try await request(id: id, method: method, payload: payload) }
        catch { handlers.removeValue(forKey: id); throw error }
        return id
    }

    func unsubscribe(_ id: String?) async {
        guard let id else { return }
        handlers.removeValue(forKey: id)
        try? await send(.object(["_tag": .string("Interrupt"), "requestId": .string(id)]))
    }

    func call(_ method: String, payload: JSONValue) async throws -> JSONValue {
        let id = nextID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                timeouts[id] = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(25)) } catch { return }
                    await self?.fail(id, error: ClientError("The server did not confirm the action. Check the conversation before retrying."))
                }
                Task {
                    do { try await self.request(id: id, method: method, payload: payload) }
                    catch { self.fail(id, error: error) }
                }
            }
        } onCancel: { Task { await self.fail(id, error: CancellationError()) } }
    }

    func close() {
        heartbeat?.cancel(); heartbeat = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        session?.invalidateAndCancel(); session = nil
        for task in timeouts.values { task.cancel() }; timeouts.removeAll()
        let continuations = pending.values; pending.removeAll(); handlers.removeAll()
        for c in continuations { c.resume(throwing: ClientError("Disconnected. Check whether your last action reached the server before retrying.")) }
    }

    private func nextID() -> String { sequence += 1; return String(sequence) }
    private func tick() async throws {
        guard Date().timeIntervalSince(lastFrameAt) < 20 else {
            interruption = TransportFailure(message: "The server stopped responding. Reconnecting…")
            socket?.cancel(with: .goingAway, reason: nil)
            return
        }
        try await send(.object(["_tag": .string("Ping")]))
    }
    private func request(id: String, method: String, payload: JSONValue) async throws {
        try await send(.object(["_tag": .string("Request"), "id": .string(id), "tag": .string(method), "payload": payload, "headers": .array([])]))
    }
    private func send(_ value: JSONValue) async throws {
        guard let socket else { throw ClientError("Connect to a server first.") }
        try await socket.send(.data(try value.data()))
    }
    private func fail(_ id: String, error: Error) {
        timeouts.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }
    private func receive(_ frame: JSONValue) async throws {
        let id = frame["requestId"].string.isEmpty ? String(frame["requestId"].int) : frame["requestId"].string
        switch frame["_tag"].string {
        case "Chunk":
            for item in frame["values"].array { await handlers[id]?(item) }
            try await send(.object(["_tag": .string("Ack"), "requestId": frame["requestId"]]))
        case "Exit":
            let exit = frame["exit"]
            if exit["_tag"].string == "Success" {
                timeouts.removeValue(forKey: id)?.cancel()
                pending.removeValue(forKey: id)?.resume(returning: exit["value"])
            } else {
                let error = ClientError(Self.failureMessage(exit))
                fail(id, error: error)
                if let handler = handlers[id] { await handler(.object(["kind": .string("client.error"), "message": .string(error.message)])) }
            }
            handlers.removeValue(forKey: id)
        case "Defect": throw ClientError("The T3 server reported a protocol failure. Check server and client versions.")
        default: break // Pong and future control frames do not affect application state.
        }
    }
    static func failureMessage(_ value: JSONValue) -> String {
        if !value["message"].string.isEmpty { return value["message"].string }
        if value["_tag"].string == "Die", !value["defect"].string.isEmpty {
            return "The server rejected an incompatible request. Update T3 Native and check the server version."
        }
        for child in value.object.values {
            let found = failureMessage(child)
            if found != "The server rejected this action." { return found }
        }
        for child in value.array {
            let found = failureMessage(child)
            if found != "The server rejected this action." { return found }
        }
        return "The server rejected this action."
    }
}
