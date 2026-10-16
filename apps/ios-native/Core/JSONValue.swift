import Foundation

/// Keep unknown upstream fields intact so additive contract changes are harmless.
enum JSONValue: Codable, Sendable, Equatable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    subscript(_ key: String) -> JSONValue {
        get { if case .object(let v) = self { return v[key] ?? .null }; return .null }
        set { var v = object; v[key] = newValue; self = .object(v) }
    }
    var object: [String: JSONValue] { if case .object(let v) = self { v } else { [:] } }
    var array: [JSONValue] { if case .array(let v) = self { v } else { [] } }
    var string: String { if case .string(let v) = self { v } else { "" } }
    var int: Int { if case .number(let v) = self { Int(v) } else { 0 } }
    var bool: Bool { if case .bool(let v) = self { v } else { false } }
    var id: String { self["id"].string }
    var providerID: String { self["instanceId"].string }
    var modelID: String { self["slug"].string }
    var isNull: Bool { self == .null }

    static func decode(_ data: Data) throws -> JSONValue { try JSONDecoder().decode(Self.self, from: data) }
    func data() throws -> Data { try JSONEncoder().encode(self) }
    static func text(_ value: String) -> JSONValue { .string(value) }
}

struct ClientError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

struct TransportFailure: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}
