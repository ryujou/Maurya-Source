public enum EffectDiagnosticLanguage: Sendable {
    case simplifiedChinese
    case japanese
}

public struct EffectCompileIssue: Error, Equatable, Sendable {
    public let code: String
    public let messageZh: String
    public let messageJa: String
    public let sourceID: String
    public let quickFixWaitMilliseconds: Int64?
    public let sourceStart: Int?
    public let sourceEnd: Int?

    public init(
        code: String,
        messageZh: String,
        messageJa: String,
        sourceID: String = "",
        quickFixWaitMilliseconds: Int64? = nil,
        sourceStart: Int? = nil,
        sourceEnd: Int? = nil
    ) {
        self.code = code
        self.messageZh = messageZh
        self.messageJa = messageJa
        self.sourceID = sourceID
        self.quickFixWaitMilliseconds = quickFixWaitMilliseconds
        self.sourceStart = sourceStart
        self.sourceEnd = sourceEnd
    }

    public func message(for language: EffectDiagnosticLanguage) -> String {
        switch language {
        case .simplifiedChinese: messageZh
        case .japanese: messageJa
        }
    }
}

public struct EffectCompileError: Error, Equatable, Sendable {
    public let issues: [EffectCompileIssue]

    public init(issues: [EffectCompileIssue]) {
        self.issues = issues
    }
}

public indirect enum EffectTargetReference: Equatable, Sendable {
    case all
    case allPixels
    case group(oneBasedIndex: EffectExpression)
    case pixel(oneBasedGroup: EffectExpression, oneBasedPixel: EffectExpression)
    case pixelAt(oneBasedIndex: EffectExpression)
    case value(EffectExpression)

    public static func fixed(_ target: EffectTarget) -> Self {
        target == .all ? .all : .group(oneBasedIndex: .number(Double(target.groupIndex!)))
    }
}

public indirect enum EffectExpression: Equatable, Sendable {
    case number(Double)
    case boolean(Bool)
    case colour(EffectColour)
    case variable(id: String, type: EffectValueType)
    case elapsedMilliseconds
    case groupValue(zeroBasedGroup: Int, property: EffectGroupProperty)
    case dynamicGroupValue(oneBasedIndex: EffectExpression, property: EffectGroupProperty)
    case arithmetic(ArithmeticOperator, EffectExpression, EffectExpression)
    case clamp(value: EffectExpression, low: EffectExpression, high: EffectExpression)
    case comparison(ComparisonOperator, EffectExpression, EffectExpression)
    case logic(LogicOperator, EffectExpression, EffectExpression)
    case not(EffectExpression)
    case colourFromHSV(hue: EffectExpression, saturation: EffectExpression, value: EffectExpression)
    case target(EffectTarget)
    case targetFromIndex(EffectExpression)
    case runtimeInput(RuntimeInputKey)
    case builtin(BuiltinFunction, arguments: [EffectExpression], type: EffectValueType, nodeID: String = "")
    case list([EffectExpression], type: EffectValueType)
    case listGet(list: EffectExpression, index: EffectExpression, type: EffectValueType)
    case functionCall(name: String, arguments: [EffectExpression], type: EffectValueType, nodeID: String = "")

    public var type: EffectValueType {
        switch self {
        case .number, .elapsedMilliseconds, .groupValue, .dynamicGroupValue, .arithmetic, .clamp:
            .number
        case .boolean, .comparison, .logic, .not:
            .boolean
        case .colour, .colourFromHSV:
            .colour
        case .target, .targetFromIndex:
            .target
        case let .variable(_, type), let .builtin(_, _, type, _), let .list(_, type),
            let .listGet(_, _, type), let .functionCall(_, _, type, _):
            type
        case let .runtimeInput(key):
            key.valueType
        }
    }
}

public struct EffectFunctionParameter: Equatable, Sendable {
    public let name: String
    public let variableID: String
    public let type: EffectValueType

    public init(name: String, variableID: String, type: EffectValueType) {
        self.name = name
        self.variableID = variableID
        self.type = type
    }
}

public struct EffectFunctionDefinition: Equatable, Sendable {
    public let name: String
    public let parameters: [EffectFunctionParameter]
    public let returnType: EffectValueType?
    public let operations: [EffectOperation]
    public let returnExpression: EffectExpression?
    public let localVariableIDs: Set<String>

