import Foundation
import Testing

@testable import MauryaEffects

struct EffectScriptCompilerTests {
    struct Golden: Sendable {
        let name: String
        let source: String
        let expectedBlocks: Int?
    }

    @Test("Android functional syntax compiles", arguments: goldenPrograms)
    func androidFunctionalGolden(_ fixture: Golden) throws {
        let compiled = try EffectScriptCompiler.compile(fixture.source)
        #expect(compiled.operations.isEmpty == false, Comment(rawValue: fixture.name))
        if let expectedBlocks = fixture.expectedBlocks {
            #expect(compiled.blockCount == expectedBlocks, Comment(rawValue: fixture.name))
        }
        #expect(compiled.astSHA256.count == 64)
    }

    @Test func groupPixelAndAllTargetsExecuteWithAndroidIndexing() throws {
        let compiled = try EffectScriptCompiler.compile(
            ##"effect "pixels" { all.color("#000000"); pixel(2, 3).color("#FF0000"); pixelAt(42).color("#0000FF"); wait(100ms); }"##)
        var interpreter = try EffectInterpreter(compiled, initialGroups: groups())
        let frame = try interpreter.frame(at: 0)
        let pixels = try #require(frame.pixels)
        #expect(pixels[8] == (try EffectRGB(red: 255, green: 0, blue: 0)))
        #expect(pixels[41] == (try EffectRGB(red: 0, green: 0, blue: 255)))
    }

    @Test func variablesListsBuiltinsAndRuntimeInputsMatchAndroidAST() throws {
        let source =
            ##"effect "algorithms" { let palette: color[] = ["#FF0000", "#00FF00", "#0000FF"]; seedRandom(410); for (i from 0 to 6 step 1) { group(i + 1).color(mixHsv(palette[i % palette.length], complement(palette[i % palette.length]), smoothstep(0, 1, i / 6))); } all.hsv(sensor.heading + audio.bass * 120, 255, clamp(audio.level * 255, 0, 255)); wait(100ms); }"##
        let compiled = try EffectScriptCompiler.compile(source)
        #expect(compiled.variables["palette"] == .colourList)
        #expect(compiled.variables["i"] == .number)
        #expect(compiled.requiredInputs == [.sensorHeading, .audioBass, .audioLevel])
    }

    @Test func typedValueAndFlowFunctionsExecute() throws {
        let source =
            ##"fn palette(number index): color { let colors: color[] = ["#FF0000", "#00FF00", "#0000FF"]; return colors[index % colors.length]; } fn pulse(target lamp, color c, number duration) { lamp.mode(STROBE, 180); lamp.color(c); wait(duration); lamp.mode(STEADY, 0); } effect "functions" { pulse(group(4), palette(2), 500ms); wait(100ms); }"##
        let compiled = try EffectScriptCompiler.compile(source)
        #expect(Set(compiled.functions.keys) == ["palette", "pulse"])
        var interpreter = try EffectInterpreter(compiled, initialGroups: groups())
        #expect(try interpreter.frame(at: 250).groups[3].hue == 240)
        #expect(try interpreter.frame(at: 550).groups[3].innerMode == 1)
    }

    @Test func sourceLocationsAndQuickFixSurviveSemanticCompilation() {
        let source = ##"effect "bad" { forever { all.color("#FF0000"); wait(2s); all.color("#0000FF"); } }"##
        do {
            _ = try EffectScriptCompiler.compile(source)
            Issue.record("Expected loop-tail observability diagnostic")
        } catch let error as EffectCompileError {
            let issue = error.issues.first
            #expect(issue?.code == "EFFECT_STATE_NOT_OBSERVABLE")
            #expect(issue?.quickFixWaitMilliseconds == 2_000)
            #expect((issue?.sourceStart ?? -1) >= 0)
            #expect((issue?.sourceEnd ?? 0) > (issue?.sourceStart ?? 0))
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test("Unsupported and malicious syntax is rejected", arguments: rejectedSources)
    func unsupportedSyntaxNeverSilentlySucceeds(_ source: String) {
        #expect(throws: EffectCompileError.self) { try EffectScriptCompiler.compile(source) }
    }

    @Test func sourceAndListLimitsAreEnforced() {
        let huge = "effect \"x\" { wait(1ms); }" + String(repeating: " ", count: EffectScriptCompiler.maximumSourceBytes)
        #expect(throws: EffectCompileError.self) { try EffectScriptCompiler.compile(huge) }
        let values = (0...42).map(String.init).joined(separator: ",")
        #expect(throws: EffectCompileError.self) {
            try EffectScriptCompiler.compile("effect \"x\" { let v: number[] = [\(values)]; wait(1ms); }")
        }
    }

    @Test func canonicalIdentityIsStableAndSourceSensitive() throws {
        let first = try EffectScriptCompiler.compile(##"effect "x" { all.color("#FF0000"); wait(100ms); }"##)
        let same = try EffectScriptCompiler.compile(##"effect "x" { all.color("#FF0000"); wait(100ms); }"##)
        let relocated = try EffectScriptCompiler.compile(
            "// source spans are canonical\neffect \"x\" { all.color(\"#FF0000\"); wait(100ms); }")
        let changed = try EffectScriptCompiler.compile(##"effect "x" { all.color("#00FF00"); wait(100ms); }"##)
        #expect(first.astSHA256 == same.astSHA256)
        #expect(first.astSHA256 != relocated.astSHA256)
        #expect(first.astSHA256 != changed.astSHA256)
        #expect(EffectCompiler.canonicalJSON(first) == EffectCompiler.canonicalJSON(same))
    }

    @Test func formatterRoundTripPreservesExecutableSemantics() throws {
        let source =
            ##"fn pick(number i): color { let p: color[] = ["#FF0000", "#00FF00", "#0000FF"]; return p[i % p.length]; } effect "round trip" { let n = 2; repeat(2) { group(n).color(pick(n)); n += 1; wait(50ms); } }"##
        let first = try EffectScriptCompiler.compile(source)
        let formatted = EffectScriptFormatter.fromCompiled("round trip", first)
        let second = try EffectScriptCompiler.compile(formatted)
        var lhs = try EffectInterpreter(first, initialGroups: groups())
        var rhs = try EffectInterpreter(second, initialGroups: groups())
        #expect(try lhs.frame(at: 100).groups == rhs.frame(at: 100).groups)
        #expect(first.functions.keys == second.functions.keys)
    }

    private func groups() -> [EffectGroupState] { (0..<7).map { _ in EffectGroupState() } }

    private static let goldenPrograms: [Golden] = [
        .init(
            name: "colour-wait-fade",
            source:
                ##"effect "colors" { all.color("#FF0000"); wait(500ms); all.fade("#00FF00", 1500ms); all.fade(hsv(240,255,255), 1500ms); }"##,
            expectedBlocks: nil),
        .init(
            name: "if-else",
            source:
                ##"effect "if" { let hue: number = 12; if (hue >= 10 && hue != 20) { all.hsv(hue,255,255); } else { all.color("#000000"); } wait(100ms); }"##,
            expectedBlocks: nil),
        .init(
            name: "while-break",
            source:
                ##"effect "while" { let value = 0; while (value < 10) { value += 1; if (value == 5) { break; } continue; } wait(100ms); }"##,
            expectedBlocks: nil),
        .init(
            name: "repeat-continue",
            source:
                ##"effect "repeat" { let value = 0; repeat(7) { value += 1; if (value == 3) { continue; } all.hsv(value * 30,255,255); wait(50ms); } }"##,
            expectedBlocks: nil),
        .init(
            name: "c-for", source: ##"effect "for" { for (let i = 1; i <= 42; i += 1) { pixelAt(i).hsv(i * 9,255,255); } wait(50ms); }"##,
            expectedBlocks: nil),
        .init(
            name: "noise-wave",
            source:
                ##"effect "wave" { forever { all.hsv(noise1D(time.cycle(2s) * 8,17) * 359,255,sineWave(2s,0.25) * 255); wait(100ms); } }"##,
            expectedBlocks: nil),
    ]

    private static let rejectedSources = [
        "effect \"x\" { unknown(1); }",
        "effect \"x\" { all.sparkle(1); }",
        "effect \"x\" { break; }",
        "effect \"x\" { let x: bool = 1; wait(1ms); }",
        "effect \"x\" { let x = [1, true]; wait(1ms); }",
        "effect \"x\" { all.color(\"#GG0000\"); }",
        "effect \"x\" { wait(1ms); } trailing",
        "effect \"x\" { /* unterminated",
        "fn bad(number x): number { return bad(x); } effect \"x\" { wait(1ms); }",
    ]
}
