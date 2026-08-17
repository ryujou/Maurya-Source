package com.example.peacock.feature.effects

import kotlin.math.roundToInt
import kotlin.math.max
import kotlin.math.min

object EffectScriptCompiler {
    const val MAX_SOURCE_BYTES = 256 * 1024

    fun compile(source: String): CompiledEffect {
        require(source.toByteArray().size <= MAX_SOURCE_BYTES) {
            "代码不能超过256 KiB / コードは256 KiB以下にしてください"
        }
        return Parser(source).parse()
    }

    fun template(name: String = "新灯效"): String = """
        effect "$name" {
            forever {
                all.mode(STROBE, 128);
                all.color("#FF2D55");
                wait(2s);
                all.color("#1677FF");
                wait(2s);
            }
        }
    """.trimIndent()

    private enum class Kind { IDENTIFIER, NUMBER, STRING, SYMBOL, EOF }

    private data class Token(
        val kind: Kind,
        val text: String,
        val start: Int,
        val end: Int,
        val line: Int,
        val column: Int,
    )

    private class Lexer(private val source: String) {
        private var index = 0
        private var line = 1
        private var column = 1

        fun scan(): List<Token> {
            val tokens = mutableListOf<Token>()
            while (index < source.length) {
                when {
                    source[index].isWhitespace() -> advanceWhitespace()
                    source.startsWith("//", index) -> skipLineComment()
                    source.startsWith("/*", index) -> skipBlockComment()
                    source[index].isLetter() || source[index] == '_' -> tokens += identifier()
                    source[index].isDigit() || source[index] == '.' &&
                        source.getOrNull(index + 1)?.isDigit() == true -> tokens += number()
                    source[index] == '"' -> tokens += string()
                    else -> tokens += symbol()
                }
            }
            tokens += Token(Kind.EOF, "", index, index, line, column)
            return tokens
        }

        private fun advanceWhitespace() {
            while (index < source.length && source[index].isWhitespace()) advance()
        }

        private fun skipLineComment() {
            while (index < source.length && source[index] != '\n') advance()
        }

        private fun skipBlockComment() {
            val startLine = line
            val startColumn = column
            advance()
            advance()
            while (index < source.length && !source.startsWith("*/", index)) advance()
            if (index >= source.length) {
                fail(startLine, startColumn, "块注释没有结束", "ブロックコメントが閉じられていません")
            }
            advance()
            advance()
        }

        private fun identifier(): Token {
            val start = index
            val tokenLine = line
            val tokenColumn = column
            while (index < source.length && (source[index].isLetterOrDigit() || source[index] == '_')) advance()
            return Token(Kind.IDENTIFIER, source.substring(start, index), start, index, tokenLine, tokenColumn)
        }

        private fun number(): Token {
            val start = index
            val tokenLine = line
            val tokenColumn = column
            var dot = false
            while (index < source.length) {
                val char = source[index]
                if (char == '.' && !dot) {
                    dot = true
                    advance()
                } else if (char.isDigit()) {
                    advance()
                } else break
            }
            return Token(Kind.NUMBER, source.substring(start, index), start, index, tokenLine, tokenColumn)
        }

        private fun string(): Token {
            val start = index
            val tokenLine = line
            val tokenColumn = column
            advance()
            val value = StringBuilder()
            while (index < source.length && source[index] != '"') {
                val char = source[index]
                if (char == '\\') {
                    advance()
                    if (index >= source.length) break
                    value.append(when (source[index]) {
                        'n' -> '\n'
                        't' -> '\t'
                        '"' -> '"'
                        '\\' -> '\\'
                        else -> source[index]
                    })
                    advance()
                } else {
                    value.append(char)
                    advance()
                }
            }
            if (index >= source.length) fail(tokenLine, tokenColumn, "字符串没有结束", "文字列が閉じられていません")
            advance()
            return Token(Kind.STRING, value.toString(), start, index, tokenLine, tokenColumn)
        }

        private fun symbol(): Token {
            val start = index
            val tokenLine = line
            val tokenColumn = column
            val pair = source.substring(index, (index + 2).coerceAtMost(source.length))
            val text = if (pair in setOf("==", "!=", "<=", ">=", "+=", "-=", "&&", "||")) {
                advance()
                advance()
                pair
            } else {
                source[index].toString().also { advance() }
            }
            return Token(Kind.SYMBOL, text, start, index, tokenLine, tokenColumn)
        }

        private fun advance() {
            if (source[index] == '\n') {
                line++
                column = 1
            } else {
                column++
            }
            index++
        }

        private fun fail(line: Int, column: Int, zh: String, ja: String): Nothing {
            val issue = EffectCompileIssue(
                code = "SCRIPT_SYNTAX",
                messageZh = "第${line}行第${column}列：$zh",
                messageJa = "${line}行${column}列：$ja",
            )
            throw EffectCompileException(listOf(issue.combinedMessage), listOf(issue))
        }
    }

    private class Parser(private val source: String) {
        private val tokens = Lexer(source).scan()
        private var current = 0
        private var nodes = 0
        private var loopDepth = 0
        private val variables = linkedMapOf<String, EffectValueType>()
        private val aliases = linkedMapOf<String, String>()
        private val functions = linkedMapOf<String, EffectFunctionDefinition>()
        private var currentFunction: String? = null

        fun parse(): CompiledEffect {
            while (match("fn")) functionDefinition(previous())
            expect("effect", "需要以 effect 开始", "effect で開始してください")
            if (peek().kind == Kind.STRING) advance()
            aliases.clear()
            val operations = block()
            if (!isAtEnd()) error(peek(), "程序结束后存在多余内容", "プログラム末尾に不要な内容があります")
            if (operations.isEmpty()) error(previous(), "程序不能为空", "プログラムを空にはできません")
            validateFunctionGraph()
            return EffectCompiler.compileOperations(operations, nodes, variables, functions)
        }

        private fun functionDefinition(start: Token) {
            if (functions.size >= 16) error(start, "自定义函数不能超过16个", "カスタム関数は16個までです")
            val name = expectIdentifier("函数名无效", "関数名が無効です").text
            if (functions.containsKey(name)) error(previous(), "函数$name 已存在", "関数$name は既に存在します")
            expect("(", "函数名后需要“(”", "関数名の後に「(」が必要です")
            val parameters = mutableListOf<EffectFunctionParameter>()
            val savedAliases = aliases.toMap()
            aliases.clear()
            currentFunction = name
            if (!check(")")) {
                do {
                    if (parameters.size >= 8) error(peek(), "函数参数不能超过8个", "関数引数は8個までです")
                    val type = parseType()
                    val sourceName = expectIdentifier("参数名无效", "引数名が無効です").text
                    if (aliases.containsKey(sourceName)) error(previous(), "参数名重复", "引数名が重複しています")
                    val variableId = "fn:$name:param:$sourceName"
                    aliases[sourceName] = variableId
                    variables[variableId] = type
                    parameters += EffectFunctionParameter(sourceName, variableId, type)
                } while (match(","))
            }
            expect(")", "函数参数后需要“)”", "関数引数の後に「)」が必要です")
            val returnType = if (match(":")) parseType() else null
            functions[name] = EffectFunctionDefinition(name, parameters, returnType, emptyList())

            expect("{", "函数体需要“{”", "関数本体には「{」が必要です")
            val operations = mutableListOf<EffectOp>()
            var returnExpression: EffectExpression? = null
            while (!check("}") && !isAtEnd()) {
                if (match("return")) {
                    if (returnType == null) {
                        expect(";", "return后需要分号", "returnの後に「;」が必要です")
                    } else {
                        val value = expression()
                        if (value.type != returnType) error(previous(), "函数返回值类型错误", "関数の戻り値型が一致しません")
                        returnExpression = value
                        expect(";", "return后需要分号", "returnの後に「;」が必要です")
                    }
                    if (!check("}")) error(peek(), "return必须是函数最后一条语句", "returnは関数の最後に置いてください")
                } else {
                    operations += statement()
                }
            }
            expect("}", "函数体需要“}”", "関数本体には「}」が必要です")
            if (returnType != null && returnExpression == null) {
                error(start, "有返回值函数必须return", "戻り値関数にはreturnが必要です")
            }
            if (returnType != null && operations.any {
                    it !is EffectOp.SetVariable && it !is EffectOp.ChangeVariable && it !is EffectOp.SetListItem
                }
            ) {
                error(start, "有返回值函数只能包含局部计算", "戻り値関数にはローカル計算だけを記述できます")
            }
            val locals = aliases.values.toSet()
            functions[name] = EffectFunctionDefinition(
                name, parameters, returnType, operations, returnExpression, locals,
            )
            aliases.clear()
            aliases.putAll(savedAliases)
            currentFunction = null
        }

