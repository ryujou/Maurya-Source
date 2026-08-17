import Testing

@testable import MauryaEffects

struct EffectCompilerParityTests {
    struct JVMNumberFixture: Sendable, CustomTestStringConvertible {
        let value: Double
        let canonical: String
        let hash: String
        var testDescription: String { canonical }
    }

    @Test(arguments: [
        JVMNumberFixture(value: 1e20, canonical: "1.0E20", hash: "b0518fde849b31feea2e7a9a5755fffe9e744fe7400091fa4962d7ae57468dd4"),
        JVMNumberFixture(value: 1e7, canonical: "1.0E7", hash: "17fe4592951f83314dc396ead4c3d9ba628ac763b78d6e92b2b683bda198b011"),
        JVMNumberFixture(value: 1e6, canonical: "1000000", hash: "09c33aab2a7d16a3583fb1637f62e487a4930cdb4f57e9b893361cc469a094cd"),
        JVMNumberFixture(value: 1e-3, canonical: "0.001", hash: "fae9c6a880ce6212e50453b6e5aa633219768e3987d04ad3523e2e685a325c4b"),
        JVMNumberFixture(value: 1e-4, canonical: "1.0E-4", hash: "8902215a6910949f03a701871781161189633804e72d75a1fa285540004df9e2"),
        JVMNumberFixture(value: 1e-7, canonical: "1.0E-7", hash: "44e2f7d004b40c74b3bb55a2f9672d74674c9dad85dc13e01de3eab867192c11"),
        JVMNumberFixture(value: -0.0, canonical: "-0", hash: "acd7006df54826c07be65580389e2f4cd7477fc7f78c5974f1d5b68b28bdcf96"),
        JVMNumberFixture(
            value: .greatestFiniteMagnitude, canonical: "1.7976931348623157E308",
            hash: "90b5881d13702c1fb575342c0ceeda917ccaa8e018e0cb6547eca17bdbd8ec10"),
        JVMNumberFixture(
            value: .leastNonzeroMagnitude, canonical: "4.9E-324", hash: "ddbb15730e32b12683b6ac5f9ac563bbdafe0a738597a492de495a31ee8e7ba8"),
        JVMNumberFixture(
            value: 9.007199254740992e15, canonical: "9.007199254740992E15",
            hash: "d218111005292f50d30cdf8d84fc6a72c702c7bb383d6f772f6d05f296c8cd20"),
        JVMNumberFixture(
            value: 1.2345678901234567e30, canonical: "1.2345678901234567E30",
            hash: "cae15e1d092731ae9e45f5a52503a70705d3c1d5040e55c5181d78d381e0e4de"),
    ])
    func extremeNumbersMatchJVMJSONObject(_ fixture: JVMNumberFixture) throws {
        let compiled = try EffectCompiler.compile(
            operations: [.wait(.number(fixture.value), blockID: "extreme")],
            nodeCount: 2
        )
        let expected =
            "{\"operations\":[{\"op\":\"wait\",\"blockId\":\"extreme\",\"ms\":{\"type\":\"number\",\"value\":\(fixture.canonical)}}],\"functions\":[]}"
        #expect(EffectCompiler.canonicalJSON(compiled) == expected)
        #expect(compiled.astSHA256 == fixture.hash)
    }

    @Test func canonicalJSONAndHashMatchAndroidByteForByte() throws {
        let compiled = try EffectCompiler.compile(
            operations: [.wait(.number(100), blockID: "w")],
            nodeCount: 2
        )
        let expected = #"{"operations":[{"op":"wait","blockId":"w","ms":{"type":"number","value":100}}],"functions":[]}"#
        #expect(EffectCompiler.canonicalJSON(compiled) == expected)
        #expect(compiled.astSHA256 == "55f014babeed054472f892a7f829e51512cd632e276756469adf595ac667532f")
    }

    @Test func canonicalJSONUsesAndroidFractionAndSlashEscaping() throws {
        let compiled = try EffectCompiler.compile(
            operations: [.wait(.number(0.5), blockID: "wait/path")],
            nodeCount: 2
        )
        #expect(
            EffectCompiler.canonicalJSON(compiled)
                == #"{"operations":[{"op":"wait","blockId":"wait/path","ms":{"type":"number","value":0.5}}],"functions":[]}"#)

        let negativeZero = try EffectCompiler.compile(
            operations: [.wait(.number(-0.0), blockID: "negative-zero")],
            nodeCount: 2
        )
        #expect(EffectCompiler.canonicalJSON(negativeZero).contains(#""value":-0"#))
    }

    @Test func canonicalFunctionsUseAndroidSortedArrayShape() throws {
        let first = EffectFunctionDefinition(
            name: "zeta",
            parameters: [.init(name: "x", variableID: "x-id", type: .number)],
            returnType: .number,
            operations: [],
            returnExpression: .variable(id: "x-id", type: .number)
        )
        let second = EffectFunctionDefinition(name: "alpha", operations: [.wait(.number(50), blockID: "f-wait")])
        let compiled = try EffectCompiler.compile(
            operations: [.wait(.number(100), blockID: "main-wait")],
            nodeCount: 3,
            functions: [first.name: first, second.name: second]
        )
        let canonical = EffectCompiler.canonicalJSON(compiled)
        #expect(canonical.contains(#""functions":[{"name":"alpha""#))
        #expect(
            canonical.contains(#"{"name":"zeta","parameters":[{"name":"x","variableId":"x-id","type":"NUMBER"}],"returnType":"NUMBER""#))
    }

    @Test func unreachableBlockAfterForeverIsRejectedLikeAndroid() {
        #expect(throws: EffectCompileError.self) {
            try EffectCompiler.compile(
                operations: [
                    .repeatLoop(count: nil, body: [.wait(.number(100), blockID: "inside")], blockID: "forever"),
                    .wait(.number(100), blockID: "unreachable"),
                ], nodeCount: 4)
        }
    }

    @Test func finiteZeroDurationTailHasAndroidDiagnostic() {
        do {
            _ = try EffectCompiler.compile(
                operations: [.setHSV(.all, h: .number(0), s: .number(255), v: .number(255), blockID: "tail")],
                nodeCount: 2
            )
            Issue.record("Expected invisible finite tail to be rejected")
        } catch let error as EffectCompileError {
            #expect(error.issues.map(\.code) == ["EFFECT_STATE_NOT_OBSERVABLE"])
            #expect(error.issues.first?.sourceID == "tail")
            #expect(error.issues.first?.quickFixWaitMilliseconds == 1_000)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func nestedProgramCalculatesAndroidDuration() throws {
        let json =
            #"{"blocks":{"languageVersion":0,"blocks":[{"type":"maurya_start","id":"s","next":{"block":{"type":"maurya_repeat","id":"r","fields":{"COUNT":3},"inputs":{"DO":{"block":{"type":"maurya_adjust_hsv","id":"a","fields":{"TARGET":"ALL","H":6,"S":0,"V":0},"next":{"block":{"type":"maurya_wait","id":"w","fields":{"DURATION":100,"UNIT":"MS"}}}}}}}}}]}}"#
        let compiled = try EffectCompiler.compile(blocklyJSON: json)
        #expect(compiled.blockCount == 4)
        #expect(compiled.estimatedDurationMilliseconds == 300)
    }

    @Test func infiniteLoopHasUnknownDuration() throws {
        let json =
            #"{"blocks":{"languageVersion":0,"blocks":[{"type":"maurya_start","id":"s","next":{"block":{"type":"maurya_forever","id":"f","inputs":{"DO":{"block":{"type":"maurya_wait","id":"w","fields":{"DURATION":100,"UNIT":"MS"}}}}}}}]}}"#
        #expect(try EffectCompiler.compile(blocklyJSON: json).estimatedDurationMilliseconds == nil)
    }

    @Test func orphanBlockIsRejected() {
        let json = #"{"blocks":{"blocks":[{"type":"maurya_start","id":"s"},{"type":"maurya_wait","id":"w"}]}}"#
        #expect(throws: EffectCompileError.self) { try EffectCompiler.compile(blocklyJSON: json) }
    }

    @Test func typedForLoopCalculatesFiniteDuration() throws {
        let json =
            #"{"variables":[{"name":"i","id":"var-i","type":"Number"}],"blocks":{"blocks":[{"type":"maurya_start","id":"start","next":{"block":{"type":"maurya_for","id":"for","fields":{"VAR":{"id":"var-i"}},"inputs":{"FROM":{"shadow":{"type":"math_number","fields":{"NUM":0}}},"TO":{"shadow":{"type":"math_number","fields":{"NUM":10}}},"BY":{"shadow":{"type":"math_number","fields":{"NUM":5}}},"DO":{"block":{"type":"maurya_wait_value","id":"wait","fields":{"UNIT":"MS"},"inputs":{"DURATION":{"shadow":{"type":"math_number","fields":{"NUM":100}}}}}}}}}}]}}"#
        let compiled = try EffectCompiler.compile(blocklyJSON: json)
        #expect(compiled.estimatedDurationMilliseconds == 300)
        #expect(compiled.variables["var-i"] == .number)
        #expect(EffectCompiler.canonicalJSON(compiled).contains(#""op":"for""#))
    }

    @Test func hugeFiniteForRangeSaturatesIterationEstimateWithoutTrapping() throws {
        let compiled = try EffectCompiler.compile(
            operations: [
                .forLoop(
                    variableID: "i",
                    from: .number(-1e308),
                    through: .number(1e308),
                    step: .number(1),
                    body: [.wait(.number(100), blockID: "wait")],
                    blockID: "for"
                )
            ],
            nodeCount: 2,
            variables: ["i": .number]
        )
        #expect(compiled.estimatedDurationMilliseconds == 100_000)
    }

    @Test func durationOverflowFailsClosedAsUnknownInsteadOfTrapping() throws {
        let addition = try EffectCompiler.compile(
            operations: [
                .wait(.number(1e308), blockID: "first"),
                .wait(.number(1e308), blockID: "second"),
            ],
            nodeCount: 2
        )
        #expect(addition.estimatedDurationMilliseconds == nil)

        let multiplication = try EffectCompiler.compile(
            operations: [
                .repeatLoop(
                    count: .number(1_000),
                    body: [.wait(.number(1e308), blockID: "wait")],
                    blockID: "repeat"
                )
            ],
            nodeCount: 2
        )
        #expect(multiplication.estimatedDurationMilliseconds == nil)
    }

    @Test func typedInputMismatchAndBreakOutsideLoopAreRejected() {
        let mismatch =
            #"{"variables":[{"id":"flag","type":"Boolean"}],"blocks":{"blocks":[{"type":"maurya_start","next":{"block":{"type":"maurya_wait_value","id":"w","inputs":{"DURATION":{"block":{"type":"maurya_var_get_boolean","fields":{"VAR":{"id":"flag"}}}}}}}}]}}"#
        let outside = #"{"blocks":{"blocks":[{"type":"maurya_start","next":{"block":{"type":"maurya_break","id":"b"}}}]}}"#
        #expect(throws: EffectCompileError.self) { try EffectCompiler.compile(blocklyJSON: mismatch) }
        #expect(throws: EffectCompileError.self) { try EffectCompiler.compile(blocklyJSON: outside) }
    }

    @Test func loopTailMutationHasAndroidDiagnosticAndQuickFix() {
        let operations: [EffectOperation] = [
            .repeatLoop(
                count: nil,
                body: [
                    .setHSV(.all, h: .number(0), s: .number(255), v: .number(255), blockID: "red"),
                    .wait(.number(2_000), blockID: "wait"),
                    .setHSV(.all, h: .number(240), s: .number(255), v: .number(255), blockID: "blue"),
                ])
        ]
        do {
            _ = try EffectCompiler.compile(operations: operations, nodeCount: 5)
            Issue.record("Expected observable-state validation failure")
        } catch let error as EffectCompileError {
            #expect(error.issues.first?.code == "EFFECT_STATE_NOT_OBSERVABLE")
            #expect(error.issues.first?.sourceID == "blue")
            #expect(error.issues.first?.quickFixWaitMilliseconds == 2_000)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

struct EffectInterpreterParityTests {
    @Test func jvmRoundToIntTiesAndFiniteSaturationMatchKotlin() throws {
        let operations: [EffectOperation] = [
            .setHSV(.all, h: .number(-1.5), s: .number(254.5), v: .number(1e308)),
            .adjustHSV(.all, dh: .number(-1.5), ds: .number(0), dv: .number(0)),
            .seedRandom(.number(1e308)),
            .wait(.number(1e308)),
        ]
        let compiled = try EffectCompiler.compile(operations: operations, nodeCount: 5)
        var interpreter = try EffectInterpreter(compiled, initialGroups: groups(hue: 0))
        let frame = try interpreter.frame(at: 0)
        // Kotlin: (-1.5).roundToInt() == -1, 254.5 -> 255, and huge
        // finite Double conversions saturate before the runtime clamps them.
        #expect(frame.groups[0].hue == 358)
        #expect(frame.groups[0].saturation == 255)
        #expect(frame.groups[0].value == 255)
        #expect(frame.waiting)
    }

    @Test func hugeFiniteDynamicTargetFailsTypedInsteadOfTrapping() throws {
        let compiled = try EffectCompiler.compile(
            operations: [
                .setHSV(
                    .pixelAt(
                        oneBasedIndex: .arithmetic(
                            .add,
                            .number(1e308),
                            .runtimeInput(.sensorMotion)
                        )),
                    h: .number(0),
                    s: .number(0),
                    v: .number(0)
                ),
                .wait(.number(50)),
            ], nodeCount: 3)
        var interpreter = try EffectInterpreter(compiled, initialGroups: groups(hue: 0))
        #expect(throws: EffectRuntimeError.self) { try interpreter.frame(at: 0) }
    }

    @Test func infiniteAdjustmentAccumulatesAtWaitBoundaries() throws {
        let compiled = try compile([
            .repeatLoop(
                count: nil,
                body: [
                    .adjustHSV(.all, dh: .number(6), ds: .number(0), dv: .number(0)),
                    .wait(.number(100)),
                ])
        ])
        var interpreter = try EffectInterpreter(compiled, initialGroups: groups(hue: 0, mode: 4))
        #expect(try interpreter.frame(at: 0).groups[0].hue == 6)
        #expect(try interpreter.frame(at: 99).groups[0].hue == 6)
        #expect(try interpreter.frame(at: 100).groups[0].hue == 12)
        let frame = try interpreter.frame(at: 1_000)
        #expect(frame.groups[0].hue == 66)
        #expect(frame.groups[0].innerMode == 1)
        #expect(frame.finished == false)
    }

    @Test func finiteFadeAppliesExactBoundaryColours() throws {
        let compiled = try compile([
            .setHSV(.all, h: .number(0), s: .number(255), v: .number(255)),
            .wait(.number(500)),
            .fadeHSV(.all, h: .number(120), s: .number(255), v: .number(255), duration: .number(1_500)),
            .fadeHSV(.all, h: .number(240), s: .number(255), v: .number(255), duration: .number(1_500)),
        ])
        var interpreter = try EffectInterpreter(compiled, initialGroups: groups(hue: 30))
        #expect(try interpreter.frame(at: 0).groups[0].hue == 0)
        #expect(try interpreter.frame(at: 499).waiting)
        #expect(try interpreter.frame(at: 1_250).groups[0].hue == 60)
        #expect(try interpreter.frame(at: 2_000).groups[0].hue == 120)
        let final = try interpreter.frame(at: 3_500)
        #expect(final.groups[0].hue == 240)
        #expect(final.finished)
    }

    @Test func forLoopUpdatesTypedVariableAtEveryYield() throws {
        let id = "hue-index"
        let operations: [EffectOperation] = [
            .forLoop(
                variableID: id, from: .number(0), through: .number(10), step: .number(5),
                body: [
                    .setHSV(.all, h: .variable(id: id, type: .number), s: .number(255), v: .number(255)),
                    .wait(.number(100)),
                ])
        ]
        let compiled = try EffectCompiler.compile(operations: operations, nodeCount: 4, variables: [id: .number])
        var interpreter = try EffectInterpreter(compiled, initialGroups: groups(hue: 30))
        #expect(try interpreter.frame(at: 0).groups[0].hue == 0)
        #expect(try interpreter.frame(at: 100).groups[0].hue == 5)
        #expect(try interpreter.frame(at: 200).groups[0].hue == 10)
        #expect(try interpreter.frame(at: 300).finished)
    }

    @Test func whileReadsVirtualGroupState() throws {
        let condition: EffectExpression = .comparison(.lessThan, .groupValue(zeroBasedGroup: 0, property: .value), .number(150))
        let compiled = try compile([
            .whileLoop(
                condition,
                body: [
                    .adjustHSV(.all, dh: .number(0), ds: .number(0), dv: .number(50)),
                    .wait(.number(100)),
                ])
        ])
        var interpreter = try EffectInterpreter(compiled, initialGroups: groups(hue: 0, value: 0))
        #expect(try interpreter.frame(at: 0).groups[0].value == 50)
        #expect(try interpreter.frame(at: 100).groups[0].value == 100)
        #expect(try interpreter.frame(at: 200).groups[0].value == 150)
        #expect(try interpreter.frame(at: 300).finished)
    }

    @Test func colourVariableAndIfElseAreTyped() throws {
        let id = "selected-colour"
        let operations: [EffectOperation] = [
            .setVariable(id: id, value: .colour(EffectColour(hue: 120, saturation: 255, value: 255))),
            .ifElse(
                .comparison(.greaterThan, .groupValue(zeroBasedGroup: 0, property: .hue), .number(180)),
                then: [
                    .setColour(.all, .variable(id: id, type: .colour))
                ], else: [.setHSV(.all, h: .number(0), s: .number(255), v: .number(255))]),
        ]
        let compiled = try EffectCompiler.compile(operations: operations, nodeCount: 4, variables: [id: .colour])
        var high = try EffectInterpreter(compiled, initialGroups: groups(hue: 240))
        var low = try EffectInterpreter(compiled, initialGroups: groups(hue: 20))
        #expect(try high.frame(at: 0).groups[0].hue == 120)
        #expect(try low.frame(at: 0).groups[0].hue == 0)
    }

    @Test func instructionBudgetStopsZeroTimeLoop() throws {
        let compiled = try compile([
            .whileLoop(
                .boolean(true),
                body: [
                    .adjustHSV(.all, dh: .number(1), ds: .number(0), dv: .number(0))
                ])
        ])
        var interpreter = try EffectInterpreter(compiled, initialGroups: groups(hue: 0))
        #expect(throws: EffectRuntimeError.self) { try interpreter.frame(at: 0) }
    }

    @Test func breakAndContinueControlNearestLoop() throws {
        let id = "index", value = EffectExpression.variable(id: "index", type: .number)
        let operations: [EffectOperation] = [
            .forLoop(
                variableID: id, from: .number(0), through: .number(5), step: .number(1),
                body: [
                    .ifElse(.comparison(.equal, value, .number(2)), then: [.continueLoop()], else: []),
                    .ifElse(.comparison(.equal, value, .number(4)), then: [.breakLoop()], else: []),
                    .adjustHSV(.all, dh: .number(10), ds: .number(0), dv: .number(0)),
                    .wait(.number(50)),
                ])
        ]
        let compiled = try EffectCompiler.compile(operations: operations, nodeCount: 8, variables: [id: .number])
        var interpreter = try EffectInterpreter(compiled, initialGroups: groups(hue: 0))
        let final = try interpreter.frame(at: 500)
        #expect(final.groups[0].hue == 30)
        #expect(final.finished)
    }

    @Test func divisionByZeroFailsSafely() throws {
        let id = "divisor"
        let operations: [EffectOperation] = [
            .setVariable(id: id, value: .number(0)),
            .wait(.arithmetic(.divide, .number(100), .variable(id: id, type: .number))),
        ]
        let compiled = try EffectCompiler.compile(operations: operations, nodeCount: 3, variables: [id: .number])
        var interpreter = try EffectInterpreter(compiled, initialGroups: groups(hue: 0))
        #expect(throws: EffectRuntimeError.self) { try interpreter.frame(at: 0) }
    }

    @Test func runtimeInputsDriveHSVAndAreCollected() throws {
        let operations: [EffectOperation] = [
            .setHSV(
                .all,
                h: .arithmetic(.add, .runtimeInput(.sensorHeading), .arithmetic(.multiply, .runtimeInput(.audioBass), .number(120))),
                s: .number(255),
                v: .clamp(
                    value: .arithmetic(
                        .add, .arithmetic(.multiply, .runtimeInput(.audioLevel), .number(255)),
                        .arithmetic(.multiply, .runtimeInput(.sensorMotion), .number(64))), low: .number(0), high: .number(255))),
            .wait(.number(100)),
        ]
        let compiled = try compile(operations)
        #expect(compiled.requiredInputs == [.sensorHeading, .sensorMotion, .audioBass, .audioLevel])
        let snapshot = EffectRuntimeSnapshot(
            capturedAtMilliseconds: 10,
            values: [.sensorHeading: .number(90), .sensorMotion: .number(0.5), .audioBass: .number(0.5), .audioLevel: .number(0.5)])
        var interpreter = try EffectInterpreter(compiled, initialGroups: groups(hue: 0))
        let frame = try interpreter.frame(at: 0, snapshot: snapshot)
        #expect(frame.groups[0].hue == 150)
        #expect(frame.groups[0].value == 160)
    }

    private func compile(_ operations: [EffectOperation]) throws -> CompiledEffect {
        try EffectCompiler.compile(operations: operations, nodeCount: operations.count + 1)
    }

    private func groups(hue: Int, mode: Int = 1, value: Int = 255) -> [EffectGroupState] {
        (0..<7).map { _ in EffectGroupState(innerMode: mode, hue: hue, saturation: 255, value: value) }
    }
}

struct PixelInterpreterParityTests {
    @Test func pixelTargetsUseGroupMajorIndexing() throws {
        let operations: [EffectOperation] = [
            .setColour(.all, .colour(EffectMath.rgbToHSV(red: 0, green: 0, blue: 0))),
            .setColour(
                .pixel(oneBasedGroup: .number(2), oneBasedPixel: .number(3)), .colour(EffectMath.rgbToHSV(red: 255, green: 0, blue: 0))),
            .setColour(.pixelAt(oneBasedIndex: .number(42)), .colour(EffectMath.rgbToHSV(red: 0, green: 0, blue: 255))),
            .wait(.number(100)),
        ]
        let compiled = try EffectCompiler.compile(operations: operations, nodeCount: 5)
        #expect(compiled.requiresPixelEffect)
        var interpreter = try EffectInterpreter(compiled, initialGroups: initial())
        let pixels = try #require(interpreter.frame(at: 0).pixels)
        let red = try EffectRGB(red: 255, green: 0, blue: 0)
        let blue = try EffectRGB(red: 0, green: 0, blue: 255)
        #expect(pixels.count == 42)
        #expect(pixels[8] == red)
        #expect(pixels[41] == blue)
    }

    @Test func allAndGroupExpandOnlyInPixelProgram() throws {
        let operations: [EffectOperation] = [
            .setColour(.all, .colour(EffectMath.rgbToHSV(red: 1, green: 2, blue: 3))),
            .setColour(.group(oneBasedIndex: .number(4)), .colour(EffectMath.rgbToHSV(red: 170, green: 187, blue: 204))),
            .setColour(.pixelAt(oneBasedIndex: .number(1)), .colour(EffectMath.rgbToHSV(red: 255, green: 255, blue: 255))),
            .wait(.number(100)),
        ]
        let compiled = try EffectCompiler.compile(operations: operations, nodeCount: 5)
        var interpreter = try EffectInterpreter(compiled, initialGroups: initial())
        let pixels = try #require(interpreter.frame(at: 0).pixels)
        let white = try EffectRGB(red: 255, green: 255, blue: 255)
        let groupColour = try EffectRGB(red: 170, green: 187, blue: 204)
        #expect(pixels[0] == white)
        #expect(pixels[18] == groupColour)
        #expect(pixels[23] == groupColour)
    }

    @Test func pixelModeRejectsHardwareModeAndConstantRangeErrors() {
        #expect(throws: EffectCompileError.self) {
            try EffectCompiler.compile(
                operations: [
                    .setColour(.pixelAt(oneBasedIndex: .number(1)), .colour(EffectColour(hue: 0, saturation: 0, value: 255))),
                    .setMode(.all, mode: .number(3), parameter: .number(128)),
                ], nodeCount: 3)
        }
        #expect(throws: EffectCompileError.self) {
            try EffectCompiler.compile(
                operations: [.setColour(.pixelAt(oneBasedIndex: .number(43)), .colour(EffectColour(hue: 0, saturation: 0, value: 255)))],
                nodeCount: 2)
        }
    }

    @Test func allPixelsHSVProducesFortyTwoRGBValues() throws {
        let compiled = try EffectCompiler.compile(
            operations: [.setHSV(.allPixels, h: .number(210), s: .number(255), v: .number(255)), .wait(.number(100))], nodeCount: 3)
        var interpreter = try EffectInterpreter(compiled, initialGroups: initial())
        let pixels = try #require(interpreter.frame(at: 0).pixels)
        #expect(pixels.count == 42)
        #expect(pixels.allSatisfy { $0 == (try? EffectRGB(red: 0, green: 128, blue: 255)) })
    }

    private func initial() -> [EffectGroupState] { (0..<7).map { _ in EffectGroupState() } }
}
