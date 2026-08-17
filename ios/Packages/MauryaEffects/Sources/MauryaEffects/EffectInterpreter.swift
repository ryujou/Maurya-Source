import Foundation

public struct EffectInterpreter: Sendable {
    private enum RuntimeItem: Sendable {
        case execute(EffectOperation)
        case repeatLoop(operation: EffectOperation, iteration: Int, limit: Int?, loopID: String)
        case forLoop(operation: EffectOperation, current: Double, end: Double, step: Double, iteration: Int, loopID: String)
        case whileLoop(operation: EffectOperation, loopID: String)
        case boundary(String)

        var loopID: String? {
            switch self {
            case let .repeatLoop(_, _, _, id), let .forLoop(_, _, _, _, _, id), let .whileLoop(_, id), let .boundary(id): id
            case .execute: nil
            }
        }
    }

    private struct ActiveFade: Sendable {
        let targetIndices: [Int]
        let startStates: [EffectGroupState]
        let colour: EffectColour
        let startMilliseconds: Int64
        let endMilliseconds: Int64
        let pixelMode: Bool
    }

    private struct AlgorithmState: Sendable {
        var random: DeterministicRandom
        var numbers: [String: Double] = [:]
        var booleans: [String: Bool] = [:]
        var timestamps: [String: Int64] = [:]
    }

    private let compiled: CompiledEffect
    private let originalGroups: [EffectGroupState]
    private let originalPixels: [EffectGroupState]
    private var groups: [EffectGroupState]
    private var pixels: [EffectGroupState]
    private var variables: [String: EffectValue] = [:]
    private var stack: [RuntimeItem] = []
    private var activeWaitEnd: Int64?
    private var activeFade: ActiveFade?
    private var logicalTime: Int64 = 0
    private var lastElapsed: Int64 = -1
    private var finished = false
    private var zeroTimeInstructions = 0
    private var loopSerial: Int64 = 0
    private var snapshot = EffectRuntimeSnapshot.empty
    private var algorithmState: AlgorithmState
    private var functionCallDepth = 0
    private var executionCheckpoint: EffectExecutionCheckpoint = {}

    public init(_ compiled: CompiledEffect, initialGroups: [EffectGroupState]) throws {
        guard initialGroups.count == EffectGeometry.groupCount else {
            throw EffectRuntimeError.execution(code: .invalidInitialGroupCount)
        }
        self.compiled = compiled
        self.originalGroups = initialGroups.map { state in
            var copy = state
            copy.innerMode = 1
            return copy
        }
        self.originalPixels = self.originalGroups.flatMap { group in
            (0..<EffectGeometry.pixelsPerGroup).map { _ in
                var copy = group
                copy.innerMode = 1
                copy.innerParameter = 0
                return copy
            }
        }
        self.groups = self.originalGroups
        self.pixels = self.originalPixels
        self.algorithmState = AlgorithmState(random: DeterministicRandom(seed: compiled.randomSeed))
        reset()
    }

    public var isInfinite: Bool { compiled.estimatedDurationMilliseconds == nil }
    public var durationMilliseconds: Int64? { compiled.estimatedDurationMilliseconds }

    public mutating func frame(
        at elapsedMilliseconds: Int64,
        snapshot: EffectRuntimeSnapshot = .empty
    ) throws -> EffectFrame {
        try frame(at: elapsedMilliseconds, snapshot: snapshot, checkpoint: {})
    }

    mutating func frame(
        at elapsedMilliseconds: Int64,
        snapshot: EffectRuntimeSnapshot,
        checkpoint: @escaping EffectExecutionCheckpoint
    ) throws -> EffectFrame {
        executionCheckpoint = checkpoint
        defer { executionCheckpoint = {} }
        try executionCheckpoint()
        let elapsed = max(0, elapsedMilliseconds)
        if elapsed < lastElapsed { reset() }
        self.snapshot = snapshot
        lastElapsed = elapsed
        try advance(to: elapsed)
        let progress = durationMilliseconds.flatMap { duration in
            duration > 0 ? Float(Double(elapsed) / Double(duration)).clamped(to: 0...1) : nil
        }
        return EffectFrame(
            groups: groups,
            pixels: compiled.requiresPixelEffect ? pixels.map(pixelRGB) : nil,
            finished: finished,
            waiting: activeWaitEnd != nil,
            progress: progress
        )
    }