        private fun block(): List<EffectOp> {
            expect("{", "需要“{”", "「{」が必要です")
            val result = mutableListOf<EffectOp>()
            while (!check("}") && !isAtEnd()) result += statement()
            expect("}", "需要“}”", "「}」が必要です")
            return result
        }

        private fun statement(): EffectOp {
            val start = peek()
            nodes++
            if (nodes > 300) error(start, "程序步骤不能超过300", "プログラムは300ステップまでです")
            return when {
                match("let") -> variableDeclaration(start)
                match("if") -> ifStatement(start)
                match("repeat") -> repeatStatement(start)
                match("forever") -> loopStatement(start, null)
                match("for") -> forStatement(start)
                match("while") -> whileStatement(start)
                match("break") -> {
                    if (loopDepth == 0) error(start, "break只能用于循环内部", "breakはループ内だけで使用できます")
                    expect(";", "break后需要分号", "breakの後に「;」が必要です")
                    EffectOp.Break(sourceId(start))
                }
                match("continue") -> {
                    if (loopDepth == 0) error(start, "continue只能用于循环内部", "continueはループ内だけで使用できます")
                    expect(";", "continue后需要分号", "continueの後に「;」が必要です")
                    EffectOp.Continue(sourceId(start))
                }
                match("end") -> {
                    expect(";", "end后需要分号", "endの後に「;」が必要です")
                    EffectOp.End(sourceId(start))
                }
                match("wait") -> waitStatement(start)
                match("seedRandom") -> seedRandomStatement(start)
                isDeclaredNonTargetVariable(peek()) -> assignment(start)
                check("all") || check("allPixels") || check("group") ||
                    check("pixel") || check("pixelAt") || isTargetVariable(peek()) ->
                    lightStatement(start)
                peek().kind == Kind.IDENTIFIER && functions.containsKey(peek().text) &&
                    tokens.getOrNull(current + 1)?.text == "(" -> functionCallStatement(start)
                peek().kind == Kind.IDENTIFIER -> assignment(start)
                else -> error(peek(), "无法识别的语句“${peek().text}”", "認識できない文「${peek().text}」です")
            }
        }

        private fun variableDeclaration(start: Token): EffectOp {
            val sourceName = expectIdentifier("变量名无效", "変数名が無効です").text
            if (aliases.containsKey(sourceName)) error(previous(), "变量${sourceName}已经存在", "変数${sourceName}は既に存在します")
            val declaredType = if (match(":")) parseType() else null
            expect("=", "变量初始值前需要“=”", "初期値の前に「=」が必要です")
            var value = expression()
            if (declaredType in setOf(
                    EffectValueType.NUMBER_LIST,
                    EffectValueType.BOOLEAN_LIST,
                    EffectValueType.COLOUR_LIST,
                    EffectValueType.TARGET_LIST,
                ) &&
                value is EffectExpression.ListLiteral && value.elements.isEmpty()
            ) {
                value = value.copy(type = declaredType!!)
            }
            val type = declaredType ?: value.type
            if (type != value.type) error(previous(), "变量初始值类型不匹配", "変数の初期値の型が一致しません")
            val name = currentFunction?.let { "fn:$it:local:$sourceName" } ?: sourceName
            aliases[sourceName] = name
            variables[name] = type
            expect(";", "变量声明后需要分号", "変数宣言の後に「;」が必要です")
            return EffectOp.SetVariable(name, value, sourceId(start))
        }

        private fun assignment(start: Token): EffectOp {
            val sourceName = advance().text
            val name = aliases[sourceName] ?: sourceName
            val type = variables[name] ?: error(start, "找不到变量$sourceName", "変数${sourceName}が見つかりません")
            if (match("[")) {
                val elementType = elementType(type)
                    ?: error(start, "只有列表支持索引赋值", "インデックス代入にはリストが必要です")
                val index = expectType(expression(), EffectValueType.NUMBER)
                expect("]", "列表索引后需要“]”", "リストの添字の後に「]」が必要です")
                expect("=", "列表元素后需要“=”", "リスト要素の後に「=」が必要です")
                val value = expectType(expression(), elementType)
                expect(";", "赋值后需要分号", "代入の後に「;」が必要です")
                return EffectOp.SetListItem(name, index, value, sourceId(start))
            }
            return when {
                match("=") -> {
                    val value = expression()
                    if (value.type != type) error(previous(), "赋值类型不匹配", "代入する型が一致しません")
                    expect(";", "赋值后需要分号", "代入の後に「;」が必要です")
                    EffectOp.SetVariable(name, value, sourceId(start))
                }
                match("+=") -> {
                    if (type != EffectValueType.NUMBER) error(start, "只有数值变量支持+=", "数値変数だけが+=を使用できます")
                    val value = expectType(expression(), EffectValueType.NUMBER)
                    expect(";", "赋值后需要分号", "代入の後に「;」が必要です")
                    EffectOp.ChangeVariable(name, value, sourceId(start))
                }
                match("-=") -> {
                    if (type != EffectValueType.NUMBER) error(start, "只有数值变量支持-=", "数値変数だけが-=を使用できます")
                    val value = expectType(expression(), EffectValueType.NUMBER)
                    expect(";", "赋值后需要分号", "代入の後に「;」が必要です")
                    EffectOp.ChangeVariable(
                        name,
                        EffectExpression.Arithmetic(
                            ArithmeticOperator.SUBTRACT,
                            EffectExpression.NumberLiteral(0.0),
                            value,
                        ),
                        sourceId(start),
                    )
                }
                else -> error(peek(), "变量后需要=、+=或-=", "変数の後に=、+=、-=が必要です")
            }
        }

        private fun ifStatement(start: Token): EffectOp {
            expect("(", "if后需要“(”", "ifの後に「(」が必要です")
            val condition = expectType(expression(), EffectValueType.BOOLEAN)
            expect(")", "if条件后需要“)”", "if条件の後に「)」が必要です")
            val thenBody = block()
            val elseBody = if (match("else")) block() else emptyList()
            return EffectOp.If(condition, thenBody, elseBody, sourceId(start))
        }

        private fun repeatStatement(start: Token): EffectOp {
            expect("(", "repeat后需要“(”", "repeatの後に「(」が必要です")
            val count = expectType(expression(), EffectValueType.NUMBER)
            expect(")", "repeat次数后需要“)”", "repeat回数の後に「)」が必要です")
            return loopStatement(start, count)
        }

        private fun loopStatement(start: Token, count: EffectExpression?): EffectOp {
            loopDepth++
            val body = block()
            loopDepth--
            if (body.isEmpty()) error(start, "循环不能为空", "ループを空にはできません")
            return EffectOp.Repeat(count, body, sourceId(start))
        }