    public init(
        name: String,
        parameters: [EffectFunctionParameter] = [],
        returnType: EffectValueType? = nil,
        operations: [EffectOperation],
        returnExpression: EffectExpression? = nil,
        localVariableIDs: Set<String> = []
    ) {
        self.name = name
        self.parameters = parameters
        self.returnType = returnType
        self.operations = operations
        self.returnExpression = returnExpression
        self.localVariableIDs = localVariableIDs
    }
}

public indirect enum EffectOperation: Equatable, Sendable {
    case setHSV(EffectTargetReference, h: EffectExpression, s: EffectExpression, v: EffectExpression, blockID: String = "")
    case setColour(EffectTargetReference, EffectExpression, blockID: String = "")
    case fadeHSV(
        EffectTargetReference, h: EffectExpression, s: EffectExpression, v: EffectExpression, duration: EffectExpression,
        blockID: String = "")
    case fadeColour(EffectTargetReference, colour: EffectExpression, duration: EffectExpression, blockID: String = "")
    case adjustHSV(EffectTargetReference, dh: EffectExpression, ds: EffectExpression, dv: EffectExpression, blockID: String = "")
    case setMode(EffectTargetReference, mode: EffectExpression, parameter: EffectExpression, blockID: String = "")
    case wait(EffectExpression, blockID: String = "")
    case setVariable(id: String, value: EffectExpression, blockID: String = "")
    case changeVariable(id: String, delta: EffectExpression, blockID: String = "")
    case setListItem(id: String, index: EffectExpression, value: EffectExpression, blockID: String = "")
    case seedRandom(EffectExpression, blockID: String = "")
    case callFunction(name: String, arguments: [EffectExpression], blockID: String = "")
    case ifElse(EffectExpression, then: [EffectOperation], else: [EffectOperation], blockID: String = "")
    case repeatLoop(count: EffectExpression?, body: [EffectOperation], blockID: String = "")
    case forLoop(
        variableID: String, from: EffectExpression, through: EffectExpression, step: EffectExpression, body: [EffectOperation],
        blockID: String = "")
    case whileLoop(EffectExpression, body: [EffectOperation], blockID: String = "")
    case breakLoop(blockID: String = "")
    case continueLoop(blockID: String = "")
    case end(blockID: String = "")
}

public struct CompiledEffect: Equatable, Sendable {
    public let operations: [EffectOperation]
    public let blockCount: Int
    public let estimatedDurationMilliseconds: Int64?
    public let astSHA256: String
    public let variables: [String: EffectValueType]
    public let requiredInputs: Set<RuntimeInputKey>
    public let randomSeed: Int64
    public let functions: [String: EffectFunctionDefinition]
    public let requiresPixelEffect: Bool

    public init(
        operations: [EffectOperation],
        blockCount: Int,
        estimatedDurationMilliseconds: Int64? = nil,
        astSHA256: String = "",
        variables: [String: EffectValueType] = [:],
        requiredInputs: Set<RuntimeInputKey> = [],
        randomSeed: Int64 = 0,
        functions: [String: EffectFunctionDefinition] = [:],
        requiresPixelEffect: Bool = false
    ) {
        self.operations = operations
        self.blockCount = blockCount
        self.estimatedDurationMilliseconds = estimatedDurationMilliseconds
        self.astSHA256 = astSHA256
        self.variables = variables
        self.requiredInputs = requiredInputs
        self.randomSeed = randomSeed
        self.functions = functions
        self.requiresPixelEffect = requiresPixelEffect
    }
}

public struct EffectGroupState: Equatable, Sendable {
    public var innerMode: Int
    public var innerParameter: Int
    public var hue: Int
    public var saturation: Int
    public var value: Int

    public init(innerMode: Int = 1, innerParameter: Int = 0, hue: Int = 0, saturation: Int = 0, value: Int = 0) {
        self.innerMode = innerMode
        self.innerParameter = innerParameter
        self.hue = hue
        self.saturation = saturation
        self.value = value
    }
}

public struct EffectFrame: Equatable, Sendable {
    public let groups: [EffectGroupState]
    public let pixels: [EffectRGB]?
    public let finished: Bool
    public let waiting: Bool
    public let progress: Float?
}

public enum EffectGeometry: Sendable {
    public static let groupCount = 7
    public static let pixelsPerGroup = 6
    public static let pixelCount = 42
}

private extension EffectTarget {
    var groupIndex: Int? {
        switch self {
        case .all: nil
        case .group1: 1
        case .group2: 2
        case .group3: 3
        case .group4: 4
        case .group5: 5
        case .group6: 6
        case .group7: 7
        }
    }
}
