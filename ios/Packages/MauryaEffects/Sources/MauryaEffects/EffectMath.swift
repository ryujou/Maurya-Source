import Foundation

/// Pure, deterministic effect algorithms ported from Android `EffectMath`.
///
/// Stateful builtins and random draws belong to an interpreter-owned state
/// object and are deliberately not hidden in this stateless namespace.
public enum EffectMath: Sendable {
    public static func number(
        _ function: BuiltinFunction,
        arguments: [Double],
        elapsedMilliseconds: Int64
    ) throws -> Double {
        switch function {
        case .absolute:
            return abs(try argument(0, for: function, in: arguments))
        case .minimum:
            return Swift.min(
                try argument(0, for: function, in: arguments),
                try argument(1, for: function, in: arguments)
            )
        case .maximum:
            return Swift.max(
                try argument(0, for: function, in: arguments),
                try argument(1, for: function, in: arguments)
            )
        case .clamp:
            let value = try argument(0, for: function, in: arguments)
            let firstBound = try argument(1, for: function, in: arguments)
            let secondBound = try argument(2, for: function, in: arguments)
            return value.clamped(
                to: Swift.min(firstBound, secondBound)...Swift.max(firstBound, secondBound)
            )
        case .power:
            return Foundation.pow(
                try argument(0, for: function, in: arguments),
                try argument(1, for: function, in: arguments)
            )
        case .round:
            return try argument(0, for: function, in: arguments).rounded(.toNearestOrEven)
        case .floor:
            return Foundation.floor(try argument(0, for: function, in: arguments))
        case .ceil:
            return Foundation.ceil(try argument(0, for: function, in: arguments))
        case .squareRoot:
            let value = try argument(0, for: function, in: arguments)
            guard value >= 0 else { throw EffectRuntimeError.squareRootOfNegative }
            return Foundation.sqrt(value)
        case .logarithm:
            let value = try argument(0, for: function, in: arguments)
            guard value > 0 else { throw EffectRuntimeError.logarithmOfNonPositive }
            return Foundation.log(value)
        case .sine:
            return Foundation.sin(try argument(0, for: function, in: arguments))
        case .cosine:
            return Foundation.cos(try argument(0, for: function, in: arguments))
        case .radians:
            return try argument(0, for: function, in: arguments) * .pi / 180
        case .degrees:
            return try argument(0, for: function, in: arguments) * 180 / .pi
        case .map:
            let value = try argument(0, for: function, in: arguments)
            let inputStart = try argument(1, for: function, in: arguments)
            let inputEnd = try argument(2, for: function, in: arguments)
            let outputStart = try argument(3, for: function, in: arguments)
            let outputEnd = try argument(4, for: function, in: arguments)
            let span = inputEnd - inputStart
            return span == 0
                ? outputStart
                : outputStart + (value - inputStart) / span * (outputEnd - outputStart)
        case .lerp:
            return lerp(
                try argument(0, for: function, in: arguments),
                try argument(1, for: function, in: arguments),
                amount: try argument(2, for: function, in: arguments)
            )
        case .smoothstep:
            let edge0 = try argument(0, for: function, in: arguments)
            let edge1 = try argument(1, for: function, in: arguments)
            let value = try argument(2, for: function, in: arguments)
            let span = edge1 - edge0
            let t = span == 0 ? 0 : ((value - edge0) / span).clamped(to: 0...1)
            return t * t * (3 - 2 * t)
        case .smootherstep:
            let edge0 = try argument(0, for: function, in: arguments)
            let edge1 = try argument(1, for: function, in: arguments)
            let value = try argument(2, for: function, in: arguments)
            let span = edge1 - edge0
            let t = span == 0 ? 0 : ((value - edge0) / span).clamped(to: 0...1)
            return t * t * t * (t * (t * 6 - 15) + 10)
        case .easeIn:
            return Foundation.pow(
                try argument(0, for: function, in: arguments).clamped(to: 0...1),
                2
            )
        case .easeOut:
            let t = try argument(0, for: function, in: arguments).clamped(to: 0...1)
            return 1 - Foundation.pow(1 - t, 2)
        case .easeInOut:
            let t = try argument(0, for: function, in: arguments).clamped(to: 0...1)
            return t < 0.5
                ? 4 * t * t * t
                : 1 - Foundation.pow(-2 * t + 2, 3) / 2
        case .sineWave:
            return
                (Foundation.sin(
                    try waveAngle(elapsedMilliseconds, arguments, function: function)
                ) + 1) / 2
        case .triangleWave:
            let progress = try waveProgress(
                elapsedMilliseconds,
                arguments,
                function: function
            )
            return 1 - abs(2 * progress - 1)
        case .sawWave:
            return try waveProgress(elapsedMilliseconds, arguments, function: function)
        case .squareWave:
            let period = try positive(
                try argument(0, for: function, in: arguments),
                name: "period"
            )
            let duty = arguments.indices.contains(1) ? arguments[1].clamped(to: 0...1) : 0.5
            let phase = arguments.indices.contains(2) ? arguments[2] : 0
            let progress = normalizedUnit(Double(elapsedMilliseconds) / period + phase)
            return progress < duty ? 1 : 0
        case .cycle:
            return try cycle(
                elapsedMilliseconds,
                periodMilliseconds: argument(0, for: function, in: arguments)
            )
        case .beatPhase:
            let beatsPerMinute = try positive(
                try argument(0, for: function, in: arguments),
                name: "BPM"
            )
            return try cycle(elapsedMilliseconds, periodMilliseconds: 60_000 / beatsPerMinute)
        case .barPhase:
            let beatsPerMinute = try positive(
                try argument(0, for: function, in: arguments),
                name: "BPM"
            )
            let beatsPerBar = try positive(
                arguments.indices.contains(1) ? arguments[1] : 4,
                name: "beatsPerBar"
            )
            let beatUnit = try positive(
                arguments.indices.contains(2) ? arguments[2] : 4,
                name: "beatUnit"
            )
            return try cycle(
                elapsedMilliseconds,
                periodMilliseconds: 60_000 / beatsPerMinute * beatsPerBar * 4 / beatUnit
            )
        case .deadzone:
            let input = try argument(0, for: function, in: arguments)
            let threshold = abs(try argument(1, for: function, in: arguments))
            guard abs(input) > threshold else { return 0 }
            let magnitude = (abs(input) - threshold) / Swift.max(1 - threshold, 1e-9)
            return input < 0 ? -magnitude : magnitude
        case .noise1D:
            let x = try argument(0, for: function, in: arguments)
            let seed = kotlinInt64(arguments.indices.contains(1) ? arguments[1] : 0)
            return valueNoise(x, seed: seed)
        case .fbmNoise:
            let x = try argument(0, for: function, in: arguments)
            let rawOctaves = arguments.indices.contains(1) ? arguments[1] : 3
            let truncatedOctaves = rawOctaves.rounded(.towardZero)
            guard truncatedOctaves.isFinite,
                (1...4).contains(truncatedOctaves)
            else {
                throw EffectRuntimeError.invalidNoiseOctaves
            }
            let octaves = Int(truncatedOctaves)
            let seed = kotlinInt64(arguments.indices.contains(2) ? arguments[2] : 0)
            var frequency = 1.0
            var amplitude = 0.5
            var sum = 0.0
            var weight = 0.0
            for octave in 0..<octaves {
                let octaveSeed = seed &+ Int64(octave * 1_013)
                sum += valueNoise(x * frequency, seed: octaveSeed) * amplitude
                weight += amplitude
                frequency *= 2
                amplitude *= 0.5
            }
            return sum / Swift.max(weight, 1e-9)
        case .random, .smooth, .hysteresis, .peakHold, .debounce,
            .risingEdge, .fallingEdge, .rgb, .red, .green, .blue,
            .hue, .saturation, .value, .mixRGB, .mixHSV, .complement,
            .rotateHue, .adjustSaturation, .adjustValue, .paletteColour,
            .randomColour, .listLength, .mirror, .rotatePattern,
            .centerSpread, .centerContract, .chase, .wavePattern:
            throw EffectRuntimeError.unsupportedPureNumericBuiltin(function)
        }
    }