        private fun forStatement(start: Token): EffectOp {
            expect("(", "for后需要“(”", "forの後に「(」が必要です")
            val cStyle = match("let")
            val sourceName = expectIdentifier("for变量名无效", "for変数名が無効です").text
            val existingId = aliases[sourceName]
            val existing = existingId?.let(variables::get)
            if (existing != null && existing != EffectValueType.NUMBER) {
                error(previous(), "for变量必须是数值", "for変数は数値である必要があります")
            }
            val name = existingId ?: currentFunction?.let { "fn:$it:local:$sourceName" } ?: sourceName
            aliases[sourceName] = name
            variables.putIfAbsent(name, EffectValueType.NUMBER)
            val from: EffectExpression
            val to: EffectExpression
            val step: EffectExpression
            if (cStyle) {
                expect("=", "for变量后需要=", "for変数の後に「=」が必要です")
                from = expectType(expression(), EffectValueType.NUMBER)
                expect(";", "for初始值后需要分号", "for初期値の後に「;」が必要です")
                val conditionName = expectIdentifier("for条件变量无效", "for条件変数が無効です").text
                if (conditionName != sourceName) {
                    error(previous(), "for条件必须使用同一变量", "for条件には同じ変数を使用してください")
                }
                val comparison = when {
                    match("<") -> "<"
                    match("<=") -> "<="
                    match(">") -> ">"
                    match(">=") -> ">="
                    else -> error(peek(), "for条件需要<、<=、>或>=", "for条件には<、<=、>、>=が必要です")
                }
                val boundary = expectType(expression(), EffectValueType.NUMBER)
                expect(";", "for条件后需要分号", "for条件の後に「;」が必要です")
                val incrementName = expectIdentifier("for增量变量无效", "for増分変数が無効です").text
                if (incrementName != sourceName) {
                    error(previous(), "for增量必须使用同一变量", "for増分には同じ変数を使用してください")
                }
                val decreasing = when {
                    match("+=") -> false
                    match("-=") -> true
                    else -> error(peek(), "for增量需要+=或-=", "for増分には+=または-=が必要です")
                }
                val magnitude = expectType(expression(), EffectValueType.NUMBER)
                step = if (decreasing) {
                    EffectExpression.Arithmetic(
                        ArithmeticOperator.MULTIPLY,
                        magnitude,
                        EffectExpression.NumberLiteral(-1.0),
                    )
                } else {
                    magnitude
                }
                to = when (comparison) {
                    "<" -> EffectExpression.Arithmetic(
                        ArithmeticOperator.SUBTRACT,
                        boundary,
                        EffectExpression.NumberLiteral(1.0),
                    )
                    ">" -> EffectExpression.Arithmetic(
                        ArithmeticOperator.ADD,
                        boundary,
                        EffectExpression.NumberLiteral(1.0),
                    )
                    else -> boundary
                }
            } else {
                expect("from", "for变量后需要from", "for変数の後にfromが必要です")
                from = expectType(expression(), EffectValueType.NUMBER)
                expect("to", "for起点后需要to", "for開始値の後にtoが必要です")
                to = expectType(expression(), EffectValueType.NUMBER)
                expect("step", "for终点后需要step", "for終了値の後にstepが必要です")
                step = expectType(expression(), EffectValueType.NUMBER)
            }
            if ((step as? EffectExpression.NumberLiteral)?.value == 0.0) {
                error(previous(), "for步长不能为0", "forの増分は0にできません")
            }
            expect(")", "for参数后需要“)”", "forパラメータの後に「)」が必要です")
            loopDepth++
            val body = block()
            loopDepth--
            return EffectOp.For(name, from, to, step, body, sourceId(start))
        }

        private fun whileStatement(start: Token): EffectOp {
            expect("(", "while后需要“(”", "whileの後に「(」が必要です")
            val condition = expectType(expression(), EffectValueType.BOOLEAN)
            expect(")", "while条件后需要“)”", "while条件の後に「)」が必要です")
            loopDepth++
            val body = block()
            loopDepth--
            return EffectOp.While(condition, body, sourceId(start))
        }

        private fun waitStatement(start: Token): EffectOp {
            expect("(", "wait后需要“(”", "waitの後に「(」が必要です")
            val duration = durationExpression()
            expect(")", "wait时间后需要“)”", "wait時間の後に「)」が必要です")
            expect(";", "wait后需要分号", "waitの後に「;」が必要です")
            return EffectOp.Wait(duration, sourceId(start))
        }

        private fun seedRandomStatement(start: Token): EffectOp {
            expect("(", "seedRandom后需要“(”", "seedRandomの後に「(」が必要です")
            val seed = expectType(expression(), EffectValueType.NUMBER)
            expect(")", "随机种子后需要“)”", "乱数シードの後に「)」が必要です")
            expect(";", "seedRandom后需要分号", "seedRandomの後に「;」が必要です")
            return EffectOp.SeedRandom(seed, sourceId(start))
        }

        private fun lightStatement(start: Token): EffectOp {
            val target = target()
            expect(".", "灯组后需要“.”", "対象の後に「.」が必要です")
            val action = expectIdentifier("灯光操作无效", "ライト操作が無効です").text
            expect("(", "灯光操作后需要“(”", "ライト操作の後に「(」が必要です")
            val operation = when (action) {
                "color" -> EffectOp.SetColour(target, expectType(expression(), EffectValueType.COLOUR))
                "hsv" -> EffectOp.SetHsv(
                    target,
                    expectNumberArgument(),
                    expectNumberArgument(),
                    expectType(expression(), EffectValueType.NUMBER),
                )
                "adjustHsv" -> EffectOp.AdjustHsv(
                    target,
                    expectNumberArgument(),
                    expectNumberArgument(),
                    expectType(expression(), EffectValueType.NUMBER),
                )
                "fade" -> {
                    val colour = expectType(expression(), EffectValueType.COLOUR)
                    expect(",", "fade颜色后需要逗号", "fadeの色の後に「,」が必要です")
                    EffectOp.FadeColour(target, colour, durationExpression())
                }
                "mode" -> {
                    val mode = expectType(expression(), EffectValueType.NUMBER)
                    expect(",", "mode后需要参数", "modeの後にパラメータが必要です")
                    EffectOp.SetMode(target, mode, expectType(expression(), EffectValueType.NUMBER))
                }
                else -> error(previous(), "不支持的灯光操作$action", "未対応のライト操作${action}です")
            }
            expect(")", "灯光操作后需要“)”", "ライト操作の後に「)」が必要です")
            expect(";", "灯光操作后需要分号", "ライト操作の後に「;」が必要です")
            val id = sourceId(start)
            return when (operation) {
                is EffectOp.SetColour -> operation.copy(blockId = id)
                is EffectOp.SetHsv -> operation.copy(blockId = id)
                is EffectOp.AdjustHsv -> operation.copy(blockId = id)
                is EffectOp.FadeColour -> operation.copy(blockId = id)
                is EffectOp.SetMode -> operation.copy(blockId = id)
                else -> operation
            }
        }

        private fun expectNumberArgument(): EffectExpression {
            val value = expectType(expression(), EffectValueType.NUMBER)
            expect(",", "参数之间需要逗号", "パラメータの間に「,」が必要です")
            return value
        }

        private fun target(): EffectTargetRef {
            if (match("all")) return EffectTargetRef.All
            if (match("allPixels")) return EffectTargetRef.AllPixels
            if (peek().kind == Kind.IDENTIFIER && isTargetVariable(peek())) {
                val sourceName = advance().text
                val id = aliases[sourceName] ?: sourceName
                return EffectTargetRef.Value(EffectExpression.Variable(id, EffectValueType.TARGET))
            }
            if (match("pixel")) {
                expect("(", "pixel后需要“(”", "pixelの後に「(」が必要です")
                val group = expectType(expression(), EffectValueType.NUMBER)
                expect(",", "pixel灯组后需要逗号", "pixelのグループ後に「,」が必要です")
                val pixel = expectType(expression(), EffectValueType.NUMBER)
                expect(")", "pixel后需要“)”", "pixelの後に「)」が必要です")
                return EffectTargetRef.Pixel(group, pixel)
            }
            if (match("pixelAt")) {
                expect("(", "pixelAt后需要“(”", "pixelAtの後に「(」が必要です")
                val index = expectType(expression(), EffectValueType.NUMBER)
                expect(")", "pixelAt后需要“)”", "pixelAtの後に「)」が必要です")
                return EffectTargetRef.PixelAt(index)
            }
            expect("group", "目标必须是all、group、pixel或pixelAt", "対象はall、group、pixel、pixelAtです")
            expect("(", "group后需要“(”", "groupの後に「(」が必要です")
            val index = expectType(expression(), EffectValueType.NUMBER)
            expect(")", "灯组编号后需要“)”", "グループ番号の後に「)」が必要です")
            (index as? EffectExpression.NumberLiteral)?.value?.roundToInt()?.let {
                if (it !in 1..7) error(numberToken = it)
            }
            return EffectTargetRef.Group(index)
        }

        private fun isTargetVariable(token: Token): Boolean {
            if (token.kind != Kind.IDENTIFIER) return false
            val id = aliases[token.text] ?: token.text
            return variables[id] == EffectValueType.TARGET &&
                tokens.getOrNull(current + 1)?.text == "."
        }

        private fun isDeclaredNonTargetVariable(token: Token): Boolean {
            if (token.kind != Kind.IDENTIFIER) return false
            val id = aliases[token.text] ?: return false
            return variables[id] != EffectValueType.TARGET
        }