    private mutating func reset() {
        groups = originalGroups
        pixels = originalPixels
        variables = compiled.variables.mapValues(defaultValue)
        stack.removeAll(keepingCapacity: true)
        pushSequence(compiled.operations)
        activeWaitEnd = nil
        activeFade = nil
        logicalTime = 0
        lastElapsed = -1
        finished = false
        zeroTimeInstructions = 0
        loopSerial = 0
        algorithmState = AlgorithmState(random: DeterministicRandom(seed: compiled.randomSeed))
        functionCallDepth = 0
    }

    private mutating func advance(to target: Int64) throws {
        while finished == false {
            try executionCheckpoint()
            if let waitEnd = activeWaitEnd {
                guard target >= waitEnd else { return }
                logicalTime = waitEnd
                activeWaitEnd = nil
                zeroTimeInstructions = 0
            }
            if let fade = activeFade {
                let duration = max(1, fade.endMilliseconds - fade.startMilliseconds)
                let progress = Float(Double(target - fade.startMilliseconds) / Double(duration)).clamped(to: 0...1)
                apply(fade: fade, progress: progress)
                guard target >= fade.endMilliseconds else { return }
                logicalTime = fade.endMilliseconds
                activeFade = nil
                zeroTimeInstructions = 0
            }
            guard let item = stack.popLast() else {
                finished = true
                return
            }
            try executionCheckpoint()
            zeroTimeInstructions += 1
            guard zeroTimeInstructions <= 1_000 else {
                throw EffectRuntimeError.execution(code: .instructionBudgetExceeded)
            }
            switch item {
            case let .execute(operation): try execute(operation)
            case let .repeatLoop(operation, iteration, limit, loopID):
                try executeRepeat(operation, iteration: iteration, limit: limit, loopID: loopID)
            case let .forLoop(operation, current, end, step, iteration, loopID):
                try executeFor(operation, current: current, end: end, step: step, iteration: iteration, loopID: loopID)
            case let .whileLoop(operation, loopID): try executeWhile(operation, loopID: loopID)
            case .boundary: break
            }
        }
    }

