import Foundation

enum EffectCanonicalJSON {
    static func encode(
        operations: [EffectOperation],
        functions: [String: EffectFunctionDefinition]
    ) -> String {
        object([
            ("operations", operationArray(operations)),
            (
                "functions",
                array(
                    functions.keys.sorted().compactMap { name in
                        functions[name].map(function)
                    })
            ),
        ])
    }

    private static func operationArray(_ operations: [EffectOperation]) -> String {
        array(operations.map(operation))
    }

    private static func operation(_ operation: EffectOperation) -> String {
        switch operation {
        case let .setHSV(target, h, s, v, blockID):
            object(
                base("set", blockID) + [
                    ("target", self.target(target)), ("h", expression(h)),
                    ("s", expression(s)), ("v", expression(v)),
                ])
        case let .setColour(target, colour, blockID):
            object(
                base("setColour", blockID) + [
                    ("target", self.target(target)), ("colour", expression(colour)),
                ])
        case let .fadeHSV(target, h, s, v, duration, blockID):
            object(
                base("fade", blockID) + [
                    ("target", self.target(target)), ("h", expression(h)),
                    ("s", expression(s)), ("v", expression(v)), ("ms", expression(duration)),
                ])
        case let .fadeColour(target, colour, duration, blockID):
            object(
                base("fadeColour", blockID) + [
                    ("target", self.target(target)), ("colour", expression(colour)),
                    ("ms", expression(duration)),
                ])
        case let .adjustHSV(target, h, s, v, blockID):
            object(
                base("adjust", blockID) + [
                    ("target", self.target(target)), ("dh", expression(h)),
                    ("ds", expression(s)), ("dv", expression(v)),
                ])
        case let .setMode(target, mode, parameter, blockID):
            object(
                base("mode", blockID) + [
                    ("target", self.target(target)), ("mode", expression(mode)),
                    ("param", expression(parameter)),
                ])
        case let .wait(duration, blockID):
            object(base("wait", blockID) + [("ms", expression(duration))])
        case let .setVariable(id, value, blockID):
            object(base("setVariable", blockID) + [("id", quote(id)), ("value", expression(value))])
        case let .changeVariable(id, delta, blockID):
            object(base("changeVariable", blockID) + [("id", quote(id)), ("delta", expression(delta))])
        case let .setListItem(id, index, value, blockID):
            object(
                base("setListItem", blockID) + [
                    ("id", quote(id)), ("index", expression(index)), ("value", expression(value)),
                ])
        case let .seedRandom(seed, blockID):
            object(base("seedRandom", blockID) + [("seed", expression(seed))])
        case let .callFunction(name, arguments, blockID):
            object(
                base("callFunction", blockID) + [
                    ("name", quote(name)), ("arguments", array(arguments.map(expression))),
                ])
        case let .ifElse(condition, thenBody, elseBody, blockID):
            object(
                base("if", blockID) + [
                    ("condition", expression(condition)), ("then", operationArray(thenBody)),
                    ("else", operationArray(elseBody)),
                ])
        case let .repeatLoop(count, body, blockID):
            object(
                base("repeat", blockID) + [
                    ("count", count.map(expression) ?? "null"), ("body", operationArray(body)),
                ])
        case let .forLoop(variableID, from, through, step, body, blockID):
            object(
                base("for", blockID) + [
                    ("id", quote(variableID)), ("from", expression(from)),
                    ("to", expression(through)), ("step", expression(step)),
                    ("body", operationArray(body)),
                ])
        case let .whileLoop(condition, body, blockID):
            object(
                base("while", blockID) + [
                    ("condition", expression(condition)), ("body", operationArray(body)),
                ])
        case let .breakLoop(blockID): object(base("break", blockID))
        case let .continueLoop(blockID): object(base("continue", blockID))
        case let .end(blockID): object(base("end", blockID))
        }
    }

    private static func base(_ name: String, _ blockID: String) -> [(String, String)] {
        [("op", quote(name)), ("blockId", quote(blockID))]
    }

    private static func target(_ target: EffectTargetReference) -> String {
        switch target {
        case .all: object([("kind", quote("all"))])
        case .allPixels: object([("kind", quote("allPixels"))])
        case let .group(index): object([("kind", quote("group")), ("index", expression(index))])
        case let .pixel(group, pixel):
            object([("kind", quote("pixel")), ("group", expression(group)), ("pixel", expression(pixel))])
        case let .pixelAt(index): object([("kind", quote("pixelAt")), ("index", expression(index))])
        case let .value(expression): object([("kind", quote("value")), ("expression", self.expression(expression))])
        }
    }