        private fun functionCallStatement(start: Token): EffectOp {
            val token = advance()
            val (function, arguments) = parseFunctionArguments(token)
            if (function.returnType != null) {
                error(token, "有返回值函数不能作为独立语句", "戻り値関数は単独文にできません")
            }
            expect(";", "函数调用后需要分号", "関数呼び出しの後に「;」が必要です")
            return EffectOp.CallFunction(function.name, arguments, sourceId(start))
        }

        private fun error(numberToken: Int): Nothing = error(
            previous(),
            "灯组编号必须为1到7，当前为$numberToken",
            "グループ番号は1から7です（現在：$numberToken）",
        )

        private fun durationExpression(): EffectExpression {
            var value = expectType(expression(), EffectValueType.NUMBER)
            value = when {
                match("s") -> (value as? EffectExpression.NumberLiteral)
                    ?.let { EffectExpression.NumberLiteral(it.value * 1_000.0) }
                    ?: EffectExpression.Arithmetic(
                        ArithmeticOperator.MULTIPLY,
                        value,
                        EffectExpression.NumberLiteral(1_000.0),
                    )
                match("ms") -> value
                else -> value
            }
            return value
        }

        private fun expression(): EffectExpression = or()

        private fun or(): EffectExpression {
            var expression = and()
            while (match("||")) expression = logic(LogicOperator.OR, expression, and())
            return expression
        }

        private fun and(): EffectExpression {
            var expression = equality()
            while (match("&&")) expression = logic(LogicOperator.AND, expression, equality())
            return expression
        }

        private fun equality(): EffectExpression {
            var expression = comparison()
            while (match("==", "!=")) {
                val operator = if (previous().text == "==") ComparisonOperator.EQ else ComparisonOperator.NEQ
                val right = comparison()
                if (expression.type != right.type) error(previous(), "比较类型不一致", "比較する型が一致しません")
                expression = EffectExpression.Comparison(operator, expression, right)
            }
            return expression
        }

        private fun comparison(): EffectExpression {
            var expression = term()
            while (match("<", "<=", ">", ">=")) {
                val token = previous()
                val right = term()
                expectType(expression, EffectValueType.NUMBER)
                expectType(right, EffectValueType.NUMBER)
                val operator = when (token.text) {
                    "<" -> ComparisonOperator.LT
                    "<=" -> ComparisonOperator.LTE
                    ">" -> ComparisonOperator.GT
                    else -> ComparisonOperator.GTE
                }
                expression = EffectExpression.Comparison(operator, expression, right)
            }
            return expression
        }

        private fun term(): EffectExpression {
            var expression = factor()
            while (match("+", "-")) {
                val operator = if (previous().text == "+") ArithmeticOperator.ADD else ArithmeticOperator.SUBTRACT
                expression = arithmetic(operator, expression, factor())
            }
            return expression
        }

        private fun factor(): EffectExpression {
            var expression = unary()
            while (match("*", "/", "%")) {
                val operator = when (previous().text) {
                    "*" -> ArithmeticOperator.MULTIPLY
                    "/" -> ArithmeticOperator.DIVIDE
                    else -> ArithmeticOperator.MODULO
                }
                expression = arithmetic(operator, expression, unary())
            }
            return expression
        }

        private fun unary(): EffectExpression = when {
            match("!") -> EffectExpression.Not(expectType(unary(), EffectValueType.BOOLEAN))
            match("-") -> EffectExpression.Arithmetic(
                ArithmeticOperator.SUBTRACT,
                EffectExpression.NumberLiteral(0.0),
                expectType(unary(), EffectValueType.NUMBER),
            )
            else -> primary()
        }

        private fun primary(): EffectExpression {
            nodes++
            val token = advance()
            var result = when {
                token.kind == Kind.NUMBER -> {
                    var number = token.text.toDoubleOrNull()
                        ?: error(token, "数字无效", "数値が無効です")
                    if (match("s")) number *= 1_000.0 else match("ms")
                    EffectExpression.NumberLiteral(number)
                }
                token.kind == Kind.STRING -> colour(token)
                token.text == "true" -> EffectExpression.BooleanLiteral(true)
                token.text == "false" -> EffectExpression.BooleanLiteral(false)
                token.text == "STEADY" -> EffectExpression.NumberLiteral(1.0)
                token.text == "STROBE" -> EffectExpression.NumberLiteral(3.0)
                token.text == "elapsedMs" -> EffectExpression.ElapsedMs
                token.kind == Kind.IDENTIFIER && aliases.containsKey(token.text) -> {
                    val id = aliases.getValue(token.text)
                    val type = variables[id]
                        ?: error(token, "找不到变量${token.text}", "変数${token.text}が見つかりません")
                    EffectExpression.Variable(id, type)
                }
                token.text == "all" -> EffectExpression.TargetLiteral(EffectTarget.ALL)
                token.text == "[" -> listLiteral(token)
                token.text == "(" -> expression().also {
                    expect(")", "表达式后需要“)”", "式の後に「)」が必要です")
                }
                token.text == "group" -> groupExpression(token)
                token.text == "sensor" || token.text == "audio" || token.text == "time" ->
                    runtimeExpression(token)
                token.kind == Kind.IDENTIFIER && functions.containsKey(token.text) && check("(") -> {
                    val (function, arguments) = parseFunctionArguments(token)
                    val returnType = function.returnType
                        ?: error(token, "流程函数不能用于表达式", "手続き関数は式に使用できません")
                    EffectExpression.FunctionCall(
                        function.name, arguments, returnType, sourceId(token),
                    )
                }
                token.kind == Kind.IDENTIFIER && check("(") -> builtinFunction(token)
                token.kind == Kind.IDENTIFIER -> {
                    val id = aliases[token.text] ?: token.text
                    val type = variables[id]
                        ?: error(token, "找不到变量${token.text}", "変数${token.text}が見つかりません")
                    EffectExpression.Variable(id, type)
                }
                else -> error(token, "表达式无效", "式が無効です")
            }
            while (true) {
                result = when {
                    match("[") -> {
                        val element = elementType(result.type)
                            ?: error(previous(), "只有列表支持索引读取", "インデックス参照にはリストが必要です")
                        val index = expectType(expression(), EffectValueType.NUMBER)
                        expect("]", "列表索引后需要“]”", "リストの添字の後に「]」が必要です")
                        EffectExpression.ListGet(result, index, element)
                    }
                    match(".") -> {
                        val property = expectIdentifier("列表属性无效", "リストのプロパティが無効です")
                        if (property.text != "length" || elementType(result.type) == null) {
                            error(property, "只支持列表.length", "リストの.lengthだけを使用できます")
                        }
                        EffectExpression.Builtin(
                            BuiltinFunction.LIST_LENGTH,
                            listOf(result),
                            EffectValueType.NUMBER,
                            sourceId(property),
                        )
                    }
                    else -> return result
                }
            }
        }

        private fun listLiteral(token: Token): EffectExpression {
            if (match("]")) return EffectExpression.ListLiteral(emptyList(), EffectValueType.NUMBER_LIST)
            val elements = mutableListOf<EffectExpression>()
            do {
                if (elements.size >= EffectGeometry.PIXEL_COUNT) {
                    error(token, "列表不能超过42项", "リストは42項目までです")
                }
                elements += expression()
            } while (match(","))
            expect("]", "列表需要“]”", "リストには「]」が必要です")
            val element = elements.first().type
            if (elementType(element) != null || elements.any { it.type != element }) {
                error(token, "列表必须是同一基础类型且不能嵌套", "リストは同じ基本型で、ネストできません")
            }
            return EffectExpression.ListLiteral(elements, listType(element))
        }

        private fun groupExpression(token: Token): EffectExpression {
            expect("(", "group后需要“(”", "groupの後に「(」が必要です")
            val index = expectType(expression(), EffectValueType.NUMBER)
            expect(")", "灯组编号后需要“)”", "グループ番号の後に「)」が必要です")
            (index as? EffectExpression.NumberLiteral)?.value?.roundToInt()?.let {
                if (it !in 1..7) error(token, "灯组编号必须为1到7", "グループ番号は1から7です")
            }
            if (!match(".")) return EffectExpression.TargetFromIndex(index)
            val property = when (expectIdentifier("状态属性无效", "状態プロパティが無効です").text) {
                "hue" -> EffectGroupProperty.HUE
                "saturation" -> EffectGroupProperty.SATURATION
                "value" -> EffectGroupProperty.VALUE
                "mode" -> EffectGroupProperty.MODE
                else -> error(previous(), "状态属性无效", "状態プロパティが無効です")
            }
            return EffectExpression.DynamicGroupValue(index, property)
        }

