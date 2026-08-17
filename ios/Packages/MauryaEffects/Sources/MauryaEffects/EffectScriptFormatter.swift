import Foundation

public enum EffectScriptFormatter: Sendable {
    public static func fromCompiled(_ name: String, _ compiled: CompiledEffect) -> String {
        let names = variableNames(compiled)
        var output = ""
        for key in compiled.functions.keys.sorted() {
            guard let function = compiled.functions[key] else { continue }
            let parameters = function.parameters.map { "\(typeName($0.type)) \($0.name)" }.joined(separator: ", ")
            output += "fn \(function.name)(\(parameters))"
            if let returnType = function.returnType { output += ": \(typeName(returnType))" }
            output += " {\n"
            var declared = Set(function.parameters.map(\.variableID))
            append(function.operations, to: &output, depth: 1, names: names, types: compiled.variables, declared: &declared)
            if let value = function.returnExpression { output += "    return \(expression(value, names));\n" }
            output += "}\n\n"
        }
        output += "effect \"\(escape(name))\" {\n"
        var declared = Set<String>()
        append(compiled.operations, to: &output, depth: 1, names: names, types: compiled.variables, declared: &declared)
        output += "}\n"
        return output
    }

    public static func format(name: String, compiled: CompiledEffect) -> String { fromCompiled(name, compiled) }

    private static func append(
        _ operations: [EffectOperation], to output: inout String, depth: Int, names: [String: String], types: [String: EffectValueType],
        declared: inout Set<String>
    ) {
        for operation in operations { append(operation, to: &output, depth: depth, names: names, types: types, declared: &declared) }
    }

    private static func append(
        _ operation: EffectOperation, to output: inout String, depth: Int, names: [String: String], types: [String: EffectValueType],
        declared: inout Set<String>
    ) {
        let indent = String(repeating: "    ", count: depth)
        switch operation {
        case let .setHSV(target, h, s, v, _):
            output += "\(indent)\(targetText(target, names)).hsv(\(expression(h,names)), \(expression(s,names)), \(expression(v,names)));\n"
        case let .setColour(target, colour, _): output += "\(indent)\(targetText(target,names)).color(\(expression(colour,names)));\n"
        case let .fadeHSV(target, h, s, v, duration, _):
            output +=
                "\(indent)\(targetText(target,names)).fade(hsv(\(expression(h,names)), \(expression(s,names)), \(expression(v,names))), \(durationText(duration,names)));\n"
        case let .fadeColour(target, colour, duration, _):
            output += "\(indent)\(targetText(target,names)).fade(\(expression(colour,names)), \(durationText(duration,names)));\n"
        case let .adjustHSV(target, h, s, v, _):
            output +=
                "\(indent)\(targetText(target,names)).adjustHsv(\(expression(h,names)), \(expression(s,names)), \(expression(v,names)));\n"
        case let .setMode(target, mode, parameter, _):
            output += "\(indent)\(targetText(target,names)).mode(\(modeText(mode,names)), \(expression(parameter,names)));\n"
        case let .wait(value, _): output += "\(indent)wait(\(durationText(value,names)));\n"
        case let .setVariable(id, value, _):
            if declared.insert(id).inserted {
                output += "\(indent)let \(names[id] ?? safeName(id)): \(typeName(types[id] ?? value.type)) = \(expression(value,names));\n"
            } else {
                output += "\(indent)\(names[id] ?? safeName(id)) = \(expression(value,names));\n"
            }
        case let .changeVariable(id, delta, _): output += "\(indent)\(names[id] ?? safeName(id)) += \(expression(delta,names));\n"
        case let .setListItem(id, index, value, _):
            output += "\(indent)\(names[id] ?? safeName(id))[\(expression(index,names))] = \(expression(value,names));\n"
        case let .seedRandom(seed, _): output += "\(indent)seedRandom(\(expression(seed,names)));\n"
        case let .callFunction(name, arguments, _):
            output += "\(indent)\(name)(\(arguments.map { expression($0,names) }.joined(separator: ", ")));\n"
        case let .ifElse(condition, thenBody, elseBody, _):
            output += "\(indent)if (\(expression(condition,names))) {\n";
            append(thenBody, to: &output, depth: depth + 1, names: names, types: types, declared: &declared); output += "\(indent)}"
            if !elseBody.isEmpty {
                output += " else {\n"; append(elseBody, to: &output, depth: depth + 1, names: names, types: types, declared: &declared);
                output += "\(indent)}"
            }; output += "\n"
        case let .repeatLoop(count, body, _):
            output += count.map { "\(indent)repeat(\(expression($0,names))) {\n" } ?? "\(indent)forever {\n";
            append(body, to: &output, depth: depth + 1, names: names, types: types, declared: &declared); output += "\(indent)}\n"
        case let .forLoop(id, from, through, step, body, _):
            declared.insert(id);
            output +=
                "\(indent)for (\(names[id] ?? safeName(id)) from \(expression(from,names)) to \(expression(through,names)) step \(expression(step,names))) {\n";
            append(body, to: &output, depth: depth + 1, names: names, types: types, declared: &declared); output += "\(indent)}\n"
        case let .whileLoop(condition, body, _):
            output += "\(indent)while (\(expression(condition,names))) {\n";
            append(body, to: &output, depth: depth + 1, names: names, types: types, declared: &declared); output += "\(indent)}\n"
        case .breakLoop: output += "\(indent)break;\n"
        case .continueLoop: output += "\(indent)continue;\n"
        case .end: output += "\(indent)end;\n"
        }
    }

