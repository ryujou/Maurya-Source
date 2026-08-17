import CryptoKit
import Foundation

public enum EffectCompiler: Sendable {
    private static let maximumBlocks = 300
    private static let maximumControlDepth = 6
    private static let maximumVariables = 16

    static let supportedStatementTypes: Set<String> = [
        "maurya_start", "maurya_function_def", "maurya_set_all_pixels_color_value",
        "maurya_set_all_pixels_hsv_value", "maurya_set_pixel_color_value",
        "maurya_set_pixel_hsv_value", "maurya_set_pixel_at_color_value",
        "maurya_set_pixel_at_hsv_value", "maurya_apply_pixel_colour_list",
        "maurya_set_color", "maurya_set_color_value", "maurya_fade", "maurya_fade_value",
        "maurya_set_hsv", "maurya_set_hsv_value", "maurya_adjust_hsv",
        "maurya_adjust_hsv_value", "maurya_mode", "maurya_wait", "maurya_wait_value",
        "maurya_seed_random", "maurya_function_call", "maurya_apply_colour_list",
        "maurya_var_set_number", "maurya_var_set_boolean", "maurya_var_set_colour",
        "maurya_var_change_number", "maurya_if", "maurya_if_else", "maurya_repeat",
        "maurya_forever", "maurya_for", "maurya_while", "maurya_break",
        "maurya_continue", "maurya_end",
    ]

    static let supportedExpressionTypes: Set<String> = [
        "math_number", "logic_boolean", "maurya_colour_literal", "maurya_var_get_number",
        "maurya_var_get_boolean", "maurya_var_get_colour", "maurya_elapsed",
        "maurya_group_value", "maurya_algorithm_unary", "maurya_algorithm_binary",
        "maurya_algorithm_ternary", "maurya_wave", "maurya_square_wave", "maurya_noise",
        "maurya_random_number", "maurya_random_colour", "maurya_colour_unary",
        "maurya_colour_adjust", "maurya_colour_mix", "maurya_runtime_number",
        "maurya_audio_number", "maurya_audio_beat", "maurya_time_phase",
        "maurya_colour_list7", "maurya_number_list7", "maurya_colour_list_get",
        "maurya_number_list_get", "maurya_list_length", "maurya_pattern",
        "maurya_pattern_list", "math_arithmetic", "math_modulo", "maurya_minmax",
        "maurya_clamp", "logic_compare", "logic_operation", "logic_negate",
        "maurya_hsv_colour",
    ]

    public static func compile(blocklyJSON: String) throws -> CompiledEffect {
        try compile(blocklyJSON: blocklyJSON, checkpoint: {})
    }

