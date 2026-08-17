import Foundation
import Testing

@testable import MauryaEffects

struct EffectMathTests {
    struct NumericFixture: Sendable {
        let function: BuiltinFunction
        let arguments: [Double]
        let elapsedMilliseconds: Int64
        let expected: Double
        let tolerance: Double

        init(
            _ function: BuiltinFunction,
            _ arguments: [Double],
            elapsedMilliseconds: Int64 = 0,
            expected: Double,
            tolerance: Double = 1e-12
        ) {
            self.function = function
            self.arguments = arguments
            self.elapsedMilliseconds = elapsedMilliseconds
            self.expected = expected
            self.tolerance = tolerance
        }
    }

    static let numericFixtures: [NumericFixture] = [
        .init(.absolute, [-3.5], expected: 3.5),
        .init(.minimum, [2, -1], expected: -1),
        .init(.maximum, [2, -1], expected: 2),
        .init(.clamp, [5, 4, 1], expected: 4),
        .init(.power, [2, 8], expected: 256),
        .init(.round, [2.5], expected: 2),
        .init(.round, [3.5], expected: 4),
        .init(.floor, [-1.2], expected: -2),
        .init(.ceil, [-1.2], expected: -1),
        .init(.squareRoot, [81], expected: 9),
        .init(.logarithm, [Foundation.exp(2)], expected: 2),
        .init(.sine, [.pi / 2], expected: 1),
        .init(.cosine, [.pi], expected: -1),
        .init(.radians, [180], expected: .pi),
        .init(.degrees, [.pi], expected: 180),
        .init(.map, [5, 0, 10, 0, 100], expected: 50),
        .init(.map, [5, 1, 1, 7, 9], expected: 7),
        .init(.lerp, [10, 20, -1], expected: 10),
        .init(.lerp, [10, 20, 2], expected: 20),
        .init(.smoothstep, [0, 1, 0.5], expected: 0.5),
        .init(.smootherstep, [0, 1, 0.5], expected: 0.5),
        .init(.easeIn, [0.5], expected: 0.25),
        .init(.easeOut, [0.5], expected: 0.75),
        .init(.easeInOut, [0.25], expected: 0.0625),
        .init(.easeInOut, [0.75], expected: 0.9375),
        .init(.sineWave, [1_000, 0], elapsedMilliseconds: 0, expected: 0.5),
        .init(.sineWave, [1_000, 0], elapsedMilliseconds: 250, expected: 1),
        .init(.triangleWave, [1_000, 0], elapsedMilliseconds: 0, expected: 0),
        .init(.sawWave, [1_000, 0], elapsedMilliseconds: 750, expected: 0.75),
        .init(.squareWave, [1_000, 0.25, 0], elapsedMilliseconds: 100, expected: 1),
        .init(.squareWave, [1_000, 0.25, 0], elapsedMilliseconds: 300, expected: 0),
        .init(.cycle, [1_000], elapsedMilliseconds: 250, expected: 0.25),
        .init(.beatPhase, [120], elapsedMilliseconds: 250, expected: 0.5),
        .init(.barPhase, [120, 4, 4], elapsedMilliseconds: 1_000, expected: 0.5),
        .init(.deadzone, [0.1, 0.2], expected: 0),
        .init(.deadzone, [0.6, 0.2], expected: 0.5),
        .init(.noise1D, [12, 7], expected: 0x1.dab034b642892p-1),
        .init(.noise1D, [12.01, 7], expected: 0x1.da941ec253112p-1),
        .init(.fbmNoise, [4.2, 4, 9], expected: 0x1.070b0f7357dc0p-1),
    ]

    @Test(arguments: numericFixtures)
    func pureNumericBuiltinsMatchAndroid(_ fixture: NumericFixture) throws {
        let actual = try EffectMath.number(
            fixture.function,
            arguments: fixture.arguments,
            elapsedMilliseconds: fixture.elapsedMilliseconds
        )
        #expect(abs(actual - fixture.expected) <= fixture.tolerance)
    }