    private static func expression(_ value: EffectExpression, _ names: [String: String]) -> String {
        switch value {
        case let .number(number): return number.rounded() == number ? String(Int64(number)) : String(number)
        case let .boolean(flag): return String(flag)
        case let .colour(colour): return "hsv(\(colour.hue), \(colour.saturation), \(colour.value))"
        case let .variable(id, _): return names[id] ?? safeName(id)
        case .elapsedMilliseconds: return "time.elapsedMs"
        case let .groupValue(group, property): return "group(\(group + 1)).\(property.rawValue.lowercased())"
        case let .dynamicGroupValue(index, property): return "group(\(expression(index,names))).\(property.rawValue.lowercased())"
        case let .arithmetic(op, left, right):
            if op == .minimum || op == .maximum || op == .power {
                return "\(op == .minimum ? "min" : op == .maximum ? "max" : "pow")(\(expression(left,names)), \(expression(right,names)))"
            }
            return "(\(expression(left,names)) \(arithmetic(op)) \(expression(right,names)))"
        case let .clamp(value, low, high): return "clamp(\(expression(value,names)), \(expression(low,names)), \(expression(high,names)))"
        case let .comparison(op, left, right): return "(\(expression(left,names)) \(comparison(op)) \(expression(right,names)))"
        case let .logic(op, left, right): return "(\(expression(left,names)) \(op == .and ? "&&" : "||") \(expression(right,names)))"
        case let .not(value): return "!\(expression(value,names))"
        case let .colourFromHSV(h, s, v): return "hsv(\(expression(h,names)), \(expression(s,names)), \(expression(v,names)))"
        case let .target(target): return target == .all ? "all" : "group(\(target.groupNumber))"
        case let .targetFromIndex(index): return "group(\(expression(index,names)))"
        case let .runtimeInput(key): return runtimeInput(key)
        case let .builtin(.listLength, arguments, _, _): return "\(arguments.first.map { expression($0,names) } ?? "[]").length"
        case let .builtin(function, arguments, _, _):
            return "\(builtin(function))(\(arguments.map { expression($0,names) }.joined(separator: ", ")))"
        case let .list(elements, _): return "[\(elements.map { expression($0,names) }.joined(separator: ", "))]"
        case let .listGet(list, index, _): return "\(expression(list,names))[\(expression(index,names))]"
        case let .functionCall(name, arguments, _, _): return "\(name)(\(arguments.map { expression($0,names) }.joined(separator: ", ")))"
        }
    }

    private static func variableNames(_ compiled: CompiledEffect) -> [String: String] {
        var result: [String: String] = [:], used = Set<String>()
        for function in compiled.functions.values {
            for parameter in function.parameters { result[parameter.variableID] = parameter.name; used.insert(parameter.name) }
        }
        for id in compiled.variables.keys.sorted() where result[id] == nil {
            var candidate = safeName(id), suffix = 2;
            while used.contains(candidate) { candidate = "\(safeName(id))\(suffix)"; suffix += 1 }; result[id] = candidate;
            used.insert(candidate)
        }
        return result
    }