    static func compile(blocklyJSON: String, checkpoint: @escaping EffectExecutionCheckpoint) throws -> CompiledEffect {
        try checkpoint()
        let data = Data(blocklyJSON.utf8)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw compileError(code: "INVALID_JSON", zh: "效果JSON无效", ja: "エフェクトJSONが無効です")
        }
        let top = ((root["blocks"] as? [String: Any])?["blocks"] as? [[String: Any]]) ?? []
        let count = top.reduce(0) { $0 + countBlocks($1) }
        guard count <= maximumBlocks else {
            throw compileError(code: "TOO_MANY_BLOCKS", zh: "积木数量不能超过300", ja: "ブロックは最大300個です")
        }
        let variables = try readVariables(root)
        let starts = top.filter { string($0, "type") == "maurya_start" }
        let functionBlocks = top.filter { string($0, "type") == "maurya_function_def" }
        guard starts.count == 1, top.count == 1 + functionBlocks.count else {
            throw compileError(code: "ORPHAN_BLOCK", zh: "必须有一个开始积木且不能有孤立积木", ja: "再生開始は1個で、未接続ブロックは使用できません")
        }
        try checkpoint()
        let parser = Parser(variables: variables, checkpoint: checkpoint)
        var functions: [String: EffectFunctionDefinition] = [:]
        for block in functionBlocks {
            try checkpoint()
            let fields = block["fields"] as? [String: Any] ?? [:]
            let name = string(fields, "NAME").trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.isEmpty == false, functions[name] == nil else {
                throw compileError(code: "INVALID_FUNCTION", zh: "函数名为空或重复", ja: "関数名が空か重複しています", sourceID: string(block, "id"))
            }
            functions[name] = EffectFunctionDefinition(
                name: name,
                operations: try parser.parseChain(inputBlock(block, "BODY"), depth: 1, loopDepth: 0)
            )
        }
        let operations = try parser.parseChain(next(starts[0]), depth: 0, loopDepth: 0)
        guard operations.isEmpty == false else {
            throw compileError(code: "EMPTY_PROGRAM", zh: "开始积木后没有可执行内容", ja: "実行するブロックがありません")
        }
        try validateBlocklyFunctions(operations: operations, functions: functions)
        return try compile(
            operations: operations,
            nodeCount: count,
            variables: variables,
            functions: functions,
            checkpoint: checkpoint
        )
    }

    public static func compile(
        operations: [EffectOperation],
        nodeCount: Int,
        variables: [String: EffectValueType] = [:],
        functions: [String: EffectFunctionDefinition] = [:]
    ) throws -> CompiledEffect {
        try compile(operations: operations, nodeCount: nodeCount, variables: variables, functions: functions, checkpoint: {})
    }

    static func compile(
        operations: [EffectOperation],
        nodeCount: Int,
        variables: [String: EffectValueType] = [:],
        functions: [String: EffectFunctionDefinition] = [:],
        checkpoint: @escaping EffectExecutionCheckpoint
    ) throws -> CompiledEffect {
        try checkpoint()
        guard nodeCount <= maximumBlocks, variables.count <= maximumVariables else {
            throw compileError(code: "PROGRAM_LIMIT", zh: "程序超过大小限制", ja: "プログラムがサイズ制限を超えています")
        }
        let allOperations = operations + functions.values.flatMap(\.operations)
        for _ in allOperations { try checkpoint() }
        let pixelMode = allOperations.contains(where: containsPixelTarget)
        if pixelMode, allOperations.contains(where: containsModeOperation) {
            throw compileError(code: "PIXEL_MODE_CONFLICT", zh: "逐灯程序不能使用硬件组内模式", ja: "ピクセルプログラムではハードウェアモードを使用できません")
        }
        try validateConstantTargets(allOperations)
        try checkpoint()
        try validateReachability(operations)
        try checkpoint()
        try validateObservableStates(operations)
        try checkpoint()
        let canonical = canonicalJSON(operations: operations, functions: functions)
        let digest = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
        let seed = Int64(bitPattern: UInt64(digest.prefix(16), radix: 16) ?? 0)
        return CompiledEffect(
            operations: operations,
            blockCount: nodeCount,
            estimatedDurationMilliseconds: duration(of: operations),
            astSHA256: digest,
            variables: variables,
            requiredInputs: collectInputs(
                allOperations,
                additionalExpressions: functions.values.compactMap(\.returnExpression)
            ),
            randomSeed: seed,
            functions: functions,
            requiresPixelEffect: pixelMode
        )
    }

    public static func canonicalJSON(_ compiled: CompiledEffect) -> String {
        canonicalJSON(operations: compiled.operations, functions: compiled.functions)
    }

    private struct Parser {
        let variables: [String: EffectValueType]
        let checkpoint: EffectExecutionCheckpoint

        func parseChain(_ first: [String: Any]?, depth: Int, loopDepth: Int) throws -> [EffectOperation] {
            guard depth <= maximumControlDepth else { throw error("CONTROL_DEPTH", "控制结构嵌套不能超过6层", "ネストは6階層までです") }
            var result: [EffectOperation] = []
            var block = first
            while let current = block {
                try checkpoint()
                let id = string(current, "id"), type = string(current, "type")
                let fields = current["fields"] as? [String: Any] ?? [:]
                let target = try targetReference(string(fields, "TARGET", default: "ALL"), sourceID: id)
                switch type {
                case "maurya_set_all_pixels_color_value":
                    result.append(.setColour(.allPixels, try expression(current, "COLOR", .colour), blockID: id))
                case "maurya_set_all_pixels_hsv_value":
                    result.append(
                        .setHSV(
                            .allPixels, h: try expression(current, "H", .number), s: try expression(current, "S", .number),
                            v: try expression(current, "V", .number), blockID: id))
                case "maurya_set_pixel_color_value", "maurya_set_pixel_hsv_value":
                    let pixel = EffectTargetReference.pixel(
                        oneBasedGroup: try expression(current, "GROUP", .number), oneBasedPixel: try expression(current, "PIXEL", .number))
                    if type.hasSuffix("color_value") {
                        result.append(.setColour(pixel, try expression(current, "COLOR", .colour), blockID: id))
                    } else {
                        result.append(
                            .setHSV(
                                pixel, h: try expression(current, "H", .number), s: try expression(current, "S", .number),
                                v: try expression(current, "V", .number), blockID: id))
                    }
                case "maurya_set_pixel_at_color_value", "maurya_set_pixel_at_hsv_value":
                    let pixel = EffectTargetReference.pixelAt(oneBasedIndex: try expression(current, "INDEX", .number))
                    if type.hasSuffix("color_value") {
                        result.append(.setColour(pixel, try expression(current, "COLOR", .colour), blockID: id))
                    } else {
                        result.append(
                            .setHSV(
                                pixel, h: try expression(current, "H", .number), s: try expression(current, "S", .number),
                                v: try expression(current, "V", .number), blockID: id))
                    }
                case "maurya_apply_pixel_colour_list":
                    let colours = try expression(current, "LIST", .colourList)
                    let length = EffectExpression.builtin(.listLength, arguments: [colours], type: .number, nodeID: "\(id):length")
                    for index in 0..<EffectGeometry.pixelCount {
                        try checkpoint()
                        result.append(
                            .setColour(
                                .pixelAt(oneBasedIndex: .number(Double(index + 1))),
                                .listGet(list: colours, index: .arithmetic(.modulo, .number(Double(index)), length), type: .colour),
                                blockID: "\(id):\(index)"))
                    }
                case "maurya_set_color":
                    let colour = hexColour(string(fields, "COLOR", default: "#FFFFFF"))
                    result.append(
                        .setHSV(
                            target, h: .number(Double(colour.hue)), s: .number(Double(colour.saturation)), v: .number(Double(colour.value)),
                            blockID: id))
                case "maurya_set_color_value": result.append(.setColour(target, try expression(current, "COLOR", .colour), blockID: id))
                case "maurya_fade":
                    let colour = hexColour(string(fields, "COLOR", default: "#FFFFFF"))
                    result.append(
                        .fadeHSV(
                            target, h: .number(Double(colour.hue)), s: .number(Double(colour.saturation)), v: .number(Double(colour.value)),
                            duration: .number(max(100, number(fields, "DURATION", default: 1_000))), blockID: id))
                case "maurya_fade_value":
                    result.append(
                        .fadeColour(
                            target, colour: try expression(current, "COLOR", .colour),
                            duration: try expression(current, "DURATION", .number), blockID: id))
                case "maurya_set_hsv":
                    result.append(
                        .setHSV(
                            target, h: .number(wrappedHue(number(fields, "H"))), s: .number(number(fields, "S").clamped(to: 0...255)),
                            v: .number(number(fields, "V").clamped(to: 0...255)), blockID: id))
                case "maurya_set_hsv_value":
                    result.append(
                        .setHSV(
                            target, h: try expression(current, "H", .number), s: try expression(current, "S", .number),
                            v: try expression(current, "V", .number), blockID: id))
                case "maurya_adjust_hsv":
                    result.append(
                        .adjustHSV(
                            target, dh: .number(number(fields, "H").clamped(to: -359...359)),
                            ds: .number(number(fields, "S").clamped(to: -255...255)),
                            dv: .number(number(fields, "V").clamped(to: -255...255)), blockID: id))
                case "maurya_adjust_hsv_value":
                    result.append(
                        .adjustHSV(
                            target, dh: try expression(current, "H", .number), ds: try expression(current, "S", .number),
                            dv: try expression(current, "V", .number), blockID: id))
                case "maurya_mode":
                    result.append(
                        .setMode(
                            target, mode: .number(number(fields, "MODE", default: 1)),
                            parameter: .number(number(fields, "PARAM", default: 128)), blockID: id))
                case "maurya_wait":
                    var milliseconds = number(fields, "DURATION", default: 1_000);
                    if string(fields, "UNIT") == "SEC" { milliseconds *= 1_000 }
                    result.append(.wait(.number(milliseconds.clamped(to: 50...600_000)), blockID: id))
                case "maurya_wait_value":
                    var value = try expression(current, "DURATION", .number);
                    if string(fields, "UNIT") == "SEC" { value = .arithmetic(.multiply, value, .number(1_000)) }
                    result.append(.wait(value, blockID: id))
                case "maurya_seed_random": result.append(.seedRandom(try expression(current, "SEED", .number), blockID: id))
                case "maurya_function_call":
                    result.append(
                        .callFunction(
                            name: string(fields, "NAME").trimmingCharacters(in: .whitespacesAndNewlines), arguments: [], blockID: id))
                case "maurya_apply_colour_list":
                    let colours = try expression(current, "LIST", .colourList)
                    for index in 0..<EffectGeometry.groupCount {
                        try checkpoint()
                        result.append(
                            .setColour(
                                .group(oneBasedIndex: .number(Double(index + 1))),
                                .listGet(list: colours, index: .number(Double(index)), type: .colour), blockID: "\(id):\(index)"))
                    }
                case "maurya_var_set_number", "maurya_var_set_boolean", "maurya_var_set_colour":
                    let expected: EffectValueType =
                        type == "maurya_var_set_number" ? .number : (type == "maurya_var_set_boolean" ? .boolean : .colour)
                    let variable = try checkedVariable(fields, expected: expected, sourceID: id)
                    result.append(.setVariable(id: variable, value: try expression(current, "VALUE", expected), blockID: id))
                case "maurya_var_change_number":
                    let variable = try checkedVariable(fields, expected: .number, sourceID: id)
                    result.append(.changeVariable(id: variable, delta: try expression(current, "VALUE", .number), blockID: id))
                case "maurya_if", "maurya_if_else":
                    result.append(
                        .ifElse(
                            try expression(current, "IF", .boolean),
                            then: try parseChain(inputBlock(current, "DO"), depth: depth + 1, loopDepth: loopDepth),
                            else: try parseChain(inputBlock(current, "ELSE"), depth: depth + 1, loopDepth: loopDepth), blockID: id))
                case "maurya_repeat", "maurya_forever":
                    let body = try nonemptyBody(current, "DO", depth: depth, loopDepth: loopDepth + 1)
                    let count: EffectExpression? =
                        type == "maurya_forever" ? nil : .number(number(fields, "COUNT", default: 1).clamped(to: 1...1_000))
                    result.append(.repeatLoop(count: count, body: body, blockID: id))
                case "maurya_for":
                    let variable = try checkedVariable(fields, expected: .number, sourceID: id),
                        step = try expression(current, "BY", .number)
                    if case .number(0) = step { throw error("ZERO_STEP", "for循环步长不能为0", "forの増分は0にできません", id) }
                    result.append(
                        .forLoop(
                            variableID: variable, from: try expression(current, "FROM", .number),
                            through: try expression(current, "TO", .number), step: step,
                            body: try nonemptyBody(current, "DO", depth: depth, loopDepth: loopDepth + 1), blockID: id))
                case "maurya_while":
                    result.append(
                        .whileLoop(
                            try expression(current, "IF", .boolean),
                            body: try nonemptyBody(current, "DO", depth: depth, loopDepth: loopDepth + 1), blockID: id))
                case "maurya_break":
                    guard loopDepth > 0 else { throw error("BREAK_OUTSIDE_LOOP", "break只能放在循环内部", "breakはループ内だけで使用できます", id) };
                    result.append(.breakLoop(blockID: id))
                case "maurya_continue":
                    guard loopDepth > 0 else { throw error("CONTINUE_OUTSIDE_LOOP", "continue只能放在循环内部", "continueはループ内だけで使用できます", id) };
                    result.append(.continueLoop(blockID: id))
                case "maurya_end":
                    guard next(current) == nil else { throw error("UNREACHABLE_BLOCK", "结束程序后的积木不可达", "終了後のブロックには到達できません", id) }
                    result.append(.end(blockID: id)); block = nil; continue
                default: throw error("UNSUPPORTED_BLOCK", "不支持的积木：\(type)", "未対応ブロックです", id)
                }
                block = next(current)
            }
            return result
        }

        private func expression(_ parent: [String: Any], _ input: String, _ expected: EffectValueType) throws -> EffectExpression {
            try checkpoint()
            guard let source = inputBlock(parent, input) else {
                throw error("MISSING_INPUT", "缺少输入：\(input)", "入力がありません", string(parent, "id"))
            }
            let value = try parseExpression(source)
            guard value.type == expected else { throw typeError(string(source, "id")) }
            return value
        }

        private func parseExpression(_ source: [String: Any]) throws -> EffectExpression {
            try checkpoint()
            let id = string(source, "id"), type = string(source, "type"), fields = source["fields"] as? [String: Any] ?? [:]
            switch type {
            case "math_number": return .number(number(fields, "NUM"))
            case "logic_boolean": return .boolean(string(fields, "BOOL", default: "TRUE") == "TRUE")
            case "maurya_colour_literal": return .colour(hexColour(string(fields, "COLOR", default: "#FFFFFF")))
            case "maurya_var_get_number", "maurya_var_get_boolean", "maurya_var_get_colour":
                let expected: EffectValueType =
                    type == "maurya_var_get_number" ? .number : (type == "maurya_var_get_boolean" ? .boolean : .colour)
                return .variable(id: try checkedVariable(fields, expected: expected, sourceID: id), type: expected)
            case "maurya_elapsed": return .elapsedMilliseconds
            case "maurya_group_value":
                let property: EffectGroupProperty =
                    switch string(fields, "PROPERTY", default: "H") {
                    case "S": .saturation;
                    case "V": .value;
                    case "MODE": .mode;
                    default: .hue
                    }
                return .groupValue(zeroBasedGroup: Int(number(fields, "GROUP").clamped(to: 0...6)), property: property)
            case "maurya_algorithm_unary": return try builtin(source, fields, [("A", .number)], .number)
            case "maurya_algorithm_binary": return try builtin(source, fields, [("A", .number), ("B", .number)], .number)
            case "maurya_algorithm_ternary": return try builtin(source, fields, [("A", .number), ("B", .number), ("C", .number)], .number)
            case "maurya_wave": return try builtin(source, fields, [("PERIOD", .number), ("PHASE", .number)], .number)
            case "maurya_square_wave":
                return .builtin(
                    .squareWave,
                    arguments: [
                        try expression(source, "PERIOD", .number), try expression(source, "DUTY", .number),
                        try expression(source, "PHASE", .number),
                    ], type: .number, nodeID: id)
            case "maurya_noise":
                let function = BuiltinFunction(rawValue: string(fields, "FUNCTION", default: "NOISE_1D")) ?? .noise1D
                var arguments = [try expression(source, "X", .number)]
                if function == .fbmNoise { arguments.append(try expression(source, "OCTAVES", .number)) }
                arguments.append(try expression(source, "SEED", .number))
                return .builtin(function, arguments: arguments, type: .number, nodeID: id)
            case "maurya_random_number":
                return .builtin(
                    .random, arguments: [try expression(source, "LOW", .number), try expression(source, "HIGH", .number)], type: .number,
                    nodeID: id)
            case "maurya_random_colour": return .builtin(.randomColour, arguments: [], type: .colour, nodeID: id)
            case "maurya_colour_unary": return try builtin(source, fields, [("COLOUR", .colour)], .colour)
            case "maurya_colour_adjust": return try builtin(source, fields, [("COLOUR", .colour), ("AMOUNT", .number)], .colour)
            case "maurya_colour_mix": return try builtin(source, fields, [("A", .colour), ("B", .colour), ("AMOUNT", .number)], .colour)
            case "maurya_runtime_number", "maurya_audio_number":
                guard let key = RuntimeInputKey(rawValue: string(fields, "KEY")) else {
                    throw error("INVALID_RUNTIME_INPUT", "运行时输入无效", "ランタイム入力が無効です", id)
                }
                return .runtimeInput(key)
            case "maurya_audio_beat": return .runtimeInput(.audioBeat)
            case "maurya_time_phase":
                let function = BuiltinFunction(rawValue: string(fields, "FUNCTION", default: "CYCLE")) ?? .cycle
                let names = function == .cycle || function == .beatPhase ? ["A"] : ["A", "B", "C"]
                return .builtin(function, arguments: try names.map { try expression(source, $0, .number) }, type: .number, nodeID: id)
            case "maurya_colour_list7": return .list(try (1...7).map { try expression(source, "C\($0)", .colour) }, type: .colourList)
            case "maurya_number_list7": return .list(try (1...7).map { try expression(source, "N\($0)", .number) }, type: .numberList)
            case "maurya_colour_list_get":
                return .listGet(
                    list: try expression(source, "LIST", .colourList), index: try expression(source, "INDEX", .number), type: .colour)
            case "maurya_number_list_get":
                return .listGet(
                    list: try expression(source, "LIST", .numberList), index: try expression(source, "INDEX", .number), type: .number)
            case "maurya_list_length":
                guard let listSource = inputBlock(source, "LIST") else { throw error("MISSING_INPUT", "缺少列表", "リストがありません", id) }
                let list = try parseExpression(listSource); guard isList(list.type) else { throw typeError(id) }
                return .builtin(.listLength, arguments: [list], type: .number, nodeID: id)
            case "maurya_pattern": return try builtin(source, fields, [("PROGRESS", .number)], .numberList)
            case "maurya_pattern_list":
                guard let listSource = inputBlock(source, "LIST") else { throw error("MISSING_INPUT", "缺少图案列表", "パターンリストがありません", id) }
                let list = try parseExpression(listSource); guard isList(list.type) else { throw typeError(id) }
                let function = BuiltinFunction(rawValue: string(fields, "FUNCTION", default: "MIRROR")) ?? .mirror
                let arguments = function == .rotatePattern ? [list, try expression(source, "OFFSET", .number)] : [list]
                return .builtin(function, arguments: arguments, type: list.type, nodeID: id)
            case "math_arithmetic":
                let operation: ArithmeticOperator =
                    switch string(fields, "OP", default: "ADD") {
                    case "MINUS": .subtract;
                    case "MULTIPLY": .multiply;
                    case "DIVIDE": .divide;
                    case "POWER": .power;
                    default: .add
                    }
                return .arithmetic(operation, try expression(source, "A", .number), try expression(source, "B", .number))
            case "math_modulo":
                return .arithmetic(.modulo, try expression(source, "DIVIDEND", .number), try expression(source, "DIVISOR", .number))
            case "maurya_minmax":
                return .arithmetic(
                    string(fields, "OP") == "MAX" ? .maximum : .minimum, try expression(source, "A", .number),
                    try expression(source, "B", .number))
            case "maurya_clamp":
                return .clamp(
                    value: try expression(source, "VALUE", .number), low: try expression(source, "LOW", .number),
                    high: try expression(source, "HIGH", .number))
            case "logic_compare":
                guard let leftSource = inputBlock(source, "A"), let rightSource = inputBlock(source, "B") else {
                    throw error("MISSING_INPUT", "比较缺少输入", "比較入力がありません", id)
                }
                let left = try parseExpression(leftSource), right = try parseExpression(rightSource);
                guard left.type == right.type else { throw typeError(id) }
                let operation = ComparisonOperator(rawValue: string(fields, "OP", default: "EQ")) ?? .equal
                if operation != .equal, operation != .notEqual, left.type != .number { throw typeError(id) }
                return .comparison(operation, left, right)
            case "logic_operation":
                return .logic(
                    string(fields, "OP") == "OR" ? .or : .and, try expression(source, "A", .boolean), try expression(source, "B", .boolean))
            case "logic_negate": return .not(try expression(source, "BOOL", .boolean))
            case "maurya_hsv_colour":
                return .colourFromHSV(
                    hue: try expression(source, "H", .number), saturation: try expression(source, "S", .number),
                    value: try expression(source, "V", .number))
            default: throw error("UNSUPPORTED_EXPRESSION", "不支持的表达式：\(type)", "未対応の式です", id)
            }
        }

        private func builtin(
            _ block: [String: Any], _ fields: [String: Any], _ inputs: [(String, EffectValueType)], _ result: EffectValueType
        ) throws -> EffectExpression {
            guard let function = BuiltinFunction(rawValue: string(fields, "FUNCTION")) else {
                throw error("INVALID_BUILTIN", "算法函数无效", "アルゴリズム関数が無効です", string(block, "id"))
            }
            return .builtin(
                function, arguments: try inputs.map { try expression(block, $0.0, $0.1) }, type: result, nodeID: string(block, "id"))
        }

        private func nonemptyBody(_ block: [String: Any], _ input: String, depth: Int, loopDepth: Int) throws -> [EffectOperation] {
            let body = try parseChain(inputBlock(block, input), depth: depth + 1, loopDepth: loopDepth)
            guard body.isEmpty == false else { throw error("EMPTY_LOOP", "循环内部不能为空", "ループ内は空にできません", string(block, "id")) }
            return body
        }

        private func checkedVariable(_ fields: [String: Any], expected: EffectValueType, sourceID: String) throws -> String {
            let id = variableID(fields); guard variables[id] == expected else { throw typeError(sourceID) }; return id
        }

        private func isList(_ type: EffectValueType) -> Bool {
            type == .numberList || type == .booleanList || type == .colourList || type == .targetList
        }

        private func wrappedHue(_ value: Double) -> Double {
            guard value.isFinite else { return 0 }
            return (value.truncatingRemainder(dividingBy: 360) + 360)
                .truncatingRemainder(dividingBy: 360)
        }

        private func variableID(_ fields: [String: Any]) -> String {
            if let value = fields["VAR"] as? [String: Any] { return string(value, "id") }
            return string(fields, "VAR")
        }

        private func typeError(_ id: String) -> EffectCompileError { error("TYPE_MISMATCH", "输入类型错误", "入力型が一致しません", id) }
        private func error(_ code: String, _ zh: String, _ ja: String, _ id: String = "") -> EffectCompileError {
            compileError(code: code, zh: zh, ja: ja, sourceID: id)
        }
    }

    private static func readVariables(_ root: [String: Any]) throws -> [String: EffectValueType] {
        let values = root["variables"] as? [[String: Any]] ?? []
        guard values.count <= maximumVariables else {
            throw compileError(code: "TOO_MANY_VARIABLES", zh: "变量不能超过16个", ja: "変数は最大16個です")
        }
        var result: [String: EffectValueType] = [:]
        for value in values {
            let id = string(value, "id")
            let type: EffectValueType? =
                switch string(value, "type") {
                case "Number": .number
                case "Boolean": .boolean
                case "Colour": .colour
                default: nil
                }
            guard id.isEmpty == false, let type, result[id] == nil else {
                throw compileError(code: "INVALID_VARIABLE", zh: "变量定义无效", ja: "変数定義が無効です")
            }
            result[id] = type
        }
        return result
    }

    private static func validateBlocklyFunctions(
        operations: [EffectOperation],
        functions: [String: EffectFunctionDefinition]
    ) throws {
        func calls(_ operations: [EffectOperation]) -> Set<String> {
            var result: Set<String> = []
            func visit(_ values: [EffectOperation]) {
                for operation in values {
                    switch operation {
                    case let .callFunction(name, _, _): result.insert(name)
                    case let .ifElse(_, thenBody, elseBody, _): visit(thenBody); visit(elseBody)
                    case let .repeatLoop(_, body, _), let .forLoop(_, _, _, _, body, _), let .whileLoop(_, body, _): visit(body)
                    default: break
                    }
                }
            }
            visit(operations)
            return result
        }
        let allCalls = calls(operations).union(functions.values.flatMap { calls($0.operations) })
        guard let missing = allCalls.first(where: { functions[$0] == nil }) else {
            var complete: Set<String> = []
            func visit(_ name: String, active: inout Set<String>) throws {
                if complete.contains(name) { return }
                guard active.insert(name).inserted else {
                    throw compileError(code: "RECURSIVE_FUNCTION", zh: "禁止递归调用函数\(name)", ja: "関数\(name)の再帰呼び出しは禁止です")
                }
                for child in calls(functions[name]?.operations ?? []).filter({ functions[$0] != nil }) {
                    try visit(child, active: &active)
                }
                active.remove(name); complete.insert(name)
            }
            for name in functions.keys { var active: Set<String> = []; try visit(name, active: &active) }
            return
        }
        throw compileError(code: "UNKNOWN_FUNCTION", zh: "找不到函数\(missing)", ja: "関数\(missing)が見つかりません")
    }

    private static func duration(of operations: [EffectOperation]) -> Int64? {
        var total: Int64 = 0
        for operation in operations {
            let value: Int64
            switch operation {
            case let .wait(expression, _): value = literalDuration(expression) ?? -1
            case let .fadeHSV(_, _, _, _, expression, _), let .fadeColour(_, _, expression, _): value = literalDuration(expression) ?? -1
            case let .repeatLoop(count, body, _):
                guard let count, case let .number(rawCount) = count,
                    let repeatCount = boundedRepeatCount(rawCount),
                    let bodyDuration = duration(of: body),
                    let product = checkedProduct(bodyDuration, repeatCount)
                else { return nil }
                value = product
            case let .forLoop(_, from, through, step, body, _):
                guard case let .number(start) = from, case let .number(end) = through,
                    case let .number(increment) = step, increment != 0,
                    let count = boundedForCount(start: start, end: end, increment: increment),
                    let bodyDuration = duration(of: body),
                    let product = checkedProduct(bodyDuration, count)
                else { return nil }
                value = product
            case let .ifElse(condition, thenBody, elseBody, _):
                guard case let .boolean(flag) = condition, let branch = duration(of: flag ? thenBody : elseBody) else { return nil }
                value = branch
            case let .whileLoop(condition, _, _):
                guard case .boolean(false) = condition else { return nil }
                value = 0
            default: value = 0
            }
            guard value >= 0 else { return nil }
            let (sum, overflow) = total.addingReportingOverflow(value)
            guard overflow == false else { return nil }
            total = min(Int64.max / 2, sum)
        }
        return total
    }

    private static func boundedRepeatCount(_ value: Double) -> Int64? {
        guard value.isNaN == false else { return nil }
        if value <= 0 { return 0 }
        if value >= 1_000 { return 1_000 }
        return Int64(value.rounded(.towardZero))
    }

    private static func boundedForCount(start: Double, end: Double, increment: Double) -> Int64? {
        guard start.isFinite, end.isFinite, increment.isFinite, increment != 0 else { return nil }
        if (increment > 0 && start > end) || (increment < 0 && start < end) { return 0 }
        let raw = Foundation.floor(Swift.abs((end - start) / increment)) + 1
        if raw.isNaN { return 0 }
        if raw >= 1_000 { return 1_000 }
        return Int64(raw)
    }

    private static func checkedProduct(_ lhs: Int64, _ rhs: Int64) -> Int64? {
        let (product, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        return overflow ? nil : product
    }

    private static func literalDuration(_ expression: EffectExpression) -> Int64? {
        guard case let .number(value) = expression, value.isFinite else { return nil }
        if value >= Double(Int64.max) { return Int64.max }
        if value <= Double(Int64.min) { return Int64.min }
        return Int64(value.rounded(.towardZero))
    }

    private static func validateConstantTargets(_ operations: [EffectOperation]) throws {
        for operation in operations {
            let target: EffectTargetReference?
            switch operation {
            case let .setHSV(value, _, _, _, _), let .setColour(value, _, _), let .fadeHSV(value, _, _, _, _, _),
                let .fadeColour(value, _, _, _), let .adjustHSV(value, _, _, _, _), let .setMode(value, _, _, _):
                target = value
            default: target = nil
            }
            if case let .pixel(group, pixel) = target,
                case let .number(g) = group, case let .number(p) = pixel,
                (!g.isFinite || !p.isFinite || g.rounded(.towardZero) != g || p.rounded(.towardZero) != p || g < 1 || g > 7 || p < 1
                    || p > 6)
            {
                throw compileError(code: "PIXEL_RANGE", zh: "灯珠坐标超出范围", ja: "ピクセル座標が範囲外です")
            }
            if case let .pixelAt(index) = target, case let .number(i) = index,
                (!i.isFinite || i.rounded(.towardZero) != i || i < 1 || i > Double(EffectGeometry.pixelCount))
            {
                throw compileError(code: "PIXEL_RANGE", zh: "灯珠编号超出范围", ja: "ピクセル番号が範囲外です")
            }
            switch operation {
            case let .repeatLoop(_, body, _), let .forLoop(_, _, _, _, body, _), let .whileLoop(_, body, _):
                try validateConstantTargets(body)
            case let .ifElse(_, thenBody, elseBody, _): try validateConstantTargets(thenBody + elseBody)
            default: break
            }
        }
    }

    private static func validateReachability(_ operations: [EffectOperation]) throws {
        for (index, operation) in operations.enumerated() {
            switch operation {
            case let .repeatLoop(count, body, blockID):
                try validateReachability(body)
                if count == nil, index != operations.indices.last {
                    throw compileError(
                        code: "UNREACHABLE_BLOCK",
                        zh: "永久循环后的积木不可达",
                        ja: "無限ループ後には到達できません",
                        sourceID: blockID
                    )
                }
            case let .ifElse(_, thenBody, elseBody, _):
                try validateReachability(thenBody)
                try validateReachability(elseBody)
            case let .forLoop(_, _, _, _, body, _), let .whileLoop(_, body, _):
                try validateReachability(body)
            default:
                break
            }
        }
    }

    private struct PendingLightChange {
        let sourceID: String
        let suggestedWaitMilliseconds: Int64
    }

    private struct VisibilityState {
        var pending: [PendingLightChange] = []
        var lastWaitMilliseconds: Int64 = 1_000
    }

    private static func validateObservableStates(_ operations: [EffectOperation]) throws {
        var issues: [EffectCompileIssue] = []
        let state = analyseVisibility(operations, initial: VisibilityState(), issues: &issues)
        appendInvisibleIssues(state.pending, to: &issues)
        if issues.isEmpty == false { throw EffectCompileError(issues: issues) }
    }

    private static func analyseVisibility(
        _ operations: [EffectOperation],
        initial: VisibilityState,
        issues: inout [EffectCompileIssue]
    ) -> VisibilityState {
        var state = initial
        for operation in operations {
            switch operation {
            case let .setHSV(_, _, _, _, sourceID), let .setColour(_, _, sourceID),
                let .adjustHSV(_, _, _, _, sourceID), let .setMode(_, _, _, sourceID):
                state.pending = [
                    PendingLightChange(
                        sourceID: sourceID,
                        suggestedWaitMilliseconds: state.lastWaitMilliseconds
                    )
                ]
            case let .wait(duration, _), let .fadeHSV(_, _, _, _, duration, _),
                let .fadeColour(_, _, duration, _):
                state.pending = []
                if let duration = literalDuration(duration) {
                    state.lastWaitMilliseconds = duration.clamped(to: 100...600_000)
                }
            case let .ifElse(_, thenBody, elseBody, _):
                let thenState = analyseVisibility(thenBody, initial: state, issues: &issues)
                let elseState = analyseVisibility(elseBody, initial: state, issues: &issues)
                state.pending = uniquePending(thenState.pending + elseState.pending)
                state.lastWaitMilliseconds = max(
                    thenState.lastWaitMilliseconds,
                    elseState.lastWaitMilliseconds
                )
            case let .repeatLoop(_, body, _), let .whileLoop(_, body, _):
                let bodyState = analyseVisibility(
                    body,
                    initial: VisibilityState(lastWaitMilliseconds: state.lastWaitMilliseconds),
                    issues: &issues
                )
                appendInvisibleIssues(bodyState.pending, to: &issues)
                state = VisibilityState(lastWaitMilliseconds: bodyState.lastWaitMilliseconds)
            case let .forLoop(_, _, _, _, body, _):
                state = analyseVisibility(body, initial: state, issues: &issues)
            case .end:
                appendInvisibleIssues(state.pending, to: &issues)
                state.pending = []
            default:
                break
            }
        }
        return state
    }

    private static func appendInvisibleIssues(
        _ changes: [PendingLightChange],
        to issues: inout [EffectCompileIssue]
    ) {
        for change in uniquePending(changes).filter({ $0.sourceID.isEmpty == false }) {
            let span = scriptSpan(change.sourceID)
            issues.append(
                EffectCompileIssue(
                    code: "EFFECT_STATE_NOT_OBSERVABLE",
                    messageZh: "该灯光状态持续0 ms，会在显示前被下一轮或程序结束覆盖",
                    messageJa: "このライト状態は0 msのため、表示前に次のループまたは終了で上書きされます",
                    sourceID: change.sourceID,
                    quickFixWaitMilliseconds: change.suggestedWaitMilliseconds.clamped(to: 100...600_000),
                    sourceStart: span?.start,
                    sourceEnd: span?.end
                ))
        }
    }

    private static func uniquePending(_ changes: [PendingLightChange]) -> [PendingLightChange] {
        var seen: Set<String> = []
        return changes.filter { seen.insert($0.sourceID).inserted }
    }

    private static func containsPixelTarget(_ operation: EffectOperation) -> Bool {
        let target: EffectTargetReference?
        switch operation {
        case let .setHSV(value, _, _, _, _), let .setColour(value, _, _), let .fadeHSV(value, _, _, _, _, _),
            let .fadeColour(value, _, _, _), let .adjustHSV(value, _, _, _, _), let .setMode(value, _, _, _):
            target = value
        default: target = nil
        }
        if case .allPixels = target { return true }
        if case .pixel = target { return true }
        if case .pixelAt = target { return true }
        switch operation {
        case let .repeatLoop(_, body, _), let .forLoop(_, _, _, _, body, _), let .whileLoop(_, body, _):
            return body.contains(where: containsPixelTarget)
        case let .ifElse(_, thenBody, elseBody, _): return (thenBody + elseBody).contains(where: containsPixelTarget)
        default: return false
        }
    }

    private static func containsModeOperation(_ operation: EffectOperation) -> Bool {
        switch operation {
        case .setMode: true
        case let .repeatLoop(_, body, _), let .forLoop(_, _, _, _, body, _), let .whileLoop(_, body, _):
            body.contains(where: containsModeOperation)
        case let .ifElse(_, thenBody, elseBody, _): (thenBody + elseBody).contains(where: containsModeOperation)
        default: false
        }
    }

    private static func collectInputs(
        _ operations: [EffectOperation],
        additionalExpressions: [EffectExpression] = []
    ) -> Set<RuntimeInputKey> {
        var result: Set<RuntimeInputKey> = []
        func visit(_ expression: EffectExpression) {
            switch expression {
            case let .runtimeInput(key): result.insert(key)
            case let .arithmetic(_, left, right), let .comparison(_, left, right), let .logic(_, left, right): visit(left); visit(right)
            case let .clamp(value, low, high): visit(value); visit(low); visit(high)
            case let .not(value), let .targetFromIndex(value): visit(value)
            case let .colourFromHSV(h, s, v): visit(h); visit(s); visit(v)
            case let .builtin(_, arguments, _, _), let .functionCall(_, arguments, _, _), let .list(arguments, _): arguments.forEach(visit)
            case let .listGet(list, index, _): visit(list); visit(index)
            case let .dynamicGroupValue(index, _): visit(index)
            default: break
            }
        }
        func visit(_ target: EffectTargetReference) {
            switch target {
            case .all, .allPixels: break
            case let .group(index), let .pixelAt(index), let .value(index): visit(index)
            case let .pixel(group, pixel): visit(group); visit(pixel)
            }
        }
        func visitOperations(_ values: [EffectOperation]) {
            values.forEach { operation in
                switch operation {
                case let .setHSV(target, h, s, v, _), let .adjustHSV(target, h, s, v, _): visit(target); visit(h); visit(s); visit(v)
                case let .setColour(target, value, _): visit(target); visit(value)
                case let .wait(value, _), let .seedRandom(value, _): visit(value)
                case let .fadeHSV(target, h, s, v, duration, _): visit(target); visit(h); visit(s); visit(v); visit(duration)
                case let .fadeColour(target, colour, duration, _): visit(target); visit(colour); visit(duration)
                case let .setMode(target, mode, parameter, _): visit(target); visit(mode); visit(parameter)
                case let .setVariable(_, value, _), let .changeVariable(_, value, _): visit(value)
                case let .setListItem(_, index, value, _): visit(index); visit(value)
                case let .callFunction(_, arguments, _): arguments.forEach(visit)
                case let .ifElse(condition, thenBody, elseBody, _): visit(condition); visitOperations(thenBody + elseBody)
                case let .repeatLoop(count, body, _): count.map(visit); visitOperations(body)
                case let .forLoop(_, from, through, step, body, _): visit(from); visit(through); visit(step); visitOperations(body)
                case let .whileLoop(condition, body, _): visit(condition); visitOperations(body)
                case .breakLoop, .continueLoop, .end: break
                }
            }
        }
        visitOperations(operations)
        additionalExpressions.forEach(visit)
        return result
    }

    private static func canonicalJSON(operations: [EffectOperation], functions: [String: EffectFunctionDefinition]) -> String {
        EffectCanonicalJSON.encode(operations: operations, functions: functions)
    }

    private static func compileError(code: String, zh: String, ja: String, sourceID: String = "") -> EffectCompileError {
        let span = scriptSpan(sourceID)
        return EffectCompileError(issues: [
            EffectCompileIssue(code: code, messageZh: zh, messageJa: ja, sourceID: sourceID, sourceStart: span?.start, sourceEnd: span?.end)
        ])
    }

    private static func scriptSpan(_ sourceID: String) -> (start: Int, end: Int)? {
        let fields = sourceID.split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count >= 3, fields[0] == "script", let start = Int(fields[1]), let end = Int(fields[2]) else { return nil }
        return (start, end)
    }

    private static func countBlocks(_ block: [String: Any]) -> Int {
        var result = 1
        if let inputs = block["inputs"] as? [String: Any] {
            for value in inputs.values {
                if let wrapper = value as? [String: Any], let child = (wrapper["block"] ?? wrapper["shadow"]) as? [String: Any] {
                    result += countBlocks(child)
                }
            }
        }
        if let following = next(block) { result += countBlocks(following) }
        return result
    }

    private static func next(_ block: [String: Any]) -> [String: Any]? {
        ((block["next"] as? [String: Any])?["block"] as? [String: Any])
    }

    private static func inputBlock(_ block: [String: Any], _ name: String) -> [String: Any]? {
        guard let wrapper = (block["inputs"] as? [String: Any])?[name] as? [String: Any] else { return nil }
        return (wrapper["block"] ?? wrapper["shadow"]) as? [String: Any]
    }

    private static func targetReference(_ raw: String, sourceID: String) throws -> EffectTargetReference {
        if raw == "ALL" { return .all }
        guard let zeroBased = Int(raw), (0...6).contains(zeroBased) else {
            throw compileError(code: "INVALID_TARGET", zh: "目标灯组无效", ja: "ライトグループが無効です", sourceID: sourceID)
        }
        return .group(oneBasedIndex: .number(Double(zeroBased + 1)))
    }

    private static func hexColour(_ source: String) -> EffectColour {
        let value = Int(source.drop(while: { $0 == "#" }), radix: 16) ?? 0xFF_FF_FF
        return EffectMath.rgbToHSV(red: value >> 16 & 255, green: value >> 8 & 255, blue: value & 255)
    }

    private static func string(_ dictionary: [String: Any], _ key: String, default fallback: String = "") -> String {
        dictionary[key] as? String ?? fallback
    }

    private static func number(_ dictionary: [String: Any], _ key: String, default fallback: Double = 0) -> Double {
        (dictionary[key] as? NSNumber)?.doubleValue ?? Double(dictionary[key] as? String ?? "") ?? fallback
    }
}

private extension BinaryInteger {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