    private mutating func execute(_ operation: EffectOperation) throws {
        try executionCheckpoint()
        switch operation {
        case let .setHSV(target, h, s, v, _):
            let colour = EffectColour(
                hue: wrap(kotlinRoundToInt(try number(h))), saturation: kotlinRoundToInt(try number(s)).clamped(to: 0...255),
                value: kotlinRoundToInt(try number(v)).clamped(to: 0...255))
            try mutate(target) { state in
                var copy = state; copy.hue = colour.hue; copy.saturation = colour.saturation; copy.value = colour.value; return copy
            }
        case let .setColour(target, expression, _):
            let value = try colour(expression).normalized
            try mutate(target) { state in
                var copy = state; copy.hue = value.hue; copy.saturation = value.saturation; copy.value = value.value; return copy
            }
        case let .fadeHSV(target, h, s, v, durationExpression, _):
            try beginFade(
                target,
                colour: EffectColour(
                    hue: wrap(kotlinRoundToInt(try number(h))), saturation: kotlinRoundToInt(try number(s)).clamped(to: 0...255),
                    value: kotlinRoundToInt(try number(v)).clamped(to: 0...255)), duration: try duration(durationExpression))
        case let .fadeColour(target, expression, durationExpression, _):
            try beginFade(target, colour: try colour(expression).normalized, duration: try duration(durationExpression))
        case let .adjustHSV(target, dh, ds, dv, _):
            let hue = kotlinRoundToInt(try number(dh)), saturation = kotlinRoundToInt(try number(ds)),
                value = kotlinRoundToInt(try number(dv))
            try mutate(target) { state in
                var copy = state
                let rawHue = (state.hue + hue) % 360
                copy.hue = rawHue < 0 ? rawHue + 360 : rawHue
                copy.saturation = (state.saturation + saturation).clamped(to: 0...255)
                copy.value = (state.value + value).clamped(to: 0...255)
                return copy
            }
        case let .setMode(target, mode, parameter, _):
            guard compiled.requiresPixelEffect == false else { throw runtime(.pixelHardwareModeConflict) }
            let requested = kotlinRoundToInt(try number(mode))
            let actualMode = requested == 3 ? 3 : 1
            let actualParameter = kotlinRoundToInt(try number(parameter)).clamped(to: 0...255)
            try mutate(target) { state in
                var copy = state; copy.innerMode = actualMode; copy.innerParameter = actualParameter; return copy
            }
        case let .wait(expression, _): activeWaitEnd = logicalTime + (try duration(expression))
        case let .setVariable(id, expression, _):
            guard let expected = compiled.variables[id] else { throw runtime(.missingVariable) }
            let value = try evaluate(expression)
            guard value.type == expected else { throw runtime(.variableTypeMismatch) }
            variables[id] = value
        case let .changeVariable(id, delta, _):
            guard case let .number(current)? = variables[id] else { throw runtime(.missingNumericVariable) }
            variables[id] = .number(try finite(current + number(delta)))
        case let .setListItem(id, index, expression, _):
            guard case let .list(elementType, existing)? = variables[id] else { throw runtime(.missingList) }
            let offset = Int(floor(try number(index)))
            guard existing.indices.contains(offset) else { throw runtime(.listIndexOutOfRange) }
            let value = try evaluate(expression)
            guard value.type == elementType else { throw runtime(.listElementTypeMismatch) }
            var changed = existing; changed[offset] = value; variables[id] = .list(elementType: elementType, values: changed)
        case let .seedRandom(expression, _): algorithmState.random.reseed(kotlinRoundToLong(try number(expression)))
        case let .callFunction(name, arguments, _):
            guard let function = compiled.functions[name], function.returnType == nil else { throw runtime(.invalidFunction) }
            try bind(function, arguments: arguments)
            pushSequence(function.operations)
        case let .ifElse(condition, thenBody, elseBody, _): pushSequence(try boolean(condition) ? thenBody : elseBody)
        case let .repeatLoop(count, _, blockID):
            let limit: Int?
            if let count { limit = kotlinRoundToInt(try number(count)).clamped(to: 0...1_000) } else { limit = nil }
            stack.append(.repeatLoop(operation: operation, iteration: 0, limit: limit, loopID: nextLoopID(blockID)))
        case let .forLoop(_, from, through, step, _, blockID):
            let increment = try number(step)
            guard increment != 0 else { throw runtime(.zeroForStep) }
            stack.append(
                .forLoop(
                    operation: operation, current: try number(from), end: try number(through), step: increment, iteration: 0,
                    loopID: nextLoopID(blockID)))
        case let .whileLoop(_, _, blockID): stack.append(.whileLoop(operation: operation, loopID: nextLoopID(blockID)))
        case .breakLoop: try discardLoop(breaking: true)
        case .continueLoop: try discardLoop(breaking: false)
        case .end: stack.removeAll(); activeWaitEnd = nil; activeFade = nil; finished = true
        }
    }

    private mutating func executeRepeat(_ operation: EffectOperation, iteration: Int, limit: Int?, loopID: String) throws {
        try executionCheckpoint()
        guard case let .repeatLoop(_, body, _) = operation else { return }
        if let limit, iteration >= limit { return }
        stack.append(.repeatLoop(operation: operation, iteration: iteration == .max ? 0 : iteration + 1, limit: limit, loopID: loopID))
        stack.append(.boundary(loopID))
        pushSequence(body)
    }

    private mutating func executeFor(
        _ operation: EffectOperation, current: Double, end: Double, step: Double, iteration: Int, loopID: String
    ) throws {
        try executionCheckpoint()
        guard case let .forLoop(variableID, _, _, _, body, _) = operation else { return }
        guard step > 0 ? current <= end : current >= end else { return }
        guard iteration < 1_000 else { throw runtime(.forIterationLimit) }
        variables[variableID] = .number(current)
        stack.append(
            .forLoop(
                operation: operation, current: try finite(current + step), end: end, step: step, iteration: iteration + 1, loopID: loopID))
        stack.append(.boundary(loopID))
        pushSequence(body)
    }

    private mutating func executeWhile(_ operation: EffectOperation, loopID: String) throws {
        try executionCheckpoint()
        guard case let .whileLoop(condition, body, _) = operation, try boolean(condition) else { return }
        stack.append(.whileLoop(operation: operation, loopID: loopID))
        stack.append(.boundary(loopID))
        pushSequence(body)
    }

    private mutating func discardLoop(breaking: Bool) throws {
        while let item = stack.popLast() {
            try executionCheckpoint()
            guard case let .boundary(loopID) = item else { continue }
            if breaking, stack.last?.loopID == loopID { stack.removeLast() }
            return
        }
        throw runtime(.loopControlOutsideLoop)
    }

    private mutating func evaluate(_ expression: EffectExpression) throws -> EffectValue {
        switch expression {
        case let .number(value): return .number(try finite(value))
        case let .boolean(value): return .boolean(value)
        case let .colour(value): return .colour(value.normalized)
        case let .variable(id, _): guard let value = variables[id] else { throw runtime(.missingVariable) }; return value
        case .elapsedMilliseconds: return .number(Double(logicalTime))
        case let .groupValue(index, property): return .number(groupProperty(groups[index.clamped(to: 0...6)], property))
        case let .dynamicGroupValue(index, property):
            let value = kotlinRoundToInt(try number(index)); guard (1...7).contains(value) else { throw rangeError() }
            return .number(groupProperty(groups[value - 1], property))
        case let .arithmetic(operation, lhs, rhs):
            let left = try number(lhs), right = try number(rhs)
            let value: Double =
                switch operation {
                case .add: left + right
                case .subtract: left - right
                case .multiply: left * right
                case .divide: try divide(left, right)
                case .modulo: try modulo(left, right)
                case .power: Foundation.pow(left, right)
                case .minimum: min(left, right)
                case .maximum: max(left, right)
                }
            return .number(try finite(value))
        case let .clamp(value, low, high):
            let first = try number(low), second = try number(high)
            return .number(try number(value).clamped(to: min(first, second)...max(first, second)))
        case let .comparison(operation, lhs, rhs):
            let left = try evaluate(lhs), right = try evaluate(rhs)
            let value: Bool =
                switch operation {
                case .equal: left == right
                case .notEqual: left != right
                case .lessThan: try numericComparison(left, right, <)
                case .lessThanOrEqual: try numericComparison(left, right, <=)
                case .greaterThan: try numericComparison(left, right, >)
                case .greaterThanOrEqual: try numericComparison(left, right, >=)
                }
            return .boolean(value)
        case let .logic(operation, lhs, rhs):
            return .boolean(operation == .and ? (try boolean(lhs) && boolean(rhs)) : (try boolean(lhs) || boolean(rhs)))
        case let .not(value): return .boolean(try !boolean(value))
        case let .colourFromHSV(h, s, v):
            return .colour(
                EffectColour(
                    hue: wrap(kotlinRoundToInt(try number(h))), saturation: kotlinRoundToInt(try number(s)).clamped(to: 0...255),
                    value: kotlinRoundToInt(try number(v)).clamped(to: 0...255)))
        case let .target(value): return .target(value)
        case let .targetFromIndex(expression):
            let index = kotlinRoundToInt(try number(expression)); guard let target = target(index) else { throw rangeError() };
            return .target(target)
        case let .runtimeInput(key): return snapshot[key]
        case let .builtin(function, arguments, _, nodeID): return try evaluateBuiltin(function, arguments: arguments, nodeID: nodeID)
        case let .list(elements, type):
            guard elements.count <= EffectGeometry.pixelCount, let elementType = elementType(type) else {
                throw runtime(.listLimitOrNested)
            }
            let values = try elements.map { try evaluate($0) };
            guard values.allSatisfy({ $0.type == elementType }) else { throw runtime(.listElementTypeMismatch) }
            return .list(elementType: elementType, values: values)
        case let .listGet(listExpression, index, _):
            guard case let .list(_, values) = try evaluate(listExpression) else { throw runtime(.expectedList) }
            let offset = Int(floor(try number(index))); guard values.indices.contains(offset) else { throw runtime(.listIndexOutOfRange) };
            return values[offset]
        case let .functionCall(name, arguments, _, _): return try evaluateFunction(name, arguments: arguments)
        }
    }

    private mutating func evaluateBuiltin(_ function: BuiltinFunction, arguments: [EffectExpression], nodeID: String) throws -> EffectValue
    {
        if function == .random {
            return .number(
                EffectMath.random(from: try number(arguments[0]), through: try number(arguments[1]), using: &algorithmState.random))
        }
        if function == .randomColour { return .colour(EffectMath.randomColour(using: &algorithmState.random)) }
        if function == .listLength {
            guard case let .list(_, values) = try evaluate(arguments[0]) else { throw runtime(.expectedList) };
            return .number(Double(values.count))
        }
        if function == .mirror || function == .rotatePattern || function == .centerSpread || function == .centerContract {
            guard case let .list(type, values) = try evaluate(arguments[0]) else { throw runtime(.expectedList) }
            let transformed: [EffectValue] =
                switch function {
                case .mirror: EffectPatternMath.mirror(values)
                case .rotatePattern: EffectPatternMath.rotate(values, shift: kotlinRoundToInt(try number(arguments[1])))
                case .centerSpread: try EffectPatternMath.centerSpread(values)
                default: try EffectPatternMath.centerContract(values)
                }
            return .list(elementType: type, values: transformed)
        }
        if function == .chase {
            return .list(elementType: .number, values: EffectPatternMath.chase(progress: try number(arguments[0])).map(EffectValue.number))
        }
        if function == .wavePattern {
            return .list(elementType: .number, values: EffectPatternMath.wave(progress: try number(arguments[0])).map(EffectValue.number))
        }
        if [.rgb, .mixRGB, .mixHSV, .complement, .rotateHue, .adjustSaturation, .adjustValue, .paletteColour].contains(function) {
            return .colour(try colourBuiltin(function, arguments))
        }
        if [.red, .green, .blue, .hue, .saturation, .value].contains(function) {
            let value = try colour(arguments[0]); if function == .hue { return .number(Double(value.hue)) };
            if function == .saturation { return .number(Double(value.saturation)) };
            if function == .value { return .number(Double(value.value)) }
            let rgb = EffectMath.hsvToRGB(value);
            return .number(Double(function == .red ? rgb.red : function == .green ? rgb.green : rgb.blue))
        }
        if [.smooth, .hysteresis, .peakHold, .debounce, .risingEdge, .fallingEdge].contains(function) {
            return try stateful(function, arguments, id: nodeID.isEmpty ? "\(function):\(arguments)" : nodeID)
        }
        var numbers: [Double] = []
        for argument in arguments { numbers.append(try number(argument)) }
        return .number(try finite(EffectMath.number(function, arguments: numbers, elapsedMilliseconds: logicalTime)))
    }

    private mutating func colourBuiltin(_ function: BuiltinFunction, _ arguments: [EffectExpression]) throws -> EffectColour {
        switch function {
        case .rgb:
            return EffectMath.rgbToHSV(
                red: kotlinRoundToInt(try number(arguments[0])), green: kotlinRoundToInt(try number(arguments[1])),
                blue: kotlinRoundToInt(try number(arguments[2])))
        case .mixRGB: return EffectMath.mixRGB(try colour(arguments[0]), try colour(arguments[1]), amount: try number(arguments[2]))
        case .mixHSV: return EffectMath.mixHSV(try colour(arguments[0]), try colour(arguments[1]), amount: try number(arguments[2]))
        case .complement: return EffectMath.complement(try colour(arguments[0]))
        case .rotateHue: return EffectMath.rotateHue(try colour(arguments[0]), degrees: kotlinRoundToInt(try number(arguments[1])))
        case .adjustSaturation: return EffectMath.adjustSaturation(try colour(arguments[0]), by: kotlinRoundToInt(try number(arguments[1])))
        case .adjustValue: return EffectMath.adjustValue(try colour(arguments[0]), by: kotlinRoundToInt(try number(arguments[1])))
        case .paletteColour:
            guard case let .list(.colour, values) = try evaluate(arguments[0]) else { throw runtime(.expectedColourList) }
            return try EffectMath.paletteColour(
                try values.map { value in
                    guard case let .colour(colour) = value else { throw runtime(.expectedColourList) }; return colour
                }, position: try number(arguments[1]))
        default: throw runtime(.invalidColourFunction)
        }
    }

    private mutating func stateful(_ function: BuiltinFunction, _ arguments: [EffectExpression], id: String) throws -> EffectValue {
        let boolInput = function == .debounce || function == .risingEdge || function == .fallingEdge
        let input = boolInput ? (try boolean(arguments[0]) ? 1.0 : 0.0) : try number(arguments[0])
        let previous = algorithmState.numbers[id] ?? input
        let previousTime = algorithmState.timestamps[id] ?? logicalTime
        let delta = max(0, logicalTime - previousTime)
        algorithmState.timestamps[id] = logicalTime
        switch function {
        case .smooth:
            let attack = max(1, try number(arguments[1])); let release = arguments.count > 2 ? max(1, try number(arguments[2])) : attack;
            let tau = input > previous ? attack : release; let output = previous + (input - previous) * (1 - exp(-Double(delta) / tau));
            algorithmState.numbers[id] = output; return .number(output)
        case .hysteresis:
            let low = try number(arguments[1]), high = try number(arguments[2]), old = algorithmState.booleans[id] ?? false;
            let next = old ? input > min(low, high) : input >= max(low, high); algorithmState.booleans[id] = next; return .boolean(next)
        case .peakHold:
            let hold = Int64(max(0, try number(arguments[1]))), decay = max(1, try number(arguments[2])),
                peakAt = algorithmState.timestamps["\(id):peak"] ?? logicalTime
            ; let output: Double
            if input >= previous {
                algorithmState.timestamps["\(id):peak"] = logicalTime; output = input
            } else if logicalTime - peakAt <= hold {
                output = previous
            } else {
                output = max(input, previous - Double(delta) / decay)
            }; algorithmState.numbers[id] = output; return .number(output)
        case .debounce:
            let desired = input > 0.5, stable = algorithmState.booleans[id] ?? desired,
                changedAt = algorithmState.timestamps["\(id):changed"] ?? logicalTime
            if desired != stable, Double(logicalTime - changedAt) >= max(0, try number(arguments[1])) {
                algorithmState.booleans[id] = desired
            } else if desired == stable {
                algorithmState.timestamps["\(id):changed"] = logicalTime
            }; return .boolean(algorithmState.booleans[id] ?? desired)
        case .risingEdge, .fallingEdge:
            let current = input > 0.5, old = algorithmState.booleans[id] ?? current; algorithmState.booleans[id] = current;
            return .boolean(function == .risingEdge ? (old == false && current) : (old && current == false))
        default: throw runtime(.invalidStatefulFunction)
        }
    }

    private mutating func evaluateFunction(_ name: String, arguments: [EffectExpression]) throws -> EffectValue {
        try executionCheckpoint()
        guard let function = compiled.functions[name], let expression = function.returnExpression else { throw runtime(.invalidFunction) }
        functionCallDepth += 1; defer { functionCallDepth -= 1 };
        guard functionCallDepth <= 8 else { throw runtime(.functionCallDepthExceeded) }
        let saved = function.localVariableIDs.reduce(into: [String: EffectValue?]()) { $0[$1] = variables[$1] }
        defer { saved.forEach { variables[$0.key] = $0.value } }
        try bind(function, arguments: arguments)
        for operation in function.operations {
            try executionCheckpoint()
            switch operation {
            case .setVariable, .changeVariable, .setListItem: try execute(operation)
            default: throw runtime(.invalidValueFunctionBody)
            }
        }
        let value = try evaluate(expression); guard value.type == function.returnType else { throw runtime(.functionReturnTypeMismatch) };
        return value
    }

    private mutating func bind(_ function: EffectFunctionDefinition, arguments: [EffectExpression]) throws {
        guard arguments.count == function.parameters.count else { throw runtime(.functionArgumentCountMismatch) }
        let values = try arguments.map { try evaluate($0) }
        for (parameter, value) in zip(function.parameters, values) {
            guard parameter.type == value.type else { throw runtime(.functionArgumentTypeMismatch) };
            variables[parameter.variableID] = value
        }
    }

    private mutating func beginFade(_ target: EffectTargetReference, colour: EffectColour, duration: Int64) throws {
        activeFade = ActiveFade(
            targetIndices: try resolve(target), startStates: compiled.requiresPixelEffect ? pixels : groups, colour: colour,
            startMilliseconds: logicalTime, endMilliseconds: logicalTime + duration, pixelMode: compiled.requiresPixelEffect)
    }

    private mutating func apply(fade: ActiveFade, progress: Float) {
        for index in fade.targetIndices {
            let start = fade.startStates[index], delta = (fade.colour.hue - start.hue + 540) % 360 - 180
            var value = start; value.hue = wrap(start.hue + kotlinRoundToInt(Double(Float(delta) * progress)));
            value.saturation = kotlinRoundToInt(
                Double(Float(start.saturation) + Float(fade.colour.saturation - start.saturation) * progress)
            ).clamped(to: 0...255);
            value.value = kotlinRoundToInt(Double(Float(start.value) + Float(fade.colour.value - start.value) * progress)).clamped(
                to: 0...255)
            if fade.pixelMode { pixels[index] = value } else { groups[index] = value }
        }
        if fade.pixelMode { syncGroupPreview() }
    }

    private mutating func mutate(_ target: EffectTargetReference, transform: (EffectGroupState) -> EffectGroupState) throws {
        for index in try resolve(target) {
            if compiled.requiresPixelEffect { pixels[index] = transform(pixels[index]) } else { groups[index] = transform(groups[index]) }
        }
        if compiled.requiresPixelEffect { syncGroupPreview() }
    }

    private mutating func resolve(_ reference: EffectTargetReference) throws -> [Int] {
        switch reference {
        case .all, .allPixels: return compiled.requiresPixelEffect ? Array(pixels.indices) : Array(groups.indices)
        case let .group(expression):
            let index = kotlinRoundToInt(try number(expression)); guard (1...7).contains(index) else { throw rangeError() }
            return compiled.requiresPixelEffect ? Array(((index - 1) * 6)..<(index * 6)) : [index - 1]
        case let .pixel(group, pixel):
            guard compiled.requiresPixelEffect else { throw runtime(.pixelModeRequired) }
            let g = kotlinRoundToInt(try number(group)), p = kotlinRoundToInt(try number(pixel));
            guard (1...7).contains(g), (1...6).contains(p) else { throw rangeError() }; return [(g - 1) * 6 + p - 1]
        case let .pixelAt(expression):
            guard compiled.requiresPixelEffect else { throw runtime(.pixelModeRequired) }
            let index = kotlinRoundToInt(try number(expression));
            guard (1...EffectGeometry.pixelCount).contains(index) else { throw rangeError() }; return [index - 1]
        case let .value(expression):
            guard case let .target(target) = try evaluate(expression) else { throw runtime(.targetTypeMismatch) }
            return try resolve(.fixed(target))
        }
    }