    public static func lerp(_ start: Double, _ end: Double, amount: Double) -> Double {
        start + (end - start) * amount.clamped(to: 0...1)
    }

    public static func mixHSV(
        _ first: EffectColour,
        _ second: EffectColour,
        amount: Double
    ) -> EffectColour {
        let t = amount.clamped(to: 0...1)
        let hueDelta = positiveModulo(second.hue - first.hue + 540, divisor: 360) - 180
        return EffectColour(
            hue: wrapHue(first.hue + Int(Double(hueDelta) * t)),
            saturation: Int(
                lerp(Double(first.saturation), Double(second.saturation), amount: t)
            ).clamped(to: 0...255),
            value: Int(
                lerp(Double(first.value), Double(second.value), amount: t)
            ).clamped(to: 0...255)
        )
    }

    public static func mixRGB(
        _ first: EffectColour,
        _ second: EffectColour,
        amount: Double
    ) -> EffectColour {
        let firstRGB = hsvToRGB(first)
        let secondRGB = hsvToRGB(second)
        let t = amount.clamped(to: 0...1)
        return rgbToHSV(
            red: Int(lerp(Double(firstRGB.red), Double(secondRGB.red), amount: t)),
            green: Int(lerp(Double(firstRGB.green), Double(secondRGB.green), amount: t)),
            blue: Int(lerp(Double(firstRGB.blue), Double(secondRGB.blue), amount: t))
        )
    }