    private static func expression(_ expression: EffectExpression) -> String {
        switch expression {
        case let .number(value):
            object([("type", quote("number")), ("value", number(value))])
        case let .boolean(value):
            object([("type", quote("boolean")), ("value", value ? "true" : "false")])
        case let .colour(value):
            object([
                ("type", quote("colour")), ("h", String(value.hue)),
                ("s", String(value.saturation)), ("v", String(value.value)),
            ])
        case let .variable(id, type):
            object([("type", quote("variable")), ("id", quote(id)), ("valueType", quote(type.rawValue))])
        case .elapsedMilliseconds:
            object([("type", quote("elapsed"))])
        case let .groupValue(group, property):
            object([("type", quote("group")), ("group", String(group)), ("property", quote(property.rawValue))])
        case let .dynamicGroupValue(index, property):
            object([
                ("type", quote("dynamicGroup")), ("index", self.expression(index)),
                ("property", quote(property.rawValue)),
            ])
        case let .arithmetic(operation, left, right):
            binary("arithmetic", operation.rawValue, left, right)
        case let .clamp(value, low, high):
            object([
                ("type", quote("clamp")), ("value", self.expression(value)),
                ("low", self.expression(low)), ("high", self.expression(high)),
            ])
        case let .comparison(operation, left, right):
            binary("comparison", operation.rawValue, left, right)
        case let .logic(operation, left, right):
            binary("logic", operation.rawValue, left, right)
        case let .not(value):
            object([("type", quote("not")), ("value", self.expression(value))])
        case let .colourFromHSV(h, s, v):
            object([
                ("type", quote("hsv")), ("h", self.expression(h)),
                ("s", self.expression(s)), ("v", self.expression(v)),
            ])
        case let .target(value):
            object([("type", quote("target")), ("target", quote(value.rawValue))])
        case let .targetFromIndex(index):
            object([("type", quote("targetFromIndex")), ("index", self.expression(index))])
        case let .runtimeInput(key):
            object([("type", quote("runtimeInput")), ("key", quote(key.rawValue))])
        case let .builtin(function, arguments, type, nodeID):
            object([
                ("type", quote("builtin")), ("function", quote(function.rawValue)),
                ("valueType", quote(type.rawValue)), ("nodeId", quote(nodeID)),
                ("arguments", array(arguments.map(self.expression))),
            ])
        case let .list(elements, type):
            object([
                ("type", quote("list")), ("valueType", quote(type.rawValue)),
                ("elements", array(elements.map(self.expression))),
            ])
        case let .listGet(list, index, type):
            object([
                ("type", quote("listGet")), ("valueType", quote(type.rawValue)),
                ("list", self.expression(list)), ("index", self.expression(index)),
            ])
        case let .functionCall(name, arguments, type, nodeID):
            object([
                ("type", quote("functionCall")), ("name", quote(name)),
                ("valueType", quote(type.rawValue)), ("nodeId", quote(nodeID)),
                ("arguments", array(arguments.map(self.expression))),
            ])
        }
    }

    private static func binary(
        _ type: String,
        _ operation: String,
        _ left: EffectExpression,
        _ right: EffectExpression
    ) -> String {
        object([
            ("type", quote(type)), ("op", quote(operation)),
            ("left", expression(left)), ("right", expression(right)),
        ])
    }

    private static func function(_ function: EffectFunctionDefinition) -> String {
        object([
            ("name", quote(function.name)),
            (
                "parameters",
                array(
                    function.parameters.map { parameter in
                        object([
                            ("name", quote(parameter.name)), ("variableId", quote(parameter.variableID)),
                            ("type", quote(parameter.type.rawValue)),
                        ])
                    })
            ),
            ("returnType", function.returnType.map { quote($0.rawValue) } ?? "null"),
            ("operations", operationArray(function.operations)),
            ("return", function.returnExpression.map(expression) ?? "null"),
        ])
    }

    private static func object(_ fields: [(String, String)]) -> String {
        "{" + fields.map { quote($0.0) + ":" + $0.1 }.joined(separator: ",") + "}"
    }

    private static func array(_ values: [String]) -> String {
        "[" + values.joined(separator: ",") + "]"
    }

    private static func quote(_ value: String) -> String {
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: value,
                options: [.fragmentsAllowed, .withoutEscapingSlashes]
            ),
            let result = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        return result
    }

    private static func number(_ value: Double) -> String {
        guard value.isFinite else { return "null" }
        if value == 0, value.sign == .minus { return "-0" }
        let magnitude = abs(value)
        if magnitude >= 10_000_000 || (magnitude > 0 && magnitude < 0.001) {
            return javaScientificNumber(value)
        }
        if value == value.rounded(.towardZero), value >= Double(Int64.min), value <= Double(Int64.max) {
            return String(Int64(value))
        }
        var result = String(value)
        while result.last == "0", result.contains(".") { result.removeLast() }
        if result.last == "." { result.removeLast() }
        return result
    }

    /// Matches the finite scientific forms emitted by Java 17
    /// `Double.toString`, which backs Android `JSONObject.numberToString`.
    private static func javaScientificNumber(_ value: Double) -> String {
        if value == Double.leastNonzeroMagnitude { return "4.9E-324" }
        if value == -Double.leastNonzeroMagnitude { return "-4.9E-324" }
        let raw = String(value)
        if let marker = raw.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            var mantissa = String(raw[..<marker])
            let exponent = Int(raw[raw.index(after: marker)...]) ?? 0
            if mantissa.contains(".") == false { mantissa += ".0" }
            return "\(mantissa)E\(exponent)"
        }

        let negative = raw.hasPrefix("-")
        let unsigned = negative ? String(raw.dropFirst()) : raw
        let components = unsigned.split(separator: ".", omittingEmptySubsequences: false)
        let whole = String(components[0])
        let fraction = components.count > 1 ? String(components[1]) : ""
        let digits = whole + fraction
        guard let first = digits.firstIndex(where: { $0 != "0" }) else { return negative ? "-0" : "0" }
        let firstOffset = digits.distance(from: digits.startIndex, to: first)
        let exponent = whole.count - firstOffset - 1
        var significant = String(digits[first...])
        while significant.last == "0" { significant.removeLast() }
        let leading = significant.removeFirst()
        let mantissa = significant.isEmpty ? "\(leading).0" : "\(leading).\(significant)"
        return "\(negative ? "-" : "")\(mantissa)E\(exponent)"
    }
}
