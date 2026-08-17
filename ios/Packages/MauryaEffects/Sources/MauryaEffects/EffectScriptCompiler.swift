import Foundation

/// Android-compatible compiler for the textual Maurya Script language.
public enum EffectScriptCompiler: Sendable {
    public static let maximumSourceBytes = 256 * 1024

    public static func compile(_ source: String) throws -> CompiledEffect {
        try compile(source, checkpoint: {})
    }

    static func compile(_ source: String, checkpoint: @escaping EffectExecutionCheckpoint) throws -> CompiledEffect {
        try checkpoint()
        guard source.utf8.count <= maximumSourceBytes else {
            throw EffectCompileError(issues: [
                .init(
                    code: "SCRIPT_SOURCE_LIMIT",
                    messageZh: "代码不能超过256 KiB",
                    messageJa: "コードは256 KiB以下にしてください"
                )
            ])
        }
        return try ScriptParser(source: source, checkpoint: checkpoint).parse()
    }

    public static func template(_ name: String = "新灯效") -> String {
        let escaped = name.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
            effect "\(escaped)" {
                forever {
                    all.mode(STROBE, 128);
                    all.color("#FF2D55");
                    wait(2s);
                    all.color("#1677FF");
                    wait(2s);
                }
            }
            """
    }
}

private enum ScriptTokenKind: Sendable { case identifier, number, string, symbol, eof }

private struct ScriptToken: Sendable {
    let kind: ScriptTokenKind
    let text: String
    let start: Int
    let end: Int
    let line: Int
    let column: Int
}

private struct ScriptLexer {
    let characters: [Character]
    let checkpoint: EffectExecutionCheckpoint
    var index = 0
    var utf16Offset = 0
    var line = 1
    var column = 1

    init(source: String, checkpoint: @escaping EffectExecutionCheckpoint) {
        characters = Array(source)
        self.checkpoint = checkpoint
    }

    mutating func scan() throws -> [ScriptToken] {
        var result: [ScriptToken] = []
        while index < characters.count {
            try checkpoint()
            if characters[index].isWhitespace { advance(); continue }
            if starts(with: "//") { while index < characters.count, characters[index] != "\n" { advance() }; continue }
            if starts(with: "/*") { try blockComment(); continue }
            if characters[index].isLetter || characters[index] == "_" { result.append(identifier()); continue }
            if characters[index].isNumber || (characters[index] == "." && characters[safe: index + 1]?.isNumber == true) {
                result.append(number()); continue
            }
            if characters[index] == "\"" { result.append(try string()); continue }
            result.append(symbol())
        }
        result.append(.init(kind: .eof, text: "", start: utf16Offset, end: utf16Offset, line: line, column: column))
        return result
    }

    private mutating func blockComment() throws {
        let start = tokenStart(); advance(); advance()
        while index < characters.count, !starts(with: "*/") { advance() }
        guard index < characters.count else { throw syntax(start, "块注释没有结束", "ブロックコメントが閉じられていません") }
        advance(); advance()
    }

    private mutating func identifier() -> ScriptToken {
        let start = tokenStart()
        while let c = characters[safe: index], c.isLetter || c.isNumber || c == "_" { advance() }
        return make(.identifier, start)
    }

    private mutating func number() -> ScriptToken {
        let start = tokenStart(); var dot = false
        while let c = characters[safe: index] {
            if c == ".", !dot { dot = true; advance() } else if c.isNumber { advance() } else { break }
        }
        return make(.number, start)
    }

    private mutating func string() throws -> ScriptToken {
        let start = tokenStart(); advance(); var value = ""
        while let c = characters[safe: index], c != "\"" {
            if c == "\\" {
                advance()
                guard let escaped = characters[safe: index] else { break }
                value.append(escaped == "n" ? "\n" : escaped == "t" ? "\t" : escaped)
                advance()
            } else {
                value.append(c); advance()
            }
        }
        guard index < characters.count else { throw syntax(start, "字符串没有结束", "文字列が閉じられていません") }
        advance()
        return .init(kind: .string, text: value, start: start.utf16Offset, end: utf16Offset, line: start.line, column: start.column)
    }

    private mutating func symbol() -> ScriptToken {
        let start = tokenStart()
        let pair = String(characters[index..<min(index + 2, characters.count)])
        if ["==", "!=", "<=", ">=", "+=", "-=", "&&", "||"].contains(pair) { advance(); advance() } else { advance() }
        return make(.symbol, start)
    }

    private func starts(with text: String) -> Bool {
        let wanted = Array(text)
        guard index + wanted.count <= characters.count else { return false }
        return Array(characters[index..<index + wanted.count]) == wanted
    }

    private mutating func advance() {
        guard index < characters.count else { return }
        let width = String(characters[index]).utf16.count
        utf16Offset += width
        if characters[index] == "\n" { line += 1; column = 1 } else { column += width }
        index += 1
    }

    private typealias TokenStart = (characterIndex: Int, utf16Offset: Int, line: Int, column: Int)

    private func tokenStart() -> TokenStart { (index, utf16Offset, line, column) }
    private func make(_ kind: ScriptTokenKind, _ start: TokenStart) -> ScriptToken {
        .init(
            kind: kind, text: String(characters[start.characterIndex..<index]), start: start.utf16Offset, end: utf16Offset,
            line: start.line, column: start.column)
    }
    private func syntax(_ start: TokenStart, _ zh: String, _ ja: String) -> EffectCompileError {
        .init(issues: [
            .init(
                code: "SCRIPT_SYNTAX", messageZh: "第\(start.line)行第\(start.column)列：\(zh)",
                messageJa: "\(start.line)行\(start.column)列：\(ja)",
                sourceID: "script:\(start.utf16Offset):\(start.utf16Offset):\(start.line):\(start.column)", sourceStart: start.utf16Offset,
                sourceEnd: start.utf16Offset)
        ])
    }
}

private final class ScriptParser {
    private let tokens: [ScriptToken]
    private let checkpoint: EffectExecutionCheckpoint
    private var current = 0
    private var nodes = 0
    private var loopDepth = 0
    private var variables: [String: EffectValueType] = [:]
    private var aliases: [String: String] = [:]
    private var functions: [String: EffectFunctionDefinition] = [:]
    private var currentFunction: String?

    init(source: String, checkpoint: @escaping EffectExecutionCheckpoint) throws {
        self.checkpoint = checkpoint
        var lexer = ScriptLexer(source: source, checkpoint: checkpoint)
        tokens = try lexer.scan()
    }

    func parse() throws -> CompiledEffect {
        try checkpoint()
        while match("fn") { try functionDefinition(start: previous) }
        _ = try expect("effect", "需要以 effect 开始", "effect で開始してください")
        if peek.kind == .string { _ = advance() }
        aliases.removeAll()
        let operations = try block()
        guard isAtEnd else { throw error(peek, "程序结束后存在多余内容", "プログラム末尾に不要な内容があります") }
        guard !operations.isEmpty else { throw error(previous, "程序不能为空", "プログラムを空にはできません") }
        try validateFunctionGraph()
        return try EffectCompiler.compile(
            operations: operations, nodeCount: nodes, variables: variables, functions: functions, checkpoint: checkpoint)
    }

    private func functionDefinition(start: ScriptToken) throws {
        try checkpoint()
        guard functions.count < 16 else { throw error(start, "自定义函数不能超过16个", "カスタム関数は16個までです") }
        let name = try identifier("函数名无效", "関数名が無効です").text
        guard functions[name] == nil else { throw error(previous, "函数\(name) 已存在", "関数\(name) は既に存在します") }
        _ = try expect("(", "函数名后需要“(”", "関数名の後に「(」が必要です")
        let savedAliases = aliases; aliases.removeAll(); currentFunction = name
        var parameters: [EffectFunctionParameter] = []
        if !check(")") {
            repeat {
                guard parameters.count < 8 else { throw error(peek, "函数参数不能超过8个", "関数引数は8個までです") }
                let type = try parseType(), sourceName = try identifier("参数名无效", "引数名が無効です").text
                guard aliases[sourceName] == nil else { throw error(previous, "参数名重复", "引数名が重複しています") }
                let id = "fn:\(name):param:\(sourceName)"; aliases[sourceName] = id; variables[id] = type
                parameters.append(.init(name: sourceName, variableID: id, type: type))
            } while match(",")
        }
        _ = try expect(")", "函数参数后需要“)”", "関数引数の後に「)」が必要です")
        let returnType = match(":") ? try parseType() : nil
        functions[name] = .init(name: name, parameters: parameters, returnType: returnType, operations: [])
        _ = try expect("{", "函数体需要“{”", "関数本体には「{」が必要です")
        var operations: [EffectOperation] = [], returnExpression: EffectExpression?
        while !check("}"), !isAtEnd {
            try checkpoint()
            if match("return") {
                if let returnType { let value = try expression(); try requireType(value, returnType); returnExpression = value }
                _ = try expect(";", "return后需要分号", "returnの後に「;」が必要です")
                guard check("}") else { throw error(peek, "return必须是函数最后一条语句", "returnは関数の最後に置いてください") }
            } else {
                operations.append(try statement())
            }
        }
        _ = try expect("}", "函数体需要“}”", "関数本体には「}」が必要です")
        if returnType != nil, returnExpression == nil { throw error(start, "有返回值函数必须return", "戻り値関数にはreturnが必要です") }
        if returnType != nil,
            operations.contains(where: {
                if case .setVariable = $0 {
                    false
                } else if case .changeVariable = $0 {
                    false
                } else if case .setListItem = $0 {
                    false
                } else {
                    true
                }
            })
        {
            throw error(start, "有返回值函数只能包含局部计算", "戻り値関数にはローカル計算だけを記述できます")
        }
        functions[name] = .init(
            name: name, parameters: parameters, returnType: returnType, operations: operations, returnExpression: returnExpression,
            localVariableIDs: Set(aliases.values))
        aliases = savedAliases; currentFunction = nil
    }

    private func block() throws -> [EffectOperation] {
        try checkpoint()
        _ = try expect("{", "需要“{”", "「{」が必要です")
        var result: [EffectOperation] = []
        while !check("}"), !isAtEnd { try checkpoint(); result.append(try statement()) }
        _ = try expect("}", "需要“}”", "「}」が必要です")
        return result
    }

    private func statement() throws -> EffectOperation {
        try checkpoint()
        let start = peek; nodes += 1
        guard nodes <= 300 else { throw error(start, "程序步骤不能超过300", "プログラムは300ステップまでです") }
        if match("let") { return try variableDeclaration(start) }
        if match("if") { return try ifStatement(start) }
        if match("repeat") {
            _ = try expect("(", "repeat后需要“(”", "repeatの後に「(」が必要です"); let count = try typedExpression(.number);
            _ = try expect(")", "repeat次数后需要“)”", "repeat回数の後に「)」が必要です"); return try loop(start, count)
        }
        if match("forever") { return try loop(start, nil) }
        if match("for") { return try forStatement(start) }
        if match("while") { return try whileStatement(start) }
        if match("break") {
            guard loopDepth > 0 else { throw error(start, "break只能用于循环内部", "breakはループ内だけで使用できます") };
            _ = try expect(";", "break后需要分号", "breakの後に「;」が必要です"); return .breakLoop(blockID: sourceID(start))
        }
        if match("continue") {
            guard loopDepth > 0 else { throw error(start, "continue只能用于循环内部", "continueはループ内だけで使用できます") };
            _ = try expect(";", "continue后需要分号", "continueの後に「;」が必要です"); return .continueLoop(blockID: sourceID(start))
        }
        if match("end") { _ = try expect(";", "end后需要分号", "endの後に「;」が必要です"); return .end(blockID: sourceID(start)) }
        if match("wait") { return try waitStatement(start) }
        if match("seedRandom") {
            _ = try expect("(", "seedRandom后需要“(”", "seedRandomの後に「(」が必要です"); let seed = try typedExpression(.number);
            _ = try expect(")", "随机种子后需要“)”", "乱数シードの後に「)」が必要です"); _ = try expect(";", "seedRandom后需要分号", "seedRandomの後に「;」が必要です");
            return .seedRandom(seed, blockID: sourceID(start))
        }
        if isDeclaredNonTarget(peek) { return try assignment(start) }
        if check("all") || check("allPixels") || check("group") || check("pixel") || check("pixelAt") || isTargetVariable(peek) {
            return try lightStatement(start)
        }
        if peek.kind == .identifier, functions[peek.text]?.returnType == nil, tokens[safe: current + 1]?.text == "(" {
            return try functionCallStatement(start)
        }
        if peek.kind == .identifier { return try assignment(start) }
        throw error(peek, "无法识别的语句“\(peek.text)”", "認識できない文「\(peek.text)」です")
    }

    private func variableDeclaration(_ start: ScriptToken) throws -> EffectOperation {
        let sourceName = try identifier("变量名无效", "変数名が無効です").text
        guard aliases[sourceName] == nil else { throw error(previous, "变量\(sourceName)已经存在", "変数\(sourceName)は既に存在します") }
        let declared = match(":") ? try parseType() : nil
        _ = try expect("=", "变量初始值前需要“=”", "初期値の前に「=」が必要です")
        var value = try expression()
        if let declared, declared.elementType != nil, case .list([], _) = value { value = .list([], type: declared) }
        let type = declared ?? value.type; try requireType(value, type)
        let id = currentFunction.map { "fn:\($0):local:\(sourceName)" } ?? sourceName
        aliases[sourceName] = id; variables[id] = type
        _ = try expect(";", "变量声明后需要分号", "変数宣言の後に「;」が必要です")
        return .setVariable(id: id, value: value, blockID: sourceID(start))
    }

    private func assignment(_ start: ScriptToken) throws -> EffectOperation {
        let sourceName = advance().text, id = aliases[sourceName] ?? sourceName
        guard let type = variables[id] else { throw error(start, "找不到变量\(sourceName)", "変数\(sourceName)が見つかりません") }
        if match("[") {
            guard let element = type.elementType else { throw error(start, "只有列表支持索引赋值", "インデックス代入にはリストが必要です") }
            let index = try typedExpression(.number); _ = try expect("]", "列表索引后需要“]”", "リストの添字の後に「]」が必要です");
            _ = try expect("=", "列表元素后需要“=”", "リスト要素の後に「=」が必要です")
            let value = try typedExpression(element); _ = try expect(";", "赋值后需要分号", "代入の後に「;」が必要です")
            return .setListItem(id: id, index: index, value: value, blockID: sourceID(start))
        }
        if match("=") {
            let value = try expression(); try requireType(value, type); _ = try expect(";", "赋值后需要分号", "代入の後に「;」が必要です");
            return .setVariable(id: id, value: value, blockID: sourceID(start))
        }
        if match("+=") || match("-=") {
            let subtract = previous.text == "-=";
            guard type == .number else { throw error(start, "只有数值变量支持+=或-=", "数値変数だけが+=または-=を使用できます") }
            var delta = try typedExpression(.number); if subtract { delta = .arithmetic(.subtract, .number(0), delta) }
            _ = try expect(";", "赋值后需要分号", "代入の後に「;」が必要です"); return .changeVariable(id: id, delta: delta, blockID: sourceID(start))
        }
        throw error(peek, "变量后需要=、+=或-=", "変数の後に=、+=、-=が必要です")
    }

    private func ifStatement(_ start: ScriptToken) throws -> EffectOperation {
        _ = try expect("(", "if后需要“(”", "ifの後に「(」が必要です"); let condition = try typedExpression(.boolean);
        _ = try expect(")", "if条件后需要“)”", "if条件の後に「)」が必要です")
        let thenBody = try block(), elseBody = match("else") ? try block() : []
        return .ifElse(condition, then: thenBody, else: elseBody, blockID: sourceID(start))
    }

    private func loop(_ start: ScriptToken, _ count: EffectExpression?) throws -> EffectOperation {
        try checkpoint()
        loopDepth += 1; defer { loopDepth -= 1 }; let body = try block()
        guard !body.isEmpty else { throw error(start, "循环不能为空", "ループを空にはできません") }
        return .repeatLoop(count: count, body: body, blockID: sourceID(start))
    }

    private func forStatement(_ start: ScriptToken) throws -> EffectOperation {
        try checkpoint()
        _ = try expect("(", "for后需要“(”", "forの後に「(」が必要です"); let cStyle = match("let")
        let sourceName = try identifier("for变量名无效", "for変数名が無効です").text, existingID = aliases[sourceName]
        if let existingID, variables[existingID] != .number { throw error(previous, "for变量必须是数值", "for変数は数値である必要があります") }
        let id = existingID ?? currentFunction.map { "fn:\($0):local:\(sourceName)" } ?? sourceName; aliases[sourceName] = id;
        variables[id] = .number
        let from: EffectExpression, through: EffectExpression, step: EffectExpression
        if cStyle {
            _ = try expect("=", "for变量后需要=", "for変数の後に「=」が必要です"); from = try typedExpression(.number);
            _ = try expect(";", "for初始值后需要分号", "for初期値の後に「;」が必要です")
            guard try identifier("for条件变量无效", "for条件変数が無効です").text == sourceName else {
                throw error(previous, "for条件必须使用同一变量", "for条件には同じ変数を使用してください")
            }
            let comparison = advance();
            guard ["<", "<=", ">", ">="].contains(comparison.text) else {
                throw error(comparison, "for条件需要<、<=、>或>=", "for条件には<、<=、>、>=が必要です")
            }
            let boundary = try typedExpression(.number); _ = try expect(";", "for条件后需要分号", "for条件の後に「;」が必要です")
            guard try identifier("for增量变量无效", "for増分変数が無効です").text == sourceName else {
                throw error(previous, "for增量必须使用同一变量", "for増分には同じ変数を使用してください")
            }
            let op = advance(); guard op.text == "+=" || op.text == "-=" else { throw error(op, "for增量需要+=或-=", "for増分には+=または-=が必要です") }
            let magnitude = try typedExpression(.number);
            step = op.text == "-=" ? .arithmetic(.multiply, magnitude, .number(-1)) : magnitude
            through =
                comparison.text == "<"
                ? .arithmetic(.subtract, boundary, .number(1)) : comparison.text == ">" ? .arithmetic(.add, boundary, .number(1)) : boundary
        } else {
            _ = try expect("from", "for变量后需要from", "for変数の後にfromが必要です"); from = try typedExpression(.number);
            _ = try expect("to", "for起点后需要to", "for開始値の後にtoが必要です"); through = try typedExpression(.number);
            _ = try expect("step", "for终点后需要step", "for終了値の後にstepが必要です"); step = try typedExpression(.number)
        }
        if case .number(0) = step { throw error(previous, "for步长不能为0", "forの増分は0にできません") }
        _ = try expect(")", "for参数后需要“)”", "forパラメータの後に「)」が必要です"); loopDepth += 1; defer { loopDepth -= 1 }
        return .forLoop(variableID: id, from: from, through: through, step: step, body: try block(), blockID: sourceID(start))
    }

    private func whileStatement(_ start: ScriptToken) throws -> EffectOperation {
        try checkpoint()
        _ = try expect("(", "while后需要“(”", "whileの後に「(」が必要です"); let condition = try typedExpression(.boolean);
        _ = try expect(")", "while条件后需要“)”", "while条件の後に「)」が必要です")
        loopDepth += 1; defer { loopDepth -= 1 }; return .whileLoop(condition, body: try block(), blockID: sourceID(start))
    }

    private func waitStatement(_ start: ScriptToken) throws -> EffectOperation {
        _ = try expect("(", "wait后需要“(”", "waitの後に「(」が必要です"); let duration = try durationExpression();
        _ = try expect(")", "wait时间后需要“)”", "wait時間の後に「)」が必要です"); _ = try expect(";", "wait后需要分号", "waitの後に「;」が必要です")
        return .wait(duration, blockID: sourceID(start))
    }

    private func lightStatement(_ start: ScriptToken) throws -> EffectOperation {
        let target = try target(); _ = try expect(".", "灯组后需要“.”", "対象の後に「.」が必要です");
        let action = try identifier("灯光操作无效", "ライト操作が無効です").text; _ = try expect("(", "灯光操作后需要“(”", "ライト操作の後に「(」が必要です")
        let id: String
        let operation: EffectOperation
        switch action {
        case "color":
            let colour = try typedExpression(.colour); _ = try expect(")", "灯光操作后需要“)”", "ライト操作の後に「)」が必要です");
            _ = try expect(";", "灯光操作后需要分号", "ライト操作の後に「;」が必要です"); id = sourceID(start); operation = .setColour(target, colour, blockID: id)
        case "hsv", "adjustHsv":
            let h = try numberArgument(), s = try numberArgument(), v = try typedExpression(.number);
            _ = try expect(")", "灯光操作后需要“)”", "ライト操作の後に「)」が必要です"); _ = try expect(";", "灯光操作后需要分号", "ライト操作の後に「;」が必要です");
            id = sourceID(start);
            operation =
                action == "hsv" ? .setHSV(target, h: h, s: s, v: v, blockID: id) : .adjustHSV(target, dh: h, ds: s, dv: v, blockID: id)
        case "fade":
            let colour = try typedExpression(.colour); _ = try expect(",", "fade颜色后需要逗号", "fadeの色の後に「,」が必要です");
            let duration = try durationExpression(); _ = try expect(")", "灯光操作后需要“)”", "ライト操作の後に「)」が必要です");
            _ = try expect(";", "灯光操作后需要分号", "ライト操作の後に「;」が必要です"); id = sourceID(start);
            operation = .fadeColour(target, colour: colour, duration: duration, blockID: id)
        case "mode":
            let mode = try typedExpression(.number); _ = try expect(",", "mode后需要参数", "modeの後にパラメータが必要です");
            let parameter = try typedExpression(.number); _ = try expect(")", "灯光操作后需要“)”", "ライト操作の後に「)」が必要です");
            _ = try expect(";", "灯光操作后需要分号", "ライト操作の後に「;」が必要です"); id = sourceID(start);
            operation = .setMode(target, mode: mode, parameter: parameter, blockID: id)
        default: throw error(previous, "不支持的灯光操作\(action)", "未対応のライト操作\(action)です")
        }
        return operation
    }

    private func target() throws -> EffectTargetReference {
        if match("all") { return .all }; if match("allPixels") { return .allPixels }
        if isTargetVariable(peek) { let name = advance().text, id = aliases[name] ?? name; return .value(.variable(id: id, type: .target)) }
        if match("pixel") {
            _ = try expect("(", "pixel后需要“(”", "pixelの後に「(」が必要です"); let group = try typedExpression(.number);
            _ = try expect(",", "pixel灯组后需要逗号", "pixelのグループ後に「,」が必要です"); let pixel = try typedExpression(.number);
            _ = try expect(")", "pixel后需要“)”", "pixelの後に「)」が必要です"); return .pixel(oneBasedGroup: group, oneBasedPixel: pixel)
        }
        if match("pixelAt") {
            _ = try expect("(", "pixelAt后需要“(”", "pixelAtの後に「(」が必要です"); let index = try typedExpression(.number);
            _ = try expect(")", "pixelAt后需要“)”", "pixelAtの後に「)」が必要です"); return .pixelAt(oneBasedIndex: index)
        }
        _ = try expect("group", "目标必须是all、group、pixel或pixelAt", "対象はall、group、pixel、pixelAtです");
        _ = try expect("(", "group后需要“(”", "groupの後に「(」が必要です"); let index = try typedExpression(.number);
        _ = try expect(")", "灯组编号后需要“)”", "グループ番号の後に「)」が必要です")
        if case let .number(value) = index, !(1...7).contains(Int(value.rounded())) { throw error(previous, "灯组编号必须为1到7", "グループ番号は1から7です") }
        return .group(oneBasedIndex: index)
    }

    private func functionCallStatement(_ start: ScriptToken) throws -> EffectOperation {
        try checkpoint()
        let token = advance(), parsed = try functionArguments(token);
        guard parsed.0.returnType == nil else { throw error(token, "有返回值函数不能作为独立语句", "戻り値関数は単独文にできません") };
        _ = try expect(";", "函数调用后需要分号", "関数呼び出しの後に「;」が必要です")
        return .callFunction(name: parsed.0.name, arguments: parsed.1, blockID: sourceID(start))
    }

    private func expression() throws -> EffectExpression { try orExpression() }
    private func orExpression() throws -> EffectExpression {
        var value = try andExpression();
        while match("||") { value = .logic(.or, try requiring(value, .boolean), try typed({ try andExpression() }, .boolean)) };
        return value
    }
    private func andExpression() throws -> EffectExpression {
        var value = try equality();
        while match("&&") { value = .logic(.and, try requiring(value, .boolean), try typed({ try equality() }, .boolean)) }; return value
    }
    private func equality() throws -> EffectExpression {
        var value = try comparison();
        while match("==", "!=") {
            let op: ComparisonOperator = previous.text == "==" ? .equal : .notEqual, right = try comparison();
            guard value.type == right.type else { throw error(previous, "比较类型不一致", "比較する型が一致しません") }; value = .comparison(op, value, right)
        }; return value
    }
    private func comparison() throws -> EffectExpression {
        var value = try term();
        while match("<", "<=", ">", ">=") {
            let text = previous.text, right = try term(); try requireType(value, .number); try requireType(right, .number);
            let op: ComparisonOperator =
                text == "<" ? .lessThan : text == "<=" ? .lessThanOrEqual : text == ">" ? .greaterThan : .greaterThanOrEqual
            value = .comparison(op, value, right)
        }; return value
    }
    private func term() throws -> EffectExpression {
        var value = try factor();
        while match("+", "-") {
            let op: ArithmeticOperator = previous.text == "+" ? .add : .subtract; value = try arithmetic(op, value, factor())
        }; return value
    }
    private func factor() throws -> EffectExpression {
        var value = try unary();
        while match("*", "/", "%") {
            let op: ArithmeticOperator = previous.text == "*" ? .multiply : previous.text == "/" ? .divide : .modulo;
            value = try arithmetic(op, value, unary())
        }; return value
    }
    private func unary() throws -> EffectExpression {
        if match("!") { return .not(try typedExpression(.boolean, parse: unary)) };
        if match("-") { return .arithmetic(.subtract, .number(0), try typedExpression(.number, parse: unary)) }; return try primary()
    }

    private func primary() throws -> EffectExpression {
        nodes += 1; guard nodes <= 300 else { throw error(peek, "程序步骤不能超过300", "プログラムは300ステップまでです") }
        let token = advance(); var result: EffectExpression
        if token.kind == .number {
            guard var number = Double(token.text), number.isFinite else { throw error(token, "数字无效", "数値が無効です") };
            if match("s") { number *= 1_000 } else { _ = match("ms") }; result = .number(number)
        } else if token.kind == .string {
            result = .colour(try colour(token))
        } else if token.text == "true" {
            result = .boolean(true)
        } else if token.text == "false" {
            result = .boolean(false)
        } else if token.text == "STEADY" {
            result = .number(1)
        } else if token.text == "STROBE" {
            result = .number(3)
        } else if token.text == "elapsedMs" {
            result = .elapsedMilliseconds
        } else if token.kind == .identifier, let id = aliases[token.text], let type = variables[id] {
            result = .variable(id: id, type: type)
        } else if token.text == "all" {
            result = .target(.all)
        } else if token.text == "[" {
            result = try listLiteral(token)
        } else if token.text == "(" {
            result = try expression(); _ = try expect(")", "表达式后需要“)”", "式の後に「)」が必要です")
        } else if token.text == "group" {
            result = try groupExpression(token)
        } else if ["sensor", "audio", "time"].contains(token.text) {
            result = try runtimeExpression(token)
        } else if token.kind == .identifier, functions[token.text] != nil, check("(") {
            let parsed = try functionArguments(token);
            guard let type = parsed.0.returnType else { throw error(token, "流程函数不能用于表达式", "手続き関数は式に使用できません") };
            result = .functionCall(name: token.text, arguments: parsed.1, type: type, nodeID: sourceID(token))
        } else if token.kind == .identifier, check("(") {
            result = try builtin(token)
        } else if token.kind == .identifier, let type = variables[aliases[token.text] ?? token.text] {
            result = .variable(id: aliases[token.text] ?? token.text, type: type)
        } else {
            throw error(token, "表达式无效", "式が無効です")
        }
        while true {
            if match("[") {
                guard let element = result.type.elementType else { throw error(previous, "只有列表支持索引读取", "インデックス参照にはリストが必要です") };
                let index = try typedExpression(.number); _ = try expect("]", "列表索引后需要“]”", "リストの添字の後に「]」が必要です");
                result = .listGet(list: result, index: index, type: element)
            } else if match(".") {
                let property = try identifier("列表属性无效", "リストのプロパティが無効です");
                guard property.text == "length", result.type.elementType != nil else {
                    throw error(property, "只支持列表.length", "リストの.lengthだけを使用できます")
                }; result = .builtin(.listLength, arguments: [result], type: .number, nodeID: sourceID(property))
            } else {
                return result
            }
        }
    }

    private func listLiteral(_ token: ScriptToken) throws -> EffectExpression {
        if match("]") { return .list([], type: .numberList) }
        var elements: [EffectExpression] = []
        repeat {
            guard elements.count < EffectGeometry.pixelCount else {
                throw error(token, "列表不能超过\(EffectGeometry.pixelCount)项", "リストは\(EffectGeometry.pixelCount)項目までです")
            }; elements.append(try expression())
        } while match(",")
        _ = try expect("]", "列表需要“]”", "リストには「]」が必要です"); let element = elements[0].type
        guard element.elementType == nil, elements.allSatisfy({ $0.type == element }), let list = element.listType else {
            throw error(token, "列表必须是同一基础类型且不能嵌套", "リストは同じ基本型で、ネストできません")
        }
        return .list(elements, type: list)
    }

    private func groupExpression(_ token: ScriptToken) throws -> EffectExpression {
        _ = try expect("(", "group后需要“(”", "groupの後に「(」が必要です"); let index = try typedExpression(.number);
        _ = try expect(")", "灯组编号后需要“)”", "グループ番号の後に「)」が必要です")
        if case let .number(value) = index, !(1...7).contains(Int(value.rounded())) { throw error(token, "灯组编号必须为1到7", "グループ番号は1から7です") }
        guard match(".") else { return .targetFromIndex(index) }; let property = try identifier("状态属性无效", "状態プロパティが無効です").text
        let mapped: EffectGroupProperty =
            property == "hue"
            ? .hue : property == "saturation" ? .saturation : property == "value" ? .value : property == "mode" ? .mode : { _ in .hue }(())
        guard ["hue", "saturation", "value", "mode"].contains(property) else { throw error(previous, "状态属性无效", "状態プロパティが無効です") }
        return .dynamicGroupValue(oneBasedIndex: index, property: mapped)
    }

    private func runtimeExpression(_ token: ScriptToken) throws -> EffectExpression {
        _ = try expect(".", "\(token.text)后需要“.”", "\(token.text)の後に「.」が必要です"); let property = try identifier("运行时属性无效", "ランタイム入力が無効です")
        if token.text == "time" {
            if property.text == "elapsedMs" { return .elapsedMilliseconds };
            guard ["cycle", "beatPhase", "barPhase"].contains(property.text) else { throw error(property, "时间属性无效", "時間属性が無効です") };
            return try builtin(property)
        }
        let key = runtimeInputs["\(token.text).\(property.text)"]; guard let key else { throw error(property, "运行时属性无效", "ランタイム入力が無効です") };
        return .runtimeInput(key)
    }

    private func builtin(_ token: ScriptToken) throws -> EffectExpression {
        _ = try expect("(", "\(token.text)后需要“(”", "\(token.text)の後に「(」が必要です"); var arguments: [EffectExpression] = []
        if !check(")") { repeat { arguments.append(try expression()) } while match(",") };
        _ = try expect(")", "\(token.text)后需要“)”", "\(token.text)の後に「)」が必要です")
        if token.text == "hsv" {
            try require(arguments, [.number, .number, .number], token);
            return .colourFromHSV(hue: arguments[0], saturation: arguments[1], value: arguments[2])
        }
        guard let signature = builtinSignature(token.text, arguments) else {
            throw error(token, "未知函数\(token.text)", "未知の関数\(token.text)です")
        }; try require(arguments, signature.types, token)
        return .builtin(signature.function, arguments: arguments, type: signature.result, nodeID: sourceID(token))
    }

    private func functionArguments(_ token: ScriptToken) throws -> (EffectFunctionDefinition, [EffectExpression]) {
        try checkpoint()
        guard let function = functions[token.text] else { throw error(token, "找不到函数\(token.text)", "関数\(token.text)が見つかりません") };
        _ = try expect("(", "函数名后需要“(”", "関数名の後に「(」が必要です"); var args: [EffectExpression] = []
        if !check(")") { repeat { args.append(try expression()) } while match(",") }; _ = try expect(")", "函数参数后需要“)”", "関数引数の後に「)」が必要です")
        guard args.count == function.parameters.count else { throw error(token, "函数\(token.text)参数数量错误", "関数\(token.text)の引数数が正しくありません") }
        for (arg, parameter) in zip(args, function.parameters) { try requireType(arg, parameter.type) }
        return (function, args)
    }

    private func validateFunctionGraph() throws {
        try checkpoint()
        var graph: [String: Set<String>] = [:]
        for (name, function) in functions {
            var calls = Set<String>(); function.operations.forEach { collectCalls($0, into: &calls) };
            function.returnExpression.map { collectCalls($0, into: &calls) }; graph[name] = calls
        }
        var done = Set<String>()
        func visit(_ name: String, _ active: inout Set<String>) throws {
            if active.contains(name) { throw error(peek, "禁止递归调用函数\(name)", "関数\(name) の再帰呼び出しは禁止です") }; if done.contains(name) { return };
            active.insert(name); for child in graph[name] ?? [] { try visit(child, &active) }; active.remove(name); done.insert(name)
        }
        for name in functions.keys { try checkpoint(); var active = Set<String>(); try visit(name, &active) }
    }

    private func durationExpression() throws -> EffectExpression {
        var value = try typedExpression(.number);
        if match("s") { value = .arithmetic(.multiply, value, .number(1_000)) } else { _ = match("ms") };
        if case let .arithmetic(.multiply, .number(v), .number(1_000)) = value { return .number(v * 1_000) }; return value
    }
    private func numberArgument() throws -> EffectExpression {
        let value = try typedExpression(.number); _ = try expect(",", "参数之间需要逗号", "パラメータの間に「,」が必要です"); return value
    }
    private func arithmetic(_ op: ArithmeticOperator, _ left: EffectExpression, _ right: @autoclosure () throws -> EffectExpression) throws
        -> EffectExpression
    {
        let rhs = try right(); try requireType(left, .number); try requireType(rhs, .number);
        if (op == .divide || op == .modulo), case .number(0) = rhs { throw error(previous, "除数不能为0", "0で割ることはできません") };
        return .arithmetic(op, left, rhs)
    }
    private func typedExpression(_ type: EffectValueType) throws -> EffectExpression {
        let value = try expression(); try requireType(value, type); return value
    }
    private func typedExpression(_ type: EffectValueType, parse: () throws -> EffectExpression) throws -> EffectExpression {
        let value = try parse(); try requireType(value, type); return value
    }
    private func typed(_ parse: () throws -> EffectExpression, _ type: EffectValueType) throws -> EffectExpression {
        let value = try parse(); try requireType(value, type); return value
    }
    private func requiring(_ value: EffectExpression, _ type: EffectValueType) throws -> EffectExpression {
        try requireType(value, type); return value
    }
    private func requireType(_ value: EffectExpression, _ type: EffectValueType) throws {
        guard value.type == type else { throw error(previous, "表达式类型应为\(type.rawValue)", "式の型は\(type.rawValue)である必要があります") }
    }
    private func require(_ args: [EffectExpression], _ types: [EffectValueType], _ token: ScriptToken) throws {
        guard args.count == types.count else {
            throw error(token, "\(token.text)需要\(types.count)个参数", "\(token.text)には\(types.count)個の引数が必要です")
        }; for (arg, type) in zip(args, types) { try requireType(arg, type) }
    }

    private func parseType() throws -> EffectValueType {
        let token = try identifier("变量类型无效", "変数の型が無効です");
        let scalar: EffectValueType =
            token.text == "number"
            ? .number
            : ["bool", "boolean"].contains(token.text)
                ? .boolean : ["color", "colour"].contains(token.text) ? .colour : token.text == "target" ? .target : { _ in .number }(())
        guard ["number", "bool", "boolean", "color", "colour", "target"].contains(token.text) else {
            throw error(token, "类型必须是number、bool、color或target", "型はnumber、bool、color、targetのいずれかです")
        }; if match("[") { _ = try expect("]", "列表类型需要“]”", "リスト型には「]」が必要です"); return scalar.listType! }; return scalar
    }
    private func colour(_ token: ScriptToken) throws -> EffectColour {
        let clean = token.text.hasPrefix("#") ? String(token.text.dropFirst()) : token.text;
        guard clean.count == 6, let rgb = Int(clean, radix: 16) else { throw error(token, "颜色必须是#RRGGBB", "色は#RRGGBB形式で入力してください") };
        return EffectMath.rgbToHSV(red: (rgb >> 16) & 255, green: (rgb >> 8) & 255, blue: rgb & 255)
    }
    private func isTargetVariable(_ token: ScriptToken) -> Bool {
        token.kind == .identifier && variables[aliases[token.text] ?? token.text] == .target && tokens[safe: current + 1]?.text == "."
    }
    private func isDeclaredNonTarget(_ token: ScriptToken) -> Bool {
        token.kind == .identifier && aliases[token.text].flatMap { variables[$0] } != nil && variables[aliases[token.text]!] != .target
    }
    private var peek: ScriptToken { tokens[current] }; private var previous: ScriptToken { tokens[max(0, current - 1)] };
    private var isAtEnd: Bool { peek.kind == .eof }
    @discardableResult private func advance() -> ScriptToken { if !isAtEnd { current += 1 }; return previous }
    private func check(_ text: String) -> Bool { !isAtEnd && peek.text == text }
    private func match(_ texts: String...) -> Bool { guard texts.contains(where: check) else { return false }; _ = advance(); return true }
    private func expect(_ text: String, _ zh: String, _ ja: String) throws -> ScriptToken {
        guard check(text) else { throw error(peek, zh, ja) }; return advance()
    }
    private func identifier(_ zh: String, _ ja: String) throws -> ScriptToken {
        guard peek.kind == .identifier else { throw error(peek, zh, ja) }; return advance()
    }
    private func sourceID(_ start: ScriptToken) -> String { "script:\(start.start):\(previous.end):\(start.line):\(start.column)" }
    private func error(_ token: ScriptToken, _ zh: String, _ ja: String) -> EffectCompileError {
        .init(issues: [
            .init(
                code: "SCRIPT_SYNTAX", messageZh: "第\(token.line)行第\(token.column)列：\(zh)",
                messageJa: "\(token.line)行\(token.column)列：\(ja)",
                sourceID: "script:\(token.start):\(token.end):\(token.line):\(token.column)", sourceStart: token.start, sourceEnd: token.end
            )
        ])
    }
}

private let runtimeInputs: [String: RuntimeInputKey] = [
    "sensor.accelX": .sensorAccelX, "sensor.accelY": .sensorAccelY, "sensor.accelZ": .sensorAccelZ, "sensor.motion": .sensorMotion,
    "sensor.shake": .sensorShake,
    "sensor.gyroX": .sensorGyroX, "sensor.gyroY": .sensorGyroY, "sensor.gyroZ": .sensorGyroZ, "sensor.pitch": .sensorPitch,
    "sensor.roll": .sensorRoll,
    "sensor.yaw": .sensorYaw, "sensor.light": .sensorLight, "sensor.near": .sensorNear, "sensor.heading": .sensorHeading,
    "sensor.pressure": .sensorPressure,
    "audio.level": .audioLevel, "audio.peak": .audioPeak, "audio.bass": .audioBass, "audio.mid": .audioMid, "audio.treble": .audioTreble,
    "audio.beat": .audioBeat, "audio.bpm": .audioBPM,
]

private func builtinSignature(_ name: String, _ args: [EffectExpression]) -> (
    function: BuiltinFunction, types: [EffectValueType], result: EffectValueType
)? {
    let n = EffectValueType.number, b = EffectValueType.boolean, c = EffectValueType.colour
    let fixed: [String: (BuiltinFunction, [EffectValueType], EffectValueType)] = [
        "abs": (.absolute, [n], n), "min": (.minimum, [n, n], n), "max": (.maximum, [n, n], n), "clamp": (.clamp, [n, n, n], n),
        "round": (.round, [n], n), "floor": (.floor, [n], n), "ceil": (.ceil, [n], n), "sqrt": (.squareRoot, [n], n),
        "pow": (.power, [n, n], n), "log": (.logarithm, [n], n), "sin": (.sine, [n], n), "cos": (.cosine, [n], n),
        "radians": (.radians, [n], n), "degrees": (.degrees, [n], n), "map": (.map, [n, n, n, n, n], n), "lerp": (.lerp, [n, n, n], n),
        "smoothstep": (.smoothstep, [n, n, n], n), "smootherstep": (.smootherstep, [n, n, n], n), "easeIn": (.easeIn, [n], n),
        "easeOut": (.easeOut, [n], n), "easeInOut": (.easeInOut, [n], n), "sineWave": (.sineWave, [n, n], n),
        "triangleWave": (.triangleWave, [n, n], n), "sawWave": (.sawWave, [n, n], n), "squareWave": (.squareWave, [n, n, n], n),
        "random": (.random, [n, n], n), "randomColor": (.randomColour, [], c), "noise1D": (.noise1D, [n, n], n),
        "fbmNoise": (.fbmNoise, [n, n, n], n), "deadzone": (.deadzone, [n, n], n), "hysteresis": (.hysteresis, [n, n, n], b),
        "peakHold": (.peakHold, [n, n, n], n), "debounce": (.debounce, [b, n], b), "risingEdge": (.risingEdge, [b], b),
        "fallingEdge": (.fallingEdge, [b], b), "rgb": (.rgb, [n, n, n], c), "red": (.red, [c], n), "green": (.green, [c], n),
        "blue": (.blue, [c], n), "hue": (.hue, [c], n), "saturation": (.saturation, [c], n), "value": (.value, [c], n),
        "mixRgb": (.mixRGB, [c, c, n], c), "mixHsv": (.mixHSV, [c, c, n], c), "complement": (.complement, [c], c),
        "rotateHue": (.rotateHue, [c, n], c), "adjustSaturation": (.adjustSaturation, [c, n], c), "adjustValue": (.adjustValue, [c, n], c),
        "paletteColor": (.paletteColour, [.colourList, n], c), "cycle": (.cycle, [n], n), "beatPhase": (.beatPhase, [n], n),
        "barPhase": (.barPhase, [n, n, n], n), "chase": (.chase, [n], .numberList), "wavePattern": (.wavePattern, [n], .numberList),
    ]
    if name == "smooth" { return (.smooth, args.count == 2 ? [n, n] : [n, n, n], n) }
    let listFunctions: [String: (BuiltinFunction, Int)] = [
        "mirror": (.mirror, 1), "rotatePattern": (.rotatePattern, 2), "centerSpread": (.centerSpread, 1),
        "centerContract": (.centerContract, 1),
    ]
    if let (function, count) = listFunctions[name], args.count == count, let type = args.first?.type, type.elementType != nil {
        return (function, count == 1 ? [type] : [type, n], type)
    }
    return fixed[name]
}

private func collectCalls(_ expression: EffectExpression, into result: inout Set<String>) {
    switch expression {
    case let .functionCall(name, args, _, _): result.insert(name); args.forEach { collectCalls($0, into: &result) };
    case let .arithmetic(_, a, b), let .comparison(_, a, b), let .logic(_, a, b):
        collectCalls(a, into: &result); collectCalls(b, into: &result);
    case let .clamp(a, b, c), let .colourFromHSV(a, b, c):
        collectCalls(a, into: &result); collectCalls(b, into: &result); collectCalls(c, into: &result);
    case let .not(a), let .targetFromIndex(a): collectCalls(a, into: &result);
    case let .builtin(_, args, _, _), let .list(args, _): args.forEach { collectCalls($0, into: &result) };
    case let .listGet(a, b, _): collectCalls(a, into: &result); collectCalls(b, into: &result);
    case let .dynamicGroupValue(a, _): collectCalls(a, into: &result);
    default: break
    }
}
private func collectCalls(_ operation: EffectOperation, into result: inout Set<String>) {
    switch operation {
    case let .callFunction(name, args, _): result.insert(name); args.forEach { collectCalls($0, into: &result) };
    case let .ifElse(c, a, b, _): collectCalls(c, into: &result); (a + b).forEach { collectCalls($0, into: &result) };
    case let .repeatLoop(c, b, _): c.map { collectCalls($0, into: &result) }; b.forEach { collectCalls($0, into: &result) };
    case let .forLoop(_, a, b, c, d, _):
        collectCalls(a, into: &result); collectCalls(b, into: &result); collectCalls(c, into: &result);
        d.forEach { collectCalls($0, into: &result) };
    case let .whileLoop(c, b, _): collectCalls(c, into: &result); b.forEach { collectCalls($0, into: &result) };
    default: break
    }
}

private extension EffectValueType {
    var elementType: EffectValueType? {
        switch self {
        case .numberList: .number;
        case .booleanList: .boolean;
        case .colourList: .colour;
        case .targetList: .target;
        default: nil
        }
    }
    var listType: EffectValueType? {
        switch self {
        case .number: .numberList;
        case .boolean: .booleanList;
        case .colour: .colourList;
        case .target: .targetList;
        default: nil
        }
    }
}
private extension Collection { subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil } }
