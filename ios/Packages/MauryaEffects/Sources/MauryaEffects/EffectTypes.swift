/// Values and identifiers shared by the effect compiler, interpreter, sensor
/// bridge, and editor. Raw strings intentionally match the Android enum names.
public enum EffectTarget: String, CaseIterable, Codable, Sendable {
    case all = "ALL"
    case group1 = "GROUP_1"
    case group2 = "GROUP_2"
    case group3 = "GROUP_3"
    case group4 = "GROUP_4"
    case group5 = "GROUP_5"
    case group6 = "GROUP_6"
    case group7 = "GROUP_7"
}

public enum EffectValueType: String, CaseIterable, Codable, Sendable {
    case number = "NUMBER"
    case boolean = "BOOLEAN"
    case colour = "COLOUR"
    case target = "TARGET"
    case numberList = "NUMBER_LIST"
    case booleanList = "BOOLEAN_LIST"
    case colourList = "COLOUR_LIST"
    case targetList = "TARGET_LIST"
}

public enum EffectGroupProperty: String, CaseIterable, Codable, Sendable {
    case hue = "HUE"
    case saturation = "SATURATION"
    case value = "VALUE"
    case mode = "MODE"
}

public enum ArithmeticOperator: String, CaseIterable, Codable, Sendable {
    case add = "ADD"
    case subtract = "SUBTRACT"
    case multiply = "MULTIPLY"
    case divide = "DIVIDE"
    case modulo = "MODULO"
    case power = "POWER"
    case minimum = "MIN"
    case maximum = "MAX"
}

public enum ComparisonOperator: String, CaseIterable, Codable, Sendable {
    case equal = "EQ"
    case notEqual = "NEQ"
    case lessThan = "LT"
    case lessThanOrEqual = "LTE"
    case greaterThan = "GT"
    case greaterThanOrEqual = "GTE"
}

public enum LogicOperator: String, CaseIterable, Codable, Sendable {
    case and = "AND"
    case or = "OR"
}

public enum EffectSourceKind: String, CaseIterable, Codable, Sendable {
    case blocks = "BLOCKS"
    case script = "SCRIPT"
}

public enum RuntimeInputKey: String, CaseIterable, Codable, Sendable {
    case sensorAccelX = "SENSOR_ACCEL_X"
    case sensorAccelY = "SENSOR_ACCEL_Y"
    case sensorAccelZ = "SENSOR_ACCEL_Z"
    case sensorMotion = "SENSOR_MOTION"
    case sensorShake = "SENSOR_SHAKE"
    case sensorGyroX = "SENSOR_GYRO_X"
    case sensorGyroY = "SENSOR_GYRO_Y"
    case sensorGyroZ = "SENSOR_GYRO_Z"
    case sensorPitch = "SENSOR_PITCH"
    case sensorRoll = "SENSOR_ROLL"
    case sensorYaw = "SENSOR_YAW"
    case sensorLight = "SENSOR_LIGHT"
    case sensorNear = "SENSOR_NEAR"
    case sensorHeading = "SENSOR_HEADING"
    case sensorPressure = "SENSOR_PRESSURE"
    case audioLevel = "AUDIO_LEVEL"
    case audioPeak = "AUDIO_PEAK"
    case audioBass = "AUDIO_BASS"
    case audioMid = "AUDIO_MID"
    case audioTreble = "AUDIO_TREBLE"
    case audioBeat = "AUDIO_BEAT"
    case audioBPM = "AUDIO_BPM"

    public var valueType: EffectValueType {
        self == .audioBeat ? .boolean : .number
    }
}