        private fun runtimeExpression(token: Token): EffectExpression {
            expect(".", "${token.text}后需要“.”", "${token.text}の後に「.」が必要です")
            val property = expectIdentifier("运行时属性无效", "ランタイム入力が無効です")
            if (token.text == "time") {
                return when (property.text) {
                    "elapsedMs" -> EffectExpression.ElapsedMs
                    "cycle", "beatPhase", "barPhase" -> builtinFunction(property)
                    else -> error(property, "时间属性无效", "時間プロパティが無効です")
                }
            }
            val prefix = if (token.text == "sensor") "SENSOR_" else "AUDIO_"
            val suffix = when (property.text) {
                "accelX" -> "ACCEL_X"
                "accelY" -> "ACCEL_Y"
                "accelZ" -> "ACCEL_Z"
                "motion" -> "MOTION"
                "shake" -> "SHAKE"
                "gyroX" -> "GYRO_X"
                "gyroY" -> "GYRO_Y"
                "gyroZ" -> "GYRO_Z"
                "pitch" -> "PITCH"
                "roll" -> "ROLL"
                "yaw" -> "YAW"
                "light" -> "LIGHT"
                "near" -> "NEAR"
                "heading" -> "HEADING"
                "pressure" -> "PRESSURE"
                "level" -> "LEVEL"
                "peak" -> "PEAK"
                "bass" -> "BASS"
                "mid" -> "MID"
                "treble" -> "TREBLE"
                "beat" -> "BEAT"
                "bpm" -> "BPM"
                else -> error(property, "运行时属性无效", "ランタイム入力が無効です")
            }
            val key = runCatching { RuntimeInputKey.valueOf(prefix + suffix) }
                .getOrElse { error(property, "该输入不属于${token.text}", "${token.text}では使用できない入力です") }
            return EffectExpression.RuntimeInput(key)
        }

        private fun builtinFunction(token: Token): EffectExpression {
            expect("(", "${token.text}后需要“(”", "${token.text}の後に「(」が必要です")
            val args = mutableListOf<EffectExpression>()
            if (!check(")")) {
                do args += expression() while (match(","))
            }
            expect(")", "${token.text}后需要“)”", "${token.text}の後に「)」が必要です")
            if (token.text == "hsv") {
                requireArguments(token, args, listOf(
                    EffectValueType.NUMBER, EffectValueType.NUMBER, EffectValueType.NUMBER,
                ))
                return EffectExpression.ColourFromHsv(args[0], args[1], args[2])
            }
            val (function, argumentTypes, returnType) = builtinSignature(token, args)
            requireArguments(token, args, argumentTypes)
            return EffectExpression.Builtin(function, args, returnType, sourceId(token))
        }

        private fun parseFunctionArguments(
            token: Token,
        ): Pair<EffectFunctionDefinition, List<EffectExpression>> {
            val function = functions[token.text]
                ?: error(token, "找不到函数${token.text}", "関数${token.text}が見つかりません")
            expect("(", "函数名后需要“(”", "関数名の後に「(」が必要です")
            val arguments = mutableListOf<EffectExpression>()
            if (!check(")")) {
                do arguments += expression() while (match(","))
            }
            expect(")", "函数参数后需要“)”", "関数引数の後に「)」が必要です")
            if (arguments.size != function.parameters.size) {
                error(token, "函数${token.text}参数数量错误", "関数${token.text}の引数数が正しくありません")
            }
            arguments.zip(function.parameters).forEach { (argument, parameter) ->
                if (argument.type != parameter.type) {
                    error(token, "函数${token.text}参数${parameter.name}类型错误", "関数${token.text}の引数${parameter.name}の型が違います")
                }
            }
            return function to arguments
        }

        private fun validateFunctionGraph() {
            val graph = functions.mapValues { (_, function) ->
                buildSet {
                    fun expression(value: EffectExpression) {
                        when (value) {
                            is EffectExpression.FunctionCall -> {
                                add(value.name)
                                value.arguments.forEach(::expression)
                            }
                            is EffectExpression.Arithmetic -> { expression(value.left); expression(value.right) }
                            is EffectExpression.Clamp -> { expression(value.value); expression(value.low); expression(value.high) }
                            is EffectExpression.Comparison -> { expression(value.left); expression(value.right) }
                            is EffectExpression.Logic -> { expression(value.left); expression(value.right) }
                            is EffectExpression.Not -> expression(value.value)
                            is EffectExpression.ColourFromHsv -> {
                                expression(value.hue); expression(value.saturation); expression(value.value)
                            }
                            is EffectExpression.DynamicGroupValue -> expression(value.oneBasedIndex)
                            is EffectExpression.TargetFromIndex -> expression(value.oneBasedIndex)
                            is EffectExpression.Builtin -> value.arguments.forEach(::expression)
                            is EffectExpression.ListLiteral -> value.elements.forEach(::expression)
                            is EffectExpression.ListGet -> { expression(value.list); expression(value.index) }
                            else -> Unit
                        }
                    }
                    fun operations(items: List<EffectOp>) {
                        items.forEach { operation ->
                            when (operation) {
                                is EffectOp.CallFunction -> {
                                    add(operation.name)
                                    operation.arguments.forEach(::expression)
                                }
                                is EffectOp.If -> { expression(operation.condition); operations(operation.thenBody); operations(operation.elseBody) }
                                is EffectOp.Repeat -> { operation.count?.let(::expression); operations(operation.body) }
                                is EffectOp.For -> {
                                    expression(operation.from); expression(operation.to); expression(operation.step); operations(operation.body)
                                }
                                is EffectOp.While -> { expression(operation.condition); operations(operation.body) }
                                else -> Unit
                            }
                        }
                    }
                    operations(function.operations)
                    function.returnExpression?.let(::expression)
                }
            }
            fun visit(name: String, active: MutableSet<String>, done: MutableSet<String>) {
                if (name in active) error(peek(), "禁止递归调用函数$name", "関数$name の再帰呼び出しは禁止です")
                if (!done.add(name)) return
                active += name
                graph[name].orEmpty().forEach { visit(it, active, done) }
                active -= name
            }
            val done = mutableSetOf<String>()
            functions.keys.forEach { visit(it, mutableSetOf(), done) }
        }