    public static func rgbToHSV(red: Int, green: Int, blue: Int) -> EffectColour {
        let red = Double(red.clamped(to: 0...255)) / 255
        let green = Double(green.clamped(to: 0...255)) / 255
        let blue = Double(blue.clamped(to: 0...255)) / 255
        let high = Swift.max(red, Swift.max(green, blue))
        let low = Swift.min(red, Swift.min(green, blue))
        let delta = high - low
        var hue: Double
        if delta == 0 {
            hue = 0
        } else if high == red {
            hue = 60 * ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if high == green {
            hue = 60 * ((blue - red) / delta + 2)
        } else {
            hue = 60 * ((red - green) / delta + 4)
        }
        if hue < 0 { hue += 360 }
        return EffectColour(
            hue: positiveModulo(Int(hue), divisor: 360),
            saturation: Int(high == 0 ? 0 : delta / high * 255).clamped(to: 0...255),
            value: Int(high * 255).clamped(to: 0...255)
        )
    }

    public static func hsvToRGB(_ colour: EffectColour) -> EffectRGB {
        let hue = Double(wrapHue(colour.hue))
        let saturation = Double(colour.saturation.clamped(to: 0...255)) / 255
        let value = Double(colour.value.clamped(to: 0...255)) / 255
        let chroma = value * saturation
        let x = chroma * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1))
        let offset = value - chroma
        let components: (Double, Double, Double)
        switch hue {
        case ..<60: components = (chroma, x, 0)
        case ..<120: components = (x, chroma, 0)
        case ..<180: components = (0, chroma, x)
        case ..<240: components = (0, x, chroma)
        case ..<300: components = (x, 0, chroma)
        default: components = (chroma, 0, x)
        }
        return EffectRGB(
            clampingRed: Int((components.0 + offset) * 255),
            green: Int((components.1 + offset) * 255),
            blue: Int((components.2 + offset) * 255)
        )
    }

    public static func complement(_ colour: EffectColour) -> EffectColour {
        EffectColour(
            hue: wrapHue(colour.hue + 180),
            saturation: colour.saturation,
            value: colour.value
        )
    }

    public static func rotateHue(_ colour: EffectColour, degrees: Int) -> EffectColour {
        EffectColour(
            hue: wrapHue(colour.hue + degrees),
            saturation: colour.saturation,
            value: colour.value
        )
    }

    public static func adjustSaturation(_ colour: EffectColour, by amount: Int) -> EffectColour {
        EffectColour(
            hue: colour.hue,
            saturation: (colour.saturation + amount).clamped(to: 0...255),
            value: colour.value
        )
    }

    public static func adjustValue(_ colour: EffectColour, by amount: Int) -> EffectColour {
        EffectColour(
            hue: colour.hue,
            saturation: colour.saturation,
            value: (colour.value + amount).clamped(to: 0...255)
        )
    }

    public static func paletteColour(
        _ palette: [EffectColour],
        position: Double
    ) throws -> EffectColour {
        guard palette.isEmpty == false else { throw EffectRuntimeError.emptyPalette }
        let scaledPosition = position.clamped(to: 0...1) * Double(palette.count - 1)
        let firstIndex = Int(Foundation.floor(scaledPosition))
        let secondIndex = Swift.min(firstIndex + 1, palette.count - 1)
        return mixRGB(
            palette[firstIndex],
            palette[secondIndex],
            amount: scaledPosition - Double(firstIndex)
        )
    }

    public static func random(
        from low: Double,
        through high: Double,
        using generator: inout DeterministicRandom
    ) -> Double {
        lerp(low, high, amount: generator.nextDouble())
    }

    public static func randomColour(
        using generator: inout DeterministicRandom
    ) -> EffectColour {
        EffectColour(
            hue: Int(generator.nextDouble() * 360) % 360,
            saturation: Int(180 + generator.nextDouble() * 75).clamped(to: 0...255),
            value: Int(200 + generator.nextDouble() * 55).clamped(to: 0...255)
        )
    }

    public static func wrapHue(_ value: Int) -> Int {
        positiveModulo(value, divisor: 360)
    }

    private static func argument(
        _ index: Int,
        for function: BuiltinFunction,
        in arguments: [Double]
    ) throws -> Double {
        guard arguments.indices.contains(index) else {
            throw EffectRuntimeError.insufficientArguments(
                function: function,
                expected: index + 1,
                actual: arguments.count
            )
        }
        return arguments[index]
    }

    private static func waveAngle(
        _ elapsedMilliseconds: Int64,
        _ arguments: [Double],
        function: BuiltinFunction
    ) throws -> Double {
        try waveProgress(elapsedMilliseconds, arguments, function: function) * .pi * 2
    }

    private static func waveProgress(
        _ elapsedMilliseconds: Int64,
        _ arguments: [Double],
        function: BuiltinFunction
    ) throws -> Double {
        let period = try positive(
            try argument(0, for: function, in: arguments),
            name: "period"
        )
        let phase = arguments.indices.contains(1) ? arguments[1] : 0
        return normalizedUnit(Double(elapsedMilliseconds) / period + phase)
    }

    private static func cycle(
        _ elapsedMilliseconds: Int64,
        periodMilliseconds: Double
    ) throws -> Double {
        let period = try positive(periodMilliseconds, name: "period")
        return Double(elapsedMilliseconds).truncatingRemainder(dividingBy: period) / period
    }

    private static func positive(_ value: Double, name: String) throws -> Double {
        guard value.isFinite, value > 0 else {
            throw EffectRuntimeError.invalidPositiveArgument(name: name)
        }
        return value
    }

    private static func normalizedUnit(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 1)
        return (remainder + 1).truncatingRemainder(dividingBy: 1)
    }

    private static func valueNoise(_ x: Double, seed: Int64) -> Double {
        let floored = Foundation.floor(x)
        let left = kotlinInt64(floored)
        let t = x - floored
        let smooth = t * t * (3 - 2 * t)
        return lerp(
            hashNoise(index: left, seed: seed),
            hashNoise(index: left &+ 1, seed: seed),
            amount: smooth
        )
    }

    private static func hashNoise(index: Int64, seed: Int64) -> Double {
        let first: UInt64 = 0x9E37_79B9_7F4A_7C15
        let second: UInt64 = 0xBF58_476D_1CE4_E5B9
        let third: UInt64 = 0x94D0_49BB_1331_11EB
        var value = UInt64(bitPattern: index) &* first
        value = value &+ (UInt64(bitPattern: seed) &* second)
        value = (value ^ (value >> 30)) &* second
        value = (value ^ (value >> 27)) &* third
        value ^= value >> 31
        return Double(value >> 11) / 9_007_199_254_740_992
    }

    private static func kotlinInt64(_ value: Double) -> Int64 {
        guard value.isNaN == false else { return 0 }
        if value >= Double(Int64.max) { return .max }
        if value <= Double(Int64.min) { return .min }
        return Int64(value.rounded(.towardZero))
    }

    private static func positiveModulo(_ value: Int, divisor: Int) -> Int {
        let remainder = value % divisor
        return remainder < 0 ? remainder + divisor : remainder
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
