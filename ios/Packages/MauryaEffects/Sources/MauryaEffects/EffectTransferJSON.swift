import Foundation

enum EffectJSONValue: Sendable, Equatable {
    case object([String: EffectJSONValue])
    case array([EffectJSONValue])
    case string(String)
    case integer(Int64)
    case number(String)
    case boolean(Bool)
    case null
}

enum EffectStrictJSON {
    static func parse(_ data: Data, maxDepth: Int = 32, maxEntries: Int = 20_000, maxStringBytes: Int = 512 * 1024) throws
        -> EffectJSONValue
    {
        guard let text = String(data: data, encoding: .utf8) else { throw EffectProgramError.invalidUTF8 }
        var parser = Parser(scalars: Array(text.unicodeScalars), maxDepth: maxDepth, maxEntries: maxEntries, maxStringBytes: maxStringBytes)
        let value = try parser.value(depth: 0)
        parser.skipWhitespace()
        guard parser.isAtEnd else { throw EffectProgramError.invalidJSON }
        return value
    }

    private struct Parser {
        let scalars: [Unicode.Scalar]
        let maxDepth: Int
        let maxEntries: Int
        let maxStringBytes: Int
        var index = 0
        var entries = 0
        var isAtEnd: Bool { index == scalars.count }

        mutating func skipWhitespace() {
            while let scalar = peek(), scalar == " " || scalar == "\n" || scalar == "\r" || scalar == "\t" { index += 1 }
        }

        mutating func value(depth: Int) throws -> EffectJSONValue {
            guard depth <= maxDepth else { throw EffectProgramError.JSONLimitExceeded }
            skipWhitespace()
            guard let scalar = peek() else { throw EffectProgramError.invalidJSON }
            switch scalar {
            case "{": return try object(depth: depth + 1)
            case "[": return try array(depth: depth + 1)
            case "\"": return .string(try string())
            case "t": try literal("true"); return .boolean(true)
            case "f": try literal("false"); return .boolean(false)
            case "n": try literal("null"); return .null
            default: return try number()
            }
        }

        mutating func object(depth: Int) throws -> EffectJSONValue {
            try consume("{"); skipWhitespace()
            var result: [String: EffectJSONValue] = [:]
            if take("}") { return .object(result) }
            while true {
                skipWhitespace()
                guard peek() == "\"" else { throw EffectProgramError.invalidJSON }
                let key = try string()
                guard result[key] == nil else { throw EffectProgramError.duplicateJSONKey(key) }
                try countEntry(); skipWhitespace(); try consume(":")
                result[key] = try value(depth: depth); skipWhitespace()
                if take("}") { return .object(result) }
                try consume(",")
            }
        }

        mutating func array(depth: Int) throws -> EffectJSONValue {
            try consume("["); skipWhitespace()
            var result: [EffectJSONValue] = []
            if take("]") { return .array(result) }
            while true {
                try countEntry(); result.append(try value(depth: depth)); skipWhitespace()
                if take("]") { return .array(result) }
                try consume(",")
            }
        }

        mutating func string() throws -> String {
            try consume("\"")
            var output = String.UnicodeScalarView()
            while let scalar = peek() {
                index += 1
                if scalar == "\"" {
                    let result = String(output)
                    guard result.utf8.count <= maxStringBytes else { throw EffectProgramError.JSONLimitExceeded }
                    return result
                }
                if scalar == "\\" {
                    guard let escaped = peek() else { throw EffectProgramError.invalidJSON }
                    index += 1
                    switch escaped {
                    case "\"", "\\", "/": output.append(escaped)
                    case "b": output.append("\u{8}")
                    case "f": output.append("\u{c}")
                    case "n": output.append("\n")
                    case "r": output.append("\r")
                    case "t": output.append("\t")
                    case "u": try appendUnicodeEscape(to: &output)
                    default: throw EffectProgramError.invalidJSON
                    }
                } else {
                    guard scalar.value >= 0x20 else { throw EffectProgramError.invalidJSON }
                    output.append(scalar)
                }
            }
            throw EffectProgramError.invalidJSON
        }

        mutating func appendUnicodeEscape(to output: inout String.UnicodeScalarView) throws {
            let first = try hexQuad()
            if (0xD800...0xDBFF).contains(first) {
                try consume("\\"); try consume("u")
                let second = try hexQuad()
                guard (0xDC00...0xDFFF).contains(second), let scalar = Unicode.Scalar(0x10000 + ((first - 0xD800) << 10) + second - 0xDC00)
                else { throw EffectProgramError.invalidJSON }
                output.append(scalar)
            } else {
                guard !(0xDC00...0xDFFF).contains(first), let scalar = Unicode.Scalar(first) else { throw EffectProgramError.invalidJSON }
                output.append(scalar)
            }
        }

        mutating func hexQuad() throws -> UInt32 {
            var value: UInt32 = 0
            for _ in 0..<4 {
                guard let scalar = peek(), let digit = scalar.effectHexDigit else { throw EffectProgramError.invalidJSON }
                index += 1; value = value * 16 + UInt32(digit)
            }
            return value
        }

        mutating func number() throws -> EffectJSONValue {
            let start = index; _ = take("-")
            guard let first = peek() else { throw EffectProgramError.invalidJSON }
            if first == "0" {
                index += 1
                if let next = peek(), (48...57).contains(next.value) { throw EffectProgramError.invalidJSON }
            } else {
                guard (49...57).contains(first.value) else { throw EffectProgramError.invalidJSON }
                while let scalar = peek(), (48...57).contains(scalar.value) { index += 1 }
            }
            var integral = true
            if take(".") { integral = false; try consumeDigits() }
            if take("e") || take("E") { integral = false; _ = take("+") || take("-"); try consumeDigits() }
            let raw = String(String.UnicodeScalarView(scalars[start..<index]))
            if integral, let integer = Int64(raw) { return .integer(integer) }
            return .number(raw)
        }

        mutating func consumeDigits() throws {
            guard let scalar = peek(), (48...57).contains(scalar.value) else { throw EffectProgramError.invalidJSON }
            while let scalar = peek(), (48...57).contains(scalar.value) { index += 1 }
        }

        mutating func literal(_ text: String) throws { for scalar in text.unicodeScalars { try consume(scalar) } }
        mutating func countEntry() throws { entries += 1; guard entries <= maxEntries else { throw EffectProgramError.JSONLimitExceeded } }
        mutating func consume(_ scalar: Unicode.Scalar) throws { guard take(scalar) else { throw EffectProgramError.invalidJSON } }
        mutating func take(_ scalar: Unicode.Scalar) -> Bool { guard peek() == scalar else { return false }; index += 1; return true }
        func peek() -> Unicode.Scalar? { index < scalars.count ? scalars[index] : nil }
    }
}

private extension Unicode.Scalar {
    var effectHexDigit: Int? {
        switch value {
        case 48...57: Int(value - 48)
        case 65...70: Int(value - 55)
        case 97...102: Int(value - 87)
        default: nil
        }
    }
}