public enum BuiltinFunction: String, CaseIterable, Codable, Sendable {
    case absolute = "ABS"
    case minimum = "MIN"
    case maximum = "MAX"
    case clamp = "CLAMP"
    case power = "POWER"
    case round = "ROUND"
    case floor = "FLOOR"
    case ceil = "CEIL"
    case squareRoot = "SQRT"
    case logarithm = "LOG"
    case sine = "SIN"
    case cosine = "COS"
    case radians = "RADIANS"
    case degrees = "DEGREES"
    case map = "MAP"
    case lerp = "LERP"
    case smoothstep = "SMOOTHSTEP"
    case smootherstep = "SMOOTHERSTEP"
    case easeIn = "EASE_IN"
    case easeOut = "EASE_OUT"
    case easeInOut = "EASE_IN_OUT"
    case sineWave = "SINE_WAVE"
    case triangleWave = "TRIANGLE_WAVE"
    case sawWave = "SAW_WAVE"
    case squareWave = "SQUARE_WAVE"
    case random = "RANDOM"
    case noise1D = "NOISE_1D"
    case fbmNoise = "FBM_NOISE"
    case smooth = "SMOOTH"
    case deadzone = "DEADZONE"
    case hysteresis = "HYSTERESIS"
    case peakHold = "PEAK_HOLD"
    case debounce = "DEBOUNCE"
    case risingEdge = "RISING_EDGE"
    case fallingEdge = "FALLING_EDGE"
    case rgb = "RGB"
    case red = "RED"
    case green = "GREEN"
    case blue = "BLUE"
    case hue = "HUE"
    case saturation = "SATURATION"
    case value = "VALUE"
    case mixRGB = "MIX_RGB"
    case mixHSV = "MIX_HSV"
    case complement = "COMPLEMENT"
    case rotateHue = "ROTATE_HUE"
    case adjustSaturation = "ADJUST_SATURATION"
    case adjustValue = "ADJUST_VALUE"
    case paletteColour = "PALETTE_COLOUR"
    case randomColour = "RANDOM_COLOUR"
    case cycle = "CYCLE"
    case beatPhase = "BEAT_PHASE"
    case barPhase = "BAR_PHASE"
    case listLength = "LIST_LENGTH"
    case mirror = "MIRROR"
    case rotatePattern = "ROTATE_PATTERN"
    case centerSpread = "CENTER_SPREAD"
    case centerContract = "CENTER_CONTRACT"
    case chase = "CHASE"
    case wavePattern = "WAVE_PATTERN"
}

public struct EffectColour: Equatable, Hashable, Codable, Sendable {
    public var hue: Int
    public var saturation: Int
    public var value: Int

    public init(hue: Int, saturation: Int, value: Int) {
        self.hue = hue
        self.saturation = saturation
        self.value = value
    }

    public var normalized: Self {
        Self(
            hue: EffectMath.wrapHue(hue),
            saturation: saturation.clamped(to: 0...255),
            value: value.clamped(to: 0...255)
        )
    }
}

public struct EffectRGB: Equatable, Hashable, Codable, Sendable {
    public let red: Int
    public let green: Int
    public let blue: Int

    public init(red: Int, green: Int, blue: Int) throws {
        guard (0...255).contains(red),
            (0...255).contains(green),
            (0...255).contains(blue)
        else {
            throw EffectRuntimeError.invalidRGB(red: red, green: green, blue: blue)
        }
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(clampingRed red: Int, green: Int, blue: Int) {
        self.red = red.clamped(to: 0...255)
        self.green = green.clamped(to: 0...255)
        self.blue = blue.clamped(to: 0...255)
    }
}

public indirect enum EffectValue: Equatable, Sendable {
    case number(Double)
    case boolean(Bool)
    case colour(EffectColour)
    case target(EffectTarget)
    case list(elementType: EffectValueType, values: [EffectValue])

    public var type: EffectValueType {
        switch self {
        case .number: .number
        case .boolean: .boolean
        case .colour: .colour
        case .target: .target
        case let .list(elementType, _):
            switch elementType {
            case .number: .numberList
            case .boolean: .booleanList
            case .colour: .colourList
            case .target: .targetList
            case .numberList, .booleanList, .colourList, .targetList:
                elementType
            }
        }
    }
}

public enum EffectProgramSchemas: Sendable {
    public static let editor = 4
    public static let program = 6
}

public enum EffectRuntimeFailureCode: String, Equatable, Sendable {
    case invalidInitialGroupCount
    case instructionBudgetExceeded
    case pixelHardwareModeConflict
    case missingVariable
    case variableTypeMismatch
    case missingNumericVariable
    case missingList
    case listIndexOutOfRange
    case listElementTypeMismatch
    case invalidFunction
    case zeroForStep
    case forIterationLimit
    case loopControlOutsideLoop
    case targetOutOfRange
    case listLimitOrNested
    case expectedList
    case expectedColourList
    case invalidColourFunction
    case invalidStatefulFunction
    case functionCallDepthExceeded
    case invalidValueFunctionBody
    case functionReturnTypeMismatch
    case functionArgumentCountMismatch
    case functionArgumentTypeMismatch
    case pixelModeRequired
    case targetTypeMismatch
    case expectedNumber
    case expectedBoolean
    case expectedColour
    case nonFiniteNumber
    case divisionByZero
    case wireGroupOutOfRange
}

public enum EffectRuntimeError: Error, Equatable, Sendable {
    case insufficientArguments(function: BuiltinFunction, expected: Int, actual: Int)
    case invalidPositiveArgument(name: String)
    case squareRootOfNegative
    case logarithmOfNonPositive
    case invalidNoiseOctaves
    case unsupportedPureNumericBuiltin(BuiltinFunction)
    case invalidRGB(red: Int, green: Int, blue: Int)
    case emptyPalette
    case patternRequiresSevenValues(actual: Int)
    case execution(code: EffectRuntimeFailureCode, context: String? = nil)
}

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