    private static func safeName(_ id: String) -> String {
        let mapped = id.map { $0.isLetter || $0.isNumber || $0 == "_" ? $0 : "_" };
        var value = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "_"));
        if value.isEmpty || value.first?.isNumber == true { value = "value_\(value)" }; return value
    }
    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
    private static func typeName(_ type: EffectValueType) -> String {
        switch type {
        case .number: "number";
        case .boolean: "bool";
        case .colour: "color";
        case .target: "target";
        case .numberList: "number[]";
        case .booleanList: "bool[]";
        case .colourList: "color[]";
        case .targetList: "target[]"
        }
    }
    private static func durationText(_ value: EffectExpression, _ names: [String: String]) -> String {
        if case let .number(number) = value, number.truncatingRemainder(dividingBy: 1_000) == 0 { return "\(Int64(number / 1_000))s" };
        return "\(expression(value,names))ms"
    }
    private static func modeText(_ value: EffectExpression, _ names: [String: String]) -> String {
        if case .number(1) = value { return "STEADY" }; if case .number(3) = value { return "STROBE" }; return expression(value, names)
    }
    private static func targetText(_ value: EffectTargetReference, _ names: [String: String]) -> String {
        switch value {
        case .all: "all";
        case .allPixels: "allPixels";
        case let .group(i): "group(\(expression(i,names)))";
        case let .pixel(g, p): "pixel(\(expression(g,names)), \(expression(p,names)))";
        case let .pixelAt(i): "pixelAt(\(expression(i,names)))";
        case let .value(v): expression(v, names)
        }
    }
    private static func arithmetic(_ op: ArithmeticOperator) -> String {
        switch op {
        case .add: "+";
        case .subtract: "-";
        case .multiply: "*";
        case .divide: "/";
        case .modulo: "%";
        case .power: "*";
        case .minimum: "min";
        case .maximum: "max"
        }
    }
    private static func comparison(_ op: ComparisonOperator) -> String {
        switch op {
        case .equal: "==";
        case .notEqual: "!=";
        case .lessThan: "<";
        case .lessThanOrEqual: "<=";
        case .greaterThan: ">";
        case .greaterThanOrEqual: ">="
        }
    }
    private static func builtin(_ function: BuiltinFunction) -> String { builtinNames[function] ?? function.rawValue.lowercased() }
    private static func runtimeInput(_ key: RuntimeInputKey) -> String { runtimeNames[key] ?? key.rawValue.lowercased() }
}

private let builtinNames: [BuiltinFunction: String] = [
    .absolute: "abs", .minimum: "min", .maximum: "max", .clamp: "clamp", .power: "pow", .round: "round", .floor: "floor", .ceil: "ceil",
    .squareRoot: "sqrt", .logarithm: "log", .sine: "sin", .cosine: "cos", .radians: "radians", .degrees: "degrees", .map: "map",
    .lerp: "lerp", .smoothstep: "smoothstep", .smootherstep: "smootherstep", .easeIn: "easeIn", .easeOut: "easeOut",
    .easeInOut: "easeInOut", .sineWave: "sineWave", .triangleWave: "triangleWave", .sawWave: "sawWave", .squareWave: "squareWave",
    .random: "random", .randomColour: "randomColor", .noise1D: "noise1D", .fbmNoise: "fbmNoise", .smooth: "smooth", .deadzone: "deadzone",
    .hysteresis: "hysteresis", .peakHold: "peakHold", .debounce: "debounce", .risingEdge: "risingEdge", .fallingEdge: "fallingEdge",
    .rgb: "rgb", .red: "red", .green: "green", .blue: "blue", .hue: "hue", .saturation: "saturation", .value: "value", .mixRGB: "mixRgb",
    .mixHSV: "mixHsv", .complement: "complement", .rotateHue: "rotateHue", .adjustSaturation: "adjustSaturation",
    .adjustValue: "adjustValue", .paletteColour: "paletteColor", .cycle: "cycle", .beatPhase: "beatPhase", .barPhase: "barPhase",
    .listLength: "length", .mirror: "mirror", .rotatePattern: "rotatePattern", .centerSpread: "centerSpread",
    .centerContract: "centerContract", .chase: "chase", .wavePattern: "wavePattern",
]
private let runtimeNames: [RuntimeInputKey: String] = [
    .sensorAccelX: "sensor.accelX", .sensorAccelY: "sensor.accelY", .sensorAccelZ: "sensor.accelZ", .sensorMotion: "sensor.motion",
    .sensorShake: "sensor.shake", .sensorGyroX: "sensor.gyroX", .sensorGyroY: "sensor.gyroY", .sensorGyroZ: "sensor.gyroZ",
    .sensorPitch: "sensor.pitch", .sensorRoll: "sensor.roll", .sensorYaw: "sensor.yaw", .sensorLight: "sensor.light",
    .sensorNear: "sensor.near", .sensorHeading: "sensor.heading", .sensorPressure: "sensor.pressure", .audioLevel: "audio.level",
    .audioPeak: "audio.peak", .audioBass: "audio.bass", .audioMid: "audio.mid", .audioTreble: "audio.treble", .audioBeat: "audio.beat",
    .audioBPM: "audio.bpm",
]
private extension EffectTarget {
    var groupNumber: Int {
        switch self {
        case .all: 0;
        case .group1: 1;
        case .group2: 2;
        case .group3: 3;
        case .group4: 4;
        case .group5: 5;
        case .group6: 6;
        case .group7: 7
        }
    }
}