        private fun builtinSignature(
            token: Token,
            args: List<EffectExpression>,
        ): Triple<BuiltinFunction, List<EffectValueType>, EffectValueType> {
            val n = EffectValueType.NUMBER
            val b = EffectValueType.BOOLEAN
            val c = EffectValueType.COLOUR
            fun spec(fn: BuiltinFunction, types: List<EffectValueType>, result: EffectValueType = n) =
                Triple(fn, types, result)
            return when (token.text) {
                "abs" -> spec(BuiltinFunction.ABS, listOf(n))
                "min" -> spec(BuiltinFunction.MIN, listOf(n, n))
                "max" -> spec(BuiltinFunction.MAX, listOf(n, n))
                "clamp" -> spec(BuiltinFunction.CLAMP, listOf(n, n, n))
                "round" -> spec(BuiltinFunction.ROUND, listOf(n))
                "floor" -> spec(BuiltinFunction.FLOOR, listOf(n))
                "ceil" -> spec(BuiltinFunction.CEIL, listOf(n))
                "sqrt" -> spec(BuiltinFunction.SQRT, listOf(n))
                "pow" -> spec(BuiltinFunction.POWER, listOf(n, n))
                "log" -> spec(BuiltinFunction.LOG, listOf(n))
                "sin" -> spec(BuiltinFunction.SIN, listOf(n))
                "cos" -> spec(BuiltinFunction.COS, listOf(n))
                "radians" -> spec(BuiltinFunction.RADIANS, listOf(n))
                "degrees" -> spec(BuiltinFunction.DEGREES, listOf(n))
                "map" -> spec(BuiltinFunction.MAP, List(5) { n })
                "lerp" -> spec(BuiltinFunction.LERP, listOf(n, n, n))
                "smoothstep" -> spec(BuiltinFunction.SMOOTHSTEP, listOf(n, n, n))
                "smootherstep" -> spec(BuiltinFunction.SMOOTHERSTEP, listOf(n, n, n))
                "easeIn" -> spec(BuiltinFunction.EASE_IN, listOf(n))
                "easeOut" -> spec(BuiltinFunction.EASE_OUT, listOf(n))
                "easeInOut" -> spec(BuiltinFunction.EASE_IN_OUT, listOf(n))
                "sineWave" -> spec(BuiltinFunction.SINE_WAVE, listOf(n, n))
                "triangleWave" -> spec(BuiltinFunction.TRIANGLE_WAVE, listOf(n, n))
                "sawWave" -> spec(BuiltinFunction.SAW_WAVE, listOf(n, n))
                "squareWave" -> spec(BuiltinFunction.SQUARE_WAVE, listOf(n, n, n))
                "random" -> spec(BuiltinFunction.RANDOM, listOf(n, n))
                "randomColor" -> spec(BuiltinFunction.RANDOM_COLOUR, emptyList(), c)
                "noise1D" -> spec(BuiltinFunction.NOISE_1D, listOf(n, n))
                "fbmNoise" -> spec(BuiltinFunction.FBM_NOISE, listOf(n, n, n))
                "smooth" -> spec(BuiltinFunction.SMOOTH, if (args.size == 2) listOf(n, n) else listOf(n, n, n))
                "deadzone" -> spec(BuiltinFunction.DEADZONE, listOf(n, n))
                "hysteresis" -> spec(BuiltinFunction.HYSTERESIS, listOf(n, n, n), b)
                "peakHold" -> spec(BuiltinFunction.PEAK_HOLD, listOf(n, n, n))
                "debounce" -> spec(BuiltinFunction.DEBOUNCE, listOf(b, n), b)
                "risingEdge" -> spec(BuiltinFunction.RISING_EDGE, listOf(b), b)
                "fallingEdge" -> spec(BuiltinFunction.FALLING_EDGE, listOf(b), b)
                "rgb" -> spec(BuiltinFunction.RGB, listOf(n, n, n), c)
                "red" -> spec(BuiltinFunction.RED, listOf(c))
                "green" -> spec(BuiltinFunction.GREEN, listOf(c))
                "blue" -> spec(BuiltinFunction.BLUE, listOf(c))
                "hue" -> spec(BuiltinFunction.HUE, listOf(c))
                "saturation" -> spec(BuiltinFunction.SATURATION, listOf(c))
                "value" -> spec(BuiltinFunction.VALUE, listOf(c))
                "mixRgb" -> spec(BuiltinFunction.MIX_RGB, listOf(c, c, n), c)
                "mixHsv" -> spec(BuiltinFunction.MIX_HSV, listOf(c, c, n), c)
                "complement" -> spec(BuiltinFunction.COMPLEMENT, listOf(c), c)
                "rotateHue" -> spec(BuiltinFunction.ROTATE_HUE, listOf(c, n), c)
                "adjustSaturation" -> spec(BuiltinFunction.ADJUST_SATURATION, listOf(c, n), c)
                "adjustValue" -> spec(BuiltinFunction.ADJUST_VALUE, listOf(c, n), c)
                "paletteColor" -> spec(BuiltinFunction.PALETTE_COLOUR, listOf(EffectValueType.COLOUR_LIST, n), c)
                "cycle" -> spec(BuiltinFunction.CYCLE, listOf(n))
                "beatPhase" -> spec(BuiltinFunction.BEAT_PHASE, listOf(n))
                "barPhase" -> spec(BuiltinFunction.BAR_PHASE, listOf(n, n, n))
                "mirror" -> listBuiltin(token, args, BuiltinFunction.MIRROR, 1)
                "rotatePattern" -> listBuiltin(token, args, BuiltinFunction.ROTATE_PATTERN, 2)
                "centerSpread" -> listBuiltin(token, args, BuiltinFunction.CENTER_SPREAD, 1)
                "centerContract" -> listBuiltin(token, args, BuiltinFunction.CENTER_CONTRACT, 1)
                "chase" -> spec(BuiltinFunction.CHASE, listOf(n), EffectValueType.NUMBER_LIST)
                "wavePattern" -> spec(BuiltinFunction.WAVE_PATTERN, listOf(n), EffectValueType.NUMBER_LIST)
                else -> error(token, "未知函数${token.text}", "未知の関数${token.text}です")
            }
        }

        private fun listBuiltin(
            token: Token,
            args: List<EffectExpression>,
            function: BuiltinFunction,
            count: Int,
        ): Triple<BuiltinFunction, List<EffectValueType>, EffectValueType> {
            if (args.size != count) error(token, "${token.text}参数数量错误", "${token.text}の引数数が正しくありません")
            val listType = args.firstOrNull()?.type
                ?.takeIf { elementType(it) != null }
                ?: error(token, "${token.text}需要列表", "${token.text}にはリストが必要です")
            val types = if (count == 1) listOf(listType) else listOf(listType, EffectValueType.NUMBER)
            return Triple(function, types, listType)
        }

        private fun requireArguments(
            token: Token,
            args: List<EffectExpression>,
            types: List<EffectValueType>,
        ) {
            if (args.size != types.size) error(token, "${token.text}需要${types.size}个参数", "${token.text}には${types.size}個の引数が必要です")
            args.zip(types).forEachIndexed { index, (value, expected) ->
                if (value.type != expected) {
                    error(token, "${token.text}第${index + 1}个参数类型错误", "${token.text}の${index + 1}番目の型が正しくありません")
                }
            }
        }

        private fun colour(token: Token): EffectExpression {
            val clean = token.text.removePrefix("#")
            if (clean.length != 6 || clean.toIntOrNull(16) == null) {
                error(token, "颜色必须是#RRGGBB", "色は#RRGGBB形式で入力してください")
            }
            val rgb = clean.toInt(16)
            val red = (rgb shr 16 and 255) / 255.0
            val green = (rgb shr 8 and 255) / 255.0
            val blue = (rgb and 255) / 255.0
            val high = max(red, max(green, blue))
            val low = min(red, min(green, blue))
            val delta = high - low
            var hue = when {
                delta == 0.0 -> 0.0
                high == red -> 60.0 * (((green - blue) / delta) % 6.0)
                high == green -> 60.0 * ((blue - red) / delta + 2.0)
                else -> 60.0 * ((red - green) / delta + 4.0)
            }
            if (hue < 0) hue += 360.0
            return EffectExpression.ColourLiteral(
                EffectColour(
                    hue.roundToInt().mod(360),
                    (if (high == 0.0) 0.0 else delta / high * 255.0).roundToInt().coerceIn(0, 255),
                    (high * 255.0).roundToInt().coerceIn(0, 255),
                ),
            )
        }

        private fun arithmetic(
            operator: ArithmeticOperator,
            left: EffectExpression,
            right: EffectExpression,
        ): EffectExpression {
            expectType(left, EffectValueType.NUMBER)
            expectType(right, EffectValueType.NUMBER)
            if (operator in setOf(ArithmeticOperator.DIVIDE, ArithmeticOperator.MODULO) &&
                (right as? EffectExpression.NumberLiteral)?.value == 0.0
            ) error(previous(), "除数不能为0", "0で割ることはできません")
            return EffectExpression.Arithmetic(operator, left, right)
        }

        private fun logic(
            operator: LogicOperator,
            left: EffectExpression,
            right: EffectExpression,
        ) = EffectExpression.Logic(
            operator,
            expectType(left, EffectValueType.BOOLEAN),
            expectType(right, EffectValueType.BOOLEAN),
        )

        private fun parseType(): EffectValueType = when (expectIdentifier("变量类型无效", "変数の型が無効です").text) {
            "number" -> scalarOrList(EffectValueType.NUMBER, EffectValueType.NUMBER_LIST)
            "bool", "boolean" -> scalarOrList(EffectValueType.BOOLEAN, EffectValueType.BOOLEAN_LIST)
            "color", "colour" -> scalarOrList(EffectValueType.COLOUR, EffectValueType.COLOUR_LIST)
            "target" -> scalarOrList(EffectValueType.TARGET, EffectValueType.TARGET_LIST)
            else -> error(previous(), "类型必须是number、bool、color或target", "型はnumber、bool、color、targetのいずれかです")
        }

        private fun scalarOrList(
            scalar: EffectValueType,
            list: EffectValueType,
        ): EffectValueType {
            if (!match("[")) return scalar
            expect("]", "列表类型需要“]”", "リスト型には「]」が必要です")
            return list
        }

        private fun elementType(type: EffectValueType): EffectValueType? = when (type) {
            EffectValueType.NUMBER_LIST -> EffectValueType.NUMBER
            EffectValueType.BOOLEAN_LIST -> EffectValueType.BOOLEAN
            EffectValueType.COLOUR_LIST -> EffectValueType.COLOUR
            EffectValueType.TARGET_LIST -> EffectValueType.TARGET
            else -> null
        }