    @Test
    func wavesNormalizeNegativePhaseLikeAndroid() throws {
        let value = try EffectMath.number(
            .sawWave,
            arguments: [1_000, -0.25],
            elapsedMilliseconds: 0
        )
        #expect(value == 0.75)
    }

    @Test
    func noiseIsContinuousAndBounded() throws {
        let first = try EffectMath.number(.noise1D, arguments: [12, 7], elapsedMilliseconds: 0)
        let adjacent = try EffectMath.number(.noise1D, arguments: [12.01, 7], elapsedMilliseconds: 0)
        let fbm = try EffectMath.number(.fbmNoise, arguments: [4.2, 4, 9], elapsedMilliseconds: 0)

        #expect(abs(first - adjacent) < 0.1)
        #expect((0...1).contains(fbm))
    }

    @Test
    func invalidMathArgumentsProduceTypedFailures() {
        #expect(throws: EffectRuntimeError.squareRootOfNegative) {
            try EffectMath.number(.squareRoot, arguments: [-1], elapsedMilliseconds: 0)
        }
        #expect(throws: EffectRuntimeError.logarithmOfNonPositive) {
            try EffectMath.number(.logarithm, arguments: [0], elapsedMilliseconds: 0)
        }
        #expect(throws: EffectRuntimeError.invalidNoiseOctaves) {
            try EffectMath.number(.fbmNoise, arguments: [1, 5, 0], elapsedMilliseconds: 0)
        }
        #expect(
            throws: EffectRuntimeError.insufficientArguments(
                function: .map,
                expected: 5,
                actual: 4
            )
        ) {
            try EffectMath.number(.map, arguments: [1, 2, 3, 4], elapsedMilliseconds: 0)
        }
        #expect(throws: EffectRuntimeError.unsupportedPureNumericBuiltin(.random)) {
            try EffectMath.number(.random, arguments: [], elapsedMilliseconds: 0)
        }
    }

    @Test
    func hsvMixUsesShortestHuePath() {
        let mixed = EffectMath.mixHSV(
            EffectColour(hue: 350, saturation: 255, value: 255),
            EffectColour(hue: 10, saturation: 255, value: 255),
            amount: 0.5
        )
        #expect(mixed == EffectColour(hue: 0, saturation: 255, value: 255))
    }

    @Test
    func primaryColourConversionsMatchAndroidTruncation() throws {
        #expect(EffectMath.rgbToHSV(red: 255, green: 0, blue: 0) == .init(hue: 0, saturation: 255, value: 255))
        #expect(EffectMath.rgbToHSV(red: 0, green: 255, blue: 0) == .init(hue: 120, saturation: 255, value: 255))
        #expect(EffectMath.rgbToHSV(red: 0, green: 0, blue: 255) == .init(hue: 240, saturation: 255, value: 255))
        let expectedRed = try EffectRGB(red: 255, green: 0, blue: 0)
        #expect(EffectMath.hsvToRGB(.init(hue: 0, saturation: 255, value: 255)) == expectedRed)
    }

    @Test
    func android39C5BBRoundTripUsesSameIntegerLoss() throws {
        let hsv = EffectMath.rgbToHSV(red: 57, green: 197, blue: 187)
        #expect(hsv == EffectColour(hue: 175, saturation: 181, value: 197))
        let expected = try EffectRGB(red: 57, green: 197, blue: 185)
        #expect(EffectMath.hsvToRGB(hsv) == expected)
    }

    @Test
    func colourAdjustmentsClampAndWrap() {
        let colour = EffectColour(hue: 350, saturation: 250, value: 5)
        #expect(EffectMath.complement(colour).hue == 170)
        #expect(EffectMath.rotateHue(colour, degrees: 20).hue == 10)
        #expect(EffectMath.adjustSaturation(colour, by: 20).saturation == 255)
        #expect(EffectMath.adjustValue(colour, by: -20).value == 0)
    }
}