    private mutating func syncGroupPreview() {
        for index in 0..<7 {
            let source = pixels[index * 6]; groups[index].hue = source.hue; groups[index].saturation = source.saturation;
            groups[index].value = source.value; groups[index].innerMode = 1; groups[index].innerParameter = 0
        }
    }
    private func pixelRGB(_ state: EffectGroupState) -> EffectRGB {
        let colour = state;
        let hue = Double(wrap(colour.hue)), saturation = Double(colour.saturation.clamped(to: 0...255)) / 255,
            value = Double(colour.value.clamped(to: 0...255)) / 255, chroma = value * saturation,
            x = chroma * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1)), offset = value - chroma
        ;
        let components: (Double, Double, Double) =
            switch hue {
            case ..<60: (chroma, x, 0);
            case ..<120: (x, chroma, 0);
            case ..<180: (0, chroma, x);
            case ..<240: (0, x, chroma);
            case ..<300: (x, 0, chroma);
            default: (chroma, 0, x)
            }
        return EffectRGB(
            clampingRed: kotlinRoundToInt((components.0 + offset) * 255), green: kotlinRoundToInt((components.1 + offset) * 255),
            blue: kotlinRoundToInt((components.2 + offset) * 255))
    }
    private func groupProperty(_ state: EffectGroupState, _ property: EffectGroupProperty) -> Double {
        switch property {
        case .hue: Double(state.hue);
        case .saturation: Double(state.saturation);
        case .value: Double(state.value);
        case .mode: Double(state.innerMode)
        }
    }
    private mutating func number(_ expression: EffectExpression) throws -> Double {
        guard case let .number(value) = try evaluate(expression) else { throw runtime(.expectedNumber) }; return value
    }
    private mutating func boolean(_ expression: EffectExpression) throws -> Bool {
        guard case let .boolean(value) = try evaluate(expression) else { throw runtime(.expectedBoolean) }; return value
    }
    private mutating func colour(_ expression: EffectExpression) throws -> EffectColour {
        guard case let .colour(value) = try evaluate(expression) else { throw runtime(.expectedColour) }; return value
    }
    private mutating func duration(_ expression: EffectExpression) throws -> Int64 {
        min(600_000, max(50, kotlinRoundToLong(try number(expression))))
    }

    /// Kotlin/JVM `roundToInt` is `floor(x + 0.5)` with 32-bit saturation.
    /// Swift's default rounding instead sends negative ties away from zero and
    /// converting a huge finite `Double` traps, so neither behavior is usable.
    private func kotlinRoundToInt(_ value: Double) -> Int {
        if value >= Double(Int32.max) { return Int(Int32.max) }
        if value <= Double(Int32.min) { return Int(Int32.min) }
        return Int(floor(value + 0.5))
    }

    private func kotlinRoundToLong(_ value: Double) -> Int64 {
        if value >= Double(Int64.max) { return Int64.max }
        if value <= Double(Int64.min) { return Int64.min }
        return Int64(floor(value + 0.5))
    }
    private mutating func pushSequence(_ operations: [EffectOperation]) {
        stack.append(contentsOf: operations.reversed().map(RuntimeItem.execute))
    }
    private mutating func nextLoopID(_ blockID: String) -> String { defer { loopSerial += 1 }; return "\(blockID):\(loopSerial)" }
    private func finite(_ value: Double) throws -> Double { guard value.isFinite else { throw runtime(.nonFiniteNumber) }; return value }
    private func divide(_ lhs: Double, _ rhs: Double) throws -> Double {
        guard rhs != 0 else { throw runtime(.divisionByZero) }; return lhs / rhs
    }
    private func modulo(_ lhs: Double, _ rhs: Double) throws -> Double {
        guard rhs != 0 else { throw runtime(.divisionByZero) }; return lhs.truncatingRemainder(dividingBy: rhs)
    }
    private func numericComparison(_ lhs: EffectValue, _ rhs: EffectValue, _ comparator: (Double, Double) -> Bool) throws -> Bool {
        guard case let .number(left) = lhs, case let .number(right) = rhs else { throw runtime(.expectedNumber) };
        return comparator(left, right)
    }
    private func runtime(_ code: EffectRuntimeFailureCode, context: String? = nil) -> EffectRuntimeError {
        .execution(code: code, context: context)
    }
    private func rangeError() -> EffectRuntimeError { runtime(.targetOutOfRange) }
    private func wrap(_ value: Int) -> Int { let remainder = value % 360; return remainder < 0 ? remainder + 360 : remainder }
    private func target(_ index: Int) -> EffectTarget? {
        switch index {
        case 1: .group1;
        case 2: .group2;
        case 3: .group3;
        case 4: .group4;
        case 5: .group5;
        case 6: .group6;
        case 7: .group7;
        default: nil
        }
    }
    private func elementType(_ type: EffectValueType) -> EffectValueType? {
        switch type {
        case .numberList: .number;
        case .booleanList: .boolean;
        case .colourList: .colour;
        case .targetList: .target;
        default: nil
        }
    }
    private func defaultValue(_ type: EffectValueType) -> EffectValue {
        switch type {
        case .number: .number(0);
        case .boolean: .boolean(false);
        case .colour: .colour(EffectColour(hue: 0, saturation: 0, value: 255));
        case .target: .target(.all);
        case .numberList: .list(elementType: .number, values: []);
        case .booleanList: .list(elementType: .boolean, values: []);
        case .colourList: .list(elementType: .colour, values: []);
        case .targetList: .list(elementType: .target, values: [])
        }
    }
}

private extension Float {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