        private fun listType(type: EffectValueType): EffectValueType = when (type) {
            EffectValueType.NUMBER -> EffectValueType.NUMBER_LIST
            EffectValueType.BOOLEAN -> EffectValueType.BOOLEAN_LIST
            EffectValueType.COLOUR -> EffectValueType.COLOUR_LIST
            EffectValueType.TARGET -> EffectValueType.TARGET_LIST
            else -> error(previous(), "不支持嵌套列表", "ネストしたリストは使用できません")
        }

        private fun expectType(value: EffectExpression, type: EffectValueType): EffectExpression {
            if (value.type != type) error(previous(), "表达式类型应为$type", "式の型は${type}である必要があります")
            return value
        }

        private fun sourceId(start: Token): String =
            "script:${start.start}:${previous().end}:${start.line}:${start.column}"

        private fun match(vararg texts: String): Boolean {
            if (texts.none(::check)) return false
            advance()
            return true
        }

        private fun expect(text: String, zh: String, ja: String): Token {
            if (check(text)) return advance()
            error(peek(), zh, ja)
        }

        private fun expectIdentifier(zh: String, ja: String) = expectKind(Kind.IDENTIFIER, zh, ja)

        private fun expectKind(kind: Kind, zh: String, ja: String): Token {
            if (peek().kind == kind) return advance()
            error(peek(), zh, ja)
        }

        private fun check(text: String) = !isAtEnd() && peek().text == text
        private fun isAtEnd() = peek().kind == Kind.EOF
        private fun peek() = tokens[current]
        private fun previous() = tokens[(current - 1).coerceAtLeast(0)]
        private fun advance(): Token {
            if (!isAtEnd()) current++
            return previous()
        }

        private fun error(token: Token, zh: String, ja: String): Nothing {
            val issue = EffectCompileIssue(
                code = "SCRIPT_SYNTAX",
                messageZh = "第${token.line}行第${token.column}列：$zh",
                messageJa = "${token.line}行${token.column}列：$ja",
                sourceId = "script:${token.start}:${token.end}:${token.line}:${token.column}",
                sourceStart = token.start,
                sourceEnd = token.end,
            )
            throw EffectCompileException(listOf(issue.combinedMessage), listOf(issue))
        }
    }
}

object EffectScriptFormatter {
    fun fromCompiled(name: String, compiled: CompiledEffect): String {
        val names = compiled.variables.keys.mapIndexed { index, id -> id to safeName(id, index) }.toMap()
        val output = StringBuilder().append("effect \"").append(name.replace("\"", "\\\"")).append("\" {\n")
        compiled.variables.forEach { (id, type) ->
            output.append("    let ${names.getValue(id)}: ${typeName(type)} = ${defaultValue(type)};\n")
        }
        compiled.operations.forEach { appendOperation(output, it, 1, names) }
        return output.append("}\n").toString()
    }

    private fun appendOperation(
        output: StringBuilder,
        operation: EffectOp,
        depth: Int,
        names: Map<String, String>,
    ) {
        val indent = "    ".repeat(depth)
        when (operation) {
            is EffectOp.SetHsv -> output.append("$indent${target(operation.target, names)}.hsv(${expr(operation.h, names)}, ${expr(operation.s, names)}, ${expr(operation.v, names)});\n")
            is EffectOp.SetColour -> output.append("$indent${target(operation.target, names)}.color(${expr(operation.colour, names)});\n")
            is EffectOp.FadeHsv -> output.append("$indent${target(operation.target, names)}.fade(hsv(${expr(operation.h, names)}, ${expr(operation.s, names)}, ${expr(operation.v, names)}), ${duration(operation.durationMs, names)});\n")
            is EffectOp.FadeColour -> output.append("$indent${target(operation.target, names)}.fade(${expr(operation.colour, names)}, ${duration(operation.durationMs, names)});\n")
            is EffectOp.AdjustHsv -> output.append("$indent${target(operation.target, names)}.adjustHsv(${expr(operation.dh, names)}, ${expr(operation.ds, names)}, ${expr(operation.dv, names)});\n")
            is EffectOp.SetMode -> output.append("$indent${target(operation.target, names)}.mode(${mode(operation.mode, names)}, ${expr(operation.param, names)});\n")
            is EffectOp.Wait -> output.append("$indent" + "wait(${duration(operation.durationMs, names)});\n")
            is EffectOp.SetVariable -> output.append("$indent${names[operation.id] ?: operation.id} = ${expr(operation.value, names)};\n")
            is EffectOp.ChangeVariable -> output.append("$indent${names[operation.id] ?: operation.id} += ${expr(operation.delta, names)};\n")
            is EffectOp.SetListItem -> output.append("$indent${names[operation.id] ?: operation.id}[${expr(operation.index, names)}] = ${expr(operation.value, names)};\n")
            is EffectOp.SeedRandom -> output.append("${indent}seedRandom(${expr(operation.seed, names)});\n")
            is EffectOp.CallFunction -> output.append(
                "$indent${operation.name}(${operation.arguments.joinToString(", ") { expr(it, names) }});\n",
            )
            is EffectOp.If -> {
                output.append("${indent}if (${expr(operation.condition, names)}) {\n")
                operation.thenBody.forEach { appendOperation(output, it, depth + 1, names) }
                output.append("$indent}")
                if (operation.elseBody.isNotEmpty()) {
                    output.append(" else {\n")
                    operation.elseBody.forEach { appendOperation(output, it, depth + 1, names) }
                    output.append("$indent}")
                }
                output.append("\n")
            }
            is EffectOp.Repeat -> {
                output.append(if (operation.count == null) "${indent}forever {\n"
                else "${indent}repeat(${expr(operation.count, names)}) {\n")
                operation.body.forEach { appendOperation(output, it, depth + 1, names) }
                output.append("$indent}\n")
            }
            is EffectOp.For -> {
                output.append("${indent}for (${names[operation.variableId] ?: operation.variableId} from ${expr(operation.from, names)} to ${expr(operation.to, names)} step ${expr(operation.step, names)}) {\n")
                operation.body.forEach { appendOperation(output, it, depth + 1, names) }
                output.append("$indent}\n")
            }
            is EffectOp.While -> {
                output.append("${indent}while (${expr(operation.condition, names)}) {\n")
                operation.body.forEach { appendOperation(output, it, depth + 1, names) }
                output.append("$indent}\n")
            }
            is EffectOp.Break -> output.append("${indent}break;\n")
            is EffectOp.Continue -> output.append("${indent}continue;\n")
            is EffectOp.End -> output.append("${indent}end;\n")
        }
    }

    private fun expr(value: EffectExpression, names: Map<String, String>): String = when (value) {
        is EffectExpression.NumberLiteral -> if (value.value % 1.0 == 0.0) value.value.toLong().toString() else value.value.toString()
        is EffectExpression.BooleanLiteral -> value.value.toString()
        is EffectExpression.ColourLiteral -> "hsv(${value.value.hue}, ${value.value.saturation}, ${value.value.value})"
        is EffectExpression.Variable -> names[value.id] ?: value.id
        EffectExpression.ElapsedMs -> "elapsedMs"
        is EffectExpression.GroupValue -> "group(${value.group + 1}).${value.property.name.lowercase()}"
        is EffectExpression.DynamicGroupValue -> "group(${expr(value.oneBasedIndex, names)}).${value.property.name.lowercase()}"
        is EffectExpression.Arithmetic -> when (value.operator) {
            ArithmeticOperator.MIN -> "min(${expr(value.left, names)}, ${expr(value.right, names)})"
            ArithmeticOperator.MAX -> "max(${expr(value.left, names)}, ${expr(value.right, names)})"
            ArithmeticOperator.POWER -> "pow(${expr(value.left, names)}, ${expr(value.right, names)})"
            else -> "(${expr(value.left, names)} ${arithmetic(value.operator)} ${expr(value.right, names)})"
        }
        is EffectExpression.Clamp -> "clamp(${expr(value.value, names)}, ${expr(value.low, names)}, ${expr(value.high, names)})"
        is EffectExpression.Comparison -> "(${expr(value.left, names)} ${comparison(value.operator)} ${expr(value.right, names)})"
        is EffectExpression.Logic -> "(${expr(value.left, names)} ${if (value.operator == LogicOperator.AND) "&&" else "||"} ${expr(value.right, names)})"
        is EffectExpression.Not -> "!${expr(value.value, names)}"
        is EffectExpression.ColourFromHsv -> "hsv(${expr(value.hue, names)}, ${expr(value.saturation, names)}, ${expr(value.value, names)})"
        is EffectExpression.TargetLiteral -> if (value.target == EffectTarget.ALL) "all" else "group(${value.target.ordinal})"
        is EffectExpression.TargetFromIndex -> "group(${expr(value.oneBasedIndex, names)})"
        is EffectExpression.RuntimeInput -> runtimeInputName(value.key)
        is EffectExpression.Builtin -> "${builtinName(value.function)}(${value.arguments.joinToString(", ") { expr(it, names) }})"
        is EffectExpression.ListLiteral -> value.elements.joinToString(prefix = "[", postfix = "]") { expr(it, names) }
        is EffectExpression.ListGet -> "${expr(value.list, names)}[${expr(value.index, names)}]"
        is EffectExpression.FunctionCall ->
            "${value.name}(${value.arguments.joinToString(", ") { expr(it, names) }})"
    }

