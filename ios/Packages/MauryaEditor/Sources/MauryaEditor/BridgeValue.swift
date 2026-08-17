import Foundation

public enum BridgeValue: Sendable, Equatable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([BridgeValue])
    case object([String: BridgeValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([BridgeValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: BridgeValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    public var string: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    public var integer: Int? {
        guard case let .number(value) = self, value.isFinite,
            value.rounded(.towardZero) == value,
            value >= Double(Int.min), value <= Double(Int.max)
        else { return nil }
        return Int(value)
    }
}
