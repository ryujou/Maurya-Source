import Foundation
import Testing

@testable import MauryaEffects

struct EffectPatternMathTests {
    private struct SharedFixture: Decodable {
        let schemaVersion: Int
        let numberVectors: [NumberVector]
        let patternVectors: [PatternVector]
    }

    private struct NumberVector: Decodable {
        let function: BuiltinFunction
        let arguments: [Double]
        let elapsedMilliseconds: Int64
        let expected: Double
        let tolerance: Double
    }

    private struct PatternVector: Decodable {
        let operation: String
        let input: [Int]
        let shift: Int?
        let expected: [Int]
    }

    @Test
    func consumesSameAlgorithmFixtureAsAndroid() throws {
        let fixture = try JSONDecoder().decode(SharedFixture.self, from: Data(contentsOf: Self.fixtureURL))
        #expect(fixture.schemaVersion == 1)
        for vector in fixture.numberVectors {
            let actual = try EffectMath.number(
                vector.function,
                arguments: vector.arguments,
                elapsedMilliseconds: vector.elapsedMilliseconds
            )
            #expect(abs(actual - vector.expected) <= vector.tolerance)
        }
        for vector in fixture.patternVectors {
            let actual: [Int] =
                switch vector.operation {
                case "MIRROR": EffectPatternMath.mirror(vector.input)
                case "ROTATE": EffectPatternMath.rotate(vector.input, shift: try #require(vector.shift))
                case "CENTER_SPREAD": try EffectPatternMath.centerSpread(vector.input)
                case "CENTER_CONTRACT": try EffectPatternMath.centerContract(vector.input)
                default: try #require(nil as [Int]?, "Unknown shared pattern operation")
                }
            #expect(actual == vector.expected)
        }
    }

    @Test
    func sevenGroupMirrorMatchesAndroidExample() {
        let source = [0, 1, 2, 3, 4, 5, 6]
        #expect(EffectPatternMath.mirror(source) == [0, 1, 2, 3, 2, 1, 0])
    }

    @Test(arguments: [
        (shift: 1, expected: [6, 0, 1, 2, 3, 4, 5]),
        (shift: -1, expected: [1, 2, 3, 4, 5, 6, 0]),
        (shift: 8, expected: [6, 0, 1, 2, 3, 4, 5]),
    ])
    func rotationUsesPositiveModulo(_ fixture: (shift: Int, expected: [Int])) {
        #expect(EffectPatternMath.rotate([0, 1, 2, 3, 4, 5, 6], shift: fixture.shift) == fixture.expected)
    }

    @Test
    func centerOrdersMatchAndroidInterpreter() throws {
        let source = [0, 1, 2, 3, 4, 5, 6]
        #expect(try EffectPatternMath.centerSpread(source) == [3, 2, 4, 1, 5, 0, 6])
        #expect(try EffectPatternMath.centerContract(source) == [0, 6, 1, 5, 2, 4, 3])
    }

    @Test
    func centerPatternsRejectNonSevenLists() {
        #expect(throws: EffectRuntimeError.patternRequiresSevenValues(actual: 2)) {
            try EffectPatternMath.centerSpread([1, 2])
        }
    }

    @Test
    func generatedChaseMatchesAndroidRemainderAndClampSemantics() throws {
        #expect(EffectPatternMath.chase(progress: 0) == [1, 0, 0, 0, 0, 0, 0])
        #expect(EffectPatternMath.chase(progress: 0.5) == [0, 0, 0, 1, 0, 0, 0])
        #expect(EffectPatternMath.chase(progress: -0.01) == [1, 0, 0, 0, 0, 0, 0])
        #expect(EffectPatternMath.chase(progress: 1) == [1, 0, 0, 0, 0, 0, 0])

        let compiled = try EffectScriptCompiler.compile(
            """
            effect "negative chase" {
                let values: number[] = chase(-0.01);
                allPixels.hsv(0, 0, 0);
                for (i from 0 to 6 step 1) {
                    pixelAt(i + 1).hsv(0, 255, values[i] * 255);
                }
                wait(1s);
            }
            """
        )
        var interpreter = try EffectInterpreter(
            compiled,
            initialGroups: Array(repeating: EffectGroupState(), count: EffectGeometry.groupCount)
        )
        let pixels = try #require(interpreter.frame(at: 0).pixels)
        let actualBytes = Data(
            pixels.flatMap {
                [UInt8(clamping: $0.red), UInt8(clamping: $0.green), UInt8(clamping: $0.blue)]
            }
        )
        let expectedBytes = Data([255, 0, 0] + Array(repeating: 0, count: EffectGeometry.pixelCount * 3 - 3))
        #expect(actualBytes == expectedBytes)
    }

    @Test
    func generatedWaveHasSevenBoundedValues() {
        let values = EffectPatternMath.wave(progress: 0.25)
        #expect(values.count == 7)
        #expect(values.allSatisfy { (0...1).contains($0) })
        #expect(abs(values[0] - 1) < 1e-12)
    }

    @Test
    func randomColourConsumesThreeAndroidCompatibleDraws() {
        var generator = DeterministicRandom(seed: 42)
        #expect(
            EffectMath.randomColour(using: &generator)
                == EffectColour(hue: 0, saturation: 226, value: 229)
        )
    }

    @Test
    func paletteInterpolationUsesRGBSpace() throws {
        let result = try EffectMath.paletteColour(
            [
                .init(hue: 0, saturation: 255, value: 255),
                .init(hue: 240, saturation: 255, value: 255),
            ],
            position: 0.5
        )
        #expect(result == EffectColour(hue: 300, saturation: 255, value: 127))
    }

    @Test
    func emptyPaletteIsRejected() {
        #expect(throws: EffectRuntimeError.emptyPalette) {
            try EffectMath.paletteColour([], position: 0.5)
        }
    }

    private static let fixtureURL: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        return url.appending(path: "protocol/fixtures/effect-algorithms.json")
    }()
}