    private fun duration(value: EffectExpression, names: Map<String, String>): String {
        val literal = (value as? EffectExpression.NumberLiteral)?.value
        return if (literal != null && literal % 1_000.0 == 0.0) "${(literal / 1_000).toLong()}s"
        else "${expr(value, names)}ms"
    }

    private fun target(target: EffectTargetRef, names: Map<String, String>) = when (target) {
        EffectTargetRef.All -> "all"
        EffectTargetRef.AllPixels -> "allPixels"
        is EffectTargetRef.Group -> "group(${expr(target.oneBasedIndex, names)})"
        is EffectTargetRef.Pixel ->
            "pixel(${expr(target.oneBasedGroup, names)}, ${expr(target.oneBasedPixel, names)})"
        is EffectTargetRef.PixelAt -> "pixelAt(${expr(target.oneBasedIndex, names)})"
        is EffectTargetRef.Value -> expr(target.expression, names)
    }

    private fun mode(value: EffectExpression, names: Map<String, String>) = when ((value as? EffectExpression.NumberLiteral)?.value?.toInt()) {
        1 -> "STEADY"
        3 -> "STROBE"
        else -> expr(value, names)
    }

    private fun safeName(id: String, index: Int): String {
        val clean = id.replace(Regex("[^A-Za-z0-9_]"), "_").trim('_')
        return if (clean.isNotBlank() && !clean.first().isDigit()) clean else "value${index + 1}"
    }

    private fun typeName(type: EffectValueType) = when (type) {
        EffectValueType.NUMBER -> "number"
        EffectValueType.BOOLEAN -> "bool"
        EffectValueType.COLOUR -> "color"
        EffectValueType.TARGET -> "target"
        EffectValueType.NUMBER_LIST -> "number[]"
        EffectValueType.BOOLEAN_LIST -> "bool[]"
        EffectValueType.COLOUR_LIST -> "color[]"
        EffectValueType.TARGET_LIST -> "target[]"
    }

    private fun defaultValue(type: EffectValueType) = when (type) {
        EffectValueType.NUMBER -> "0"
        EffectValueType.BOOLEAN -> "false"
        EffectValueType.COLOUR -> "hsv(0, 0, 255)"
        EffectValueType.TARGET -> "all"
        EffectValueType.NUMBER_LIST -> "[]"
        EffectValueType.BOOLEAN_LIST -> "[]"
        EffectValueType.COLOUR_LIST -> "[]"
        EffectValueType.TARGET_LIST -> "[]"
    }

    private fun runtimeInputName(key: RuntimeInputKey): String = when (key) {
        RuntimeInputKey.SENSOR_ACCEL_X -> "sensor.accelX"
        RuntimeInputKey.SENSOR_ACCEL_Y -> "sensor.accelY"
        RuntimeInputKey.SENSOR_ACCEL_Z -> "sensor.accelZ"
        RuntimeInputKey.SENSOR_MOTION -> "sensor.motion"
        RuntimeInputKey.SENSOR_SHAKE -> "sensor.shake"
        RuntimeInputKey.SENSOR_GYRO_X -> "sensor.gyroX"
        RuntimeInputKey.SENSOR_GYRO_Y -> "sensor.gyroY"
        RuntimeInputKey.SENSOR_GYRO_Z -> "sensor.gyroZ"
        RuntimeInputKey.SENSOR_PITCH -> "sensor.pitch"
        RuntimeInputKey.SENSOR_ROLL -> "sensor.roll"
        RuntimeInputKey.SENSOR_YAW -> "sensor.yaw"
        RuntimeInputKey.SENSOR_LIGHT -> "sensor.light"
        RuntimeInputKey.SENSOR_NEAR -> "sensor.near"
        RuntimeInputKey.SENSOR_HEADING -> "sensor.heading"
        RuntimeInputKey.SENSOR_PRESSURE -> "sensor.pressure"
        RuntimeInputKey.AUDIO_LEVEL -> "audio.level"
        RuntimeInputKey.AUDIO_PEAK -> "audio.peak"
        RuntimeInputKey.AUDIO_BASS -> "audio.bass"
        RuntimeInputKey.AUDIO_MID -> "audio.mid"
        RuntimeInputKey.AUDIO_TREBLE -> "audio.treble"
        RuntimeInputKey.AUDIO_BEAT -> "audio.beat"
        RuntimeInputKey.AUDIO_BPM -> "audio.bpm"
    }

    private fun builtinName(function: BuiltinFunction): String = when (function) {
        BuiltinFunction.RANDOM_COLOUR -> "randomColor"
        BuiltinFunction.NOISE_1D -> "noise1D"
        BuiltinFunction.FBM_NOISE -> "fbmNoise"
        BuiltinFunction.SINE_WAVE -> "sineWave"
        BuiltinFunction.TRIANGLE_WAVE -> "triangleWave"
        BuiltinFunction.SAW_WAVE -> "sawWave"
        BuiltinFunction.SQUARE_WAVE -> "squareWave"
        BuiltinFunction.EASE_IN -> "easeIn"
        BuiltinFunction.EASE_OUT -> "easeOut"
        BuiltinFunction.EASE_IN_OUT -> "easeInOut"
        BuiltinFunction.MIX_RGB -> "mixRgb"
        BuiltinFunction.MIX_HSV -> "mixHsv"
        BuiltinFunction.ROTATE_HUE -> "rotateHue"
        BuiltinFunction.ADJUST_SATURATION -> "adjustSaturation"
        BuiltinFunction.ADJUST_VALUE -> "adjustValue"
        BuiltinFunction.PALETTE_COLOUR -> "paletteColor"
        BuiltinFunction.PEAK_HOLD -> "peakHold"
        BuiltinFunction.RISING_EDGE -> "risingEdge"
        BuiltinFunction.FALLING_EDGE -> "fallingEdge"
        BuiltinFunction.BEAT_PHASE -> "beatPhase"
        BuiltinFunction.BAR_PHASE -> "barPhase"
        BuiltinFunction.LIST_LENGTH -> "length"
        BuiltinFunction.ROTATE_PATTERN -> "rotatePattern"
        BuiltinFunction.CENTER_SPREAD -> "centerSpread"
        BuiltinFunction.CENTER_CONTRACT -> "centerContract"
        BuiltinFunction.WAVE_PATTERN -> "wavePattern"
        else -> function.name.lowercase()
    }

    private fun arithmetic(operator: ArithmeticOperator) = when (operator) {
        ArithmeticOperator.ADD -> "+"
        ArithmeticOperator.SUBTRACT -> "-"
        ArithmeticOperator.MULTIPLY -> "*"
        ArithmeticOperator.DIVIDE -> "/"
        ArithmeticOperator.MODULO -> "%"
        ArithmeticOperator.POWER -> "*"
        ArithmeticOperator.MIN -> "min"
        ArithmeticOperator.MAX -> "max"
    }

    private fun comparison(operator: ComparisonOperator) = when (operator) {
        ComparisonOperator.EQ -> "=="
        ComparisonOperator.NEQ -> "!="
        ComparisonOperator.LT -> "<"
        ComparisonOperator.LTE -> "<="
        ComparisonOperator.GT -> ">"
        ComparisonOperator.GTE -> ">="
    }
}
