import Foundation

struct PairingTarget: Equatable, Sendable {
    let origin: URL
    let credential: String

    init(_ input: String, code: String = "") throws {
        var input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { throw ClientError("Enter your server's pairing link.") }
        if let wrapper = URLComponents(string: input), ["t3code", "t3native"].contains(wrapper.scheme),
           let inner = wrapper.queryItems?.first(where: { $0.name == "pairingUrl" })?.value {
            input = inner
        }
        if !input.contains("://") { input = "https://" + input }
        guard var parts = URLComponents(string: input), let host = parts.host, !host.isEmpty,
              ["https", "http", "wss", "ws"].contains(parts.scheme),
              parts.user == nil, parts.password == nil else { throw ClientError("Use an HTTP or HTTPS T3 Code server address.") }
        let fragment = URLComponents(string: "https://pair.invalid/?" + (parts.fragment ?? ""))?.queryItems ?? []
        let query = parts.queryItems ?? []
        let token = (fragment + query).first(where: { $0.name == "token" })?.value ?? code
        if let hosted = query.first(where: { $0.name == "host" })?.value, !hosted.isEmpty {
            self = try PairingTarget(hosted, code: token)
            return
        }
        if parts.scheme == "ws" { parts.scheme = "http" }
        if parts.scheme == "wss" { parts.scheme = "https" }
        parts.path = ""; parts.query = nil; parts.fragment = nil
        guard let url = parts.url else { throw ClientError("This server address is invalid.") }
        self.origin = url
        self.credential = token.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct SavedHost: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    let origin: URL
    var expiresAt: Date?
    var scopes: [String]
    init(id: UUID = UUID(), name: String, origin: URL, expiresAt: Date? = nil, scopes: [String] = []) {
        self.id = id; self.name = name; self.origin = origin; self.expiresAt = expiresAt; self.scopes = scopes
    }
    var canOperate: Bool { scopes.contains("orchestration:operate") }
}

actor HostAuthenticator {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func pair(target: PairingTarget, name: String) async throws -> (SavedHost, String) {
        guard !target.credential.isEmpty else { throw ClientError("Paste a pairing link with a token, or enter a pairing code.") }
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:token-exchange"),
            URLQueryItem(name: "subject_token", value: target.credential),
            URLQueryItem(name: "subject_token_type", value: "urn:t3:params:oauth:token-type:environment-bootstrap"),
            URLQueryItem(name: "requested_token_type", value: "urn:ietf:params:oauth:token-type:access_token"),
            URLQueryItem(name: "client_label", value: "T3 Native"),
            URLQueryItem(name: "client_device_type", value: "mobile"),
            URLQueryItem(name: "client_os", value: "iOS")
        ]
        var request = URLRequest(url: target.origin.appendingPathComponent("oauth/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // '+' is a form separator, so credentials must encode it explicitly.
        request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let result = try await json(request)
        guard result["token_type"].string.lowercased() == "bearer", !result["access_token"].string.isEmpty else {
            throw ClientError("This connection requires T3 Connect account authentication. Use a direct server pairing link for this build.")
        }
        let expires = result["expires_in"].int
        return (SavedHost(name: name.isEmpty ? (target.origin.host ?? "Server") : name, origin: target.origin,
                          expiresAt: expires > 0 ? Date().addingTimeInterval(Double(expires)) : nil,
                          scopes: result["scope"].string.split(separator: " ").map(String.init)), result["access_token"].string)
    }

    func socketURL(host: SavedHost, token: String) async throws -> URL {
        if let expiry = host.expiresAt, expiry <= Date() { throw ClientError("Your connection expired. Pair this server again.") }
        var request = URLRequest(url: host.origin.appendingPathComponent("api/auth/websocket-ticket"))
        request.httpMethod = "POST"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let result = try await json(request)
        guard !result["ticket"].string.isEmpty else { throw ClientError("The server did not return a WebSocket ticket.") }
        var parts = URLComponents(url: host.origin, resolvingAgainstBaseURL: false)!
        parts.scheme = host.origin.scheme == "https" ? "wss" : "ws"
        parts.path = "/ws"
        parts.queryItems = [URLQueryItem(name: "wsTicket", value: result["ticket"].string),
                            URLQueryItem(name: "orchestrationProtocol", value: "2"),
                            URLQueryItem(name: "clientSurface", value: "mobile"),
                            URLQueryItem(name: "clientDeviceType", value: "phone"),
                            URLQueryItem(name: "clientOs", value: "iOS"),
                            URLQueryItem(name: "clientAppVersion", value: "0.1.0-native")]
        return parts.url!
    }

    func history(host: SavedHost, token: String, threadID: String, cursor: String) async throws -> JSONValue {
        var parts = URLComponents(url: host.origin.appendingPathComponent("api/orchestration/threads").appendingPathComponent(threadID).appendingPathComponent("history"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "cursor", value: cursor)]
        var request = URLRequest(url: parts.url!)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("2", forHTTPHeaderField: "x-t3-orchestration-protocol")
        return try await json(request)
    }

    private func json(_ input: URLRequest) async throws -> JSONValue {
        var request = input; request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError("The server returned no HTTP response.") }
        guard (200..<300).contains(http.statusCode) else {
            if [401, 403].contains(http.statusCode) { throw ClientError("The server rejected this credential. Create a new pairing link.") }
            if http.statusCode >= 500 || [408, 429].contains(http.statusCode) { throw TransportFailure(message: "The server returned HTTP \(http.statusCode). Reconnecting…") }
            throw ClientError("The server returned HTTP \(http.statusCode).")
        }
        return try JSONValue.decode(data)
    }
}
