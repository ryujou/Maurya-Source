import CryptoKit
import Foundation
import Testing

@testable import MauryaEffects

struct EffectAndroidLocalParityTests {
    struct SampleFixture: Sendable {
        let name: String
        let sha256: String
    }

    @Test("Eight Android Maurya Script resources are byte-identical and executable", arguments: samples)
    func androidSampleResource(_ fixture: SampleFixture) throws {
        let url = Self.repositoryRoot
            .appending(path: "android/app/src/test/resources/maurya-script")
            .appending(path: fixture.name)
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(digest == fixture.sha256, Comment(rawValue: fixture.name))

        let source = try #require(String(data: data, encoding: .utf8))
        let compiled = try EffectScriptCompiler.compile(source)
        #expect(compiled.operations.isEmpty == false, Comment(rawValue: fixture.name))
        var interpreter = try EffectInterpreter(compiled, initialGroups: groups())
        #expect(try interpreter.frame(at: 0).groups.count == 7)
        #expect(try interpreter.frame(at: 1_000).groups.count == 7)
    }

    @Test func supplementaryUnicodeUsesAndroidUTF16SourceRangesAndColumns() {
        let prefix = "// 😀\neffect \"x\" { "
        let source = prefix + "unknown(1); }"
        do {
            _ = try EffectScriptCompiler.compile(source)
            Issue.record("Expected syntax failure")
        } catch let error as EffectCompileError {
            let issue = error.issues.first
            #expect(issue?.sourceStart == prefix.utf16.count)
            #expect(issue?.sourceEnd == prefix.utf16.count + "unknown".utf16.count)
            #expect(issue?.messageZh.contains("第2行第14列") == true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func valueFunctionParametersAndLocalsRestoreSameNamedOuterVariables() throws {
        let source = """
            fn increment(number value): number {
                let scratch: number = value;
                scratch += 1;
                return scratch;
            }
            effect "scope" {
                let value: number = 40;
                let scratch: number = 100;
                all.hsv(increment(1) + increment(2) + value + scratch, 255, 255);
                wait(100ms);
            }
            """
        let compiled = try EffectScriptCompiler.compile(source)
        var interpreter = try EffectInterpreter(compiled, initialGroups: Self.groups())
        #expect(try interpreter.frame(at: 0).groups[0].hue == 145)
    }

    @Test func statefulNumericBuiltinsFollowAndroidTimeSequences() throws {
        let smooth = try numericInterpreter(.smooth, arguments: [.runtimeInput(.sensorMotion), .number(100), .number(200)], scale: 255)
        #expect(try values(smooth, inputs: [(0, 0), (100, 1), (200, 0)]) == [0, 161, 98])

        let peak = try numericInterpreter(.peakHold, arguments: [.runtimeInput(.sensorMotion), .number(150), .number(100)], scale: 255)
        #expect(try values(peak, inputs: [(0, 1), (100, 0.2), (200, 0.2)]) == [255, 255, 51])
    }

    @Test func statefulBooleanBuiltinsFollowAndroidTimeSequences() throws {
        var hysteresis = try booleanInterpreter(
            .hysteresis, arguments: [.runtimeInput(.sensorMotion), .number(0.3), .number(0.7)], input: .sensorMotion)
        #expect(
            try booleans(&hysteresis, key: .sensorMotion, inputs: [.number(0), .number(1), .number(0.5), .number(0.2)]) == [
                false, true, true, false,
            ])

        var debounce = try booleanInterpreter(.debounce, arguments: [.runtimeInput(.audioBeat), .number(150)], input: .audioBeat)
        let debounced = try booleans(&debounce, key: .audioBeat, inputs: [.boolean(false), .boolean(true), .boolean(true)])
        // Android initializes an absent stable value from the desired input, so
        // its current debounce implementation passes this first transition through.
        #expect(debounced == [false, true, true])

        var rising = try booleanInterpreter(.risingEdge, arguments: [.runtimeInput(.audioBeat)], input: .audioBeat)
        #expect(try booleans(&rising, key: .audioBeat, inputs: [.boolean(false), .boolean(true), .boolean(true)]) == [false, true, false])

        var falling = try booleanInterpreter(.fallingEdge, arguments: [.runtimeInput(.audioBeat)], input: .audioBeat)
        #expect(
            try booleans(&falling, key: .audioBeat, inputs: [.boolean(true), .boolean(false), .boolean(false)]) == [false, true, false])
    }

    private func numericInterpreter(
        _ function: BuiltinFunction,
        arguments: [EffectExpression],
        scale: Double
    ) throws -> EffectInterpreter {
        let expression = EffectExpression.arithmetic(
            .multiply,
            .builtin(function, arguments: arguments, type: .number, nodeID: "stateful"),
            .number(scale)
        )
        let compiled = try EffectCompiler.compile(
            operations: [
                .repeatLoop(count: nil, body: [.setHSV(.all, h: .number(0), s: .number(255), v: expression), .wait(.number(100))])
            ], nodeCount: 4)
        return try EffectInterpreter(compiled, initialGroups: Self.groups())
    }

    private func values(
        _ initial: EffectInterpreter,
        inputs: [(Int64, Double)]
    ) throws -> [Int] {
        var interpreter = initial
        return try inputs.map { time, input in
            let snapshot = EffectRuntimeSnapshot(capturedAtMilliseconds: time, values: [.sensorMotion: .number(input)])
            return try interpreter.frame(at: time, snapshot: snapshot).groups[0].value
        }
    }

    private func booleanInterpreter(
        _ function: BuiltinFunction,
        arguments: [EffectExpression],
        input: RuntimeInputKey
    ) throws -> EffectInterpreter {
        let condition = EffectExpression.builtin(function, arguments: arguments, type: .boolean, nodeID: "stateful")
        let compiled = try EffectCompiler.compile(
            operations: [
                .repeatLoop(
                    count: nil,
                    body: [
                        .ifElse(
                            condition, then: [.setHSV(.all, h: .number(120), s: .number(255), v: .number(255))],
                            else: [.setHSV(.all, h: .number(0), s: .number(255), v: .number(255))]),
                        .wait(.number(100)),
                    ])
            ], nodeCount: 6)
        #expect(compiled.requiredInputs.contains(input))
        return try EffectInterpreter(compiled, initialGroups: Self.groups())
    }

    private func booleans(
        _ interpreter: inout EffectInterpreter,
        key: RuntimeInputKey,
        inputs: [EffectValue]
    ) throws -> [Bool] {
        try inputs.enumerated().map { index, input in
            let time = Int64(index * 100)
            let snapshot = EffectRuntimeSnapshot(capturedAtMilliseconds: time, values: [key: input])
            return try interpreter.frame(at: time, snapshot: snapshot).groups[0].hue == 120
        }
    }

    private static func groups() -> [EffectGroupState] {
        Array(repeating: EffectGroupState(), count: EffectGeometry.groupCount)
    }

    private func groups() -> [EffectGroupState] { Self.groups() }

    private static let repositoryRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        return url
    }()

    private static let samples: [SampleFixture] = [
        .init(name: "01-常亮频闪与颜色.maurya", sha256: "a8525f6892522559a626c309acd4fd2f6f280f63b9692b8a00b5ce953c05a0cf"),
        .init(name: "02-七组独立颜色.maurya", sha256: "e8cab15bb3e3ca3d22677911ef42b3a6c57b2c1c4d085423ccd87e2ec01dfb91"),
        .init(name: "03-渐变与HSV调节.maurya", sha256: "d57959f3882a5a0100fe3361d23cd7d133dff7b7df0b2fe8b5a20fbef57fe4f4"),
        .init(name: "04-for彩虹与Hue回绕.maurya", sha256: "aeff652675c7ad19bd29261a4d8c71eb8f1c1d010248b81faeee30a75e8fa44a"),
        .init(name: "05-变量与if判断.maurya", sha256: "3bd46d36be25843018cb4bc45dc724fa99ebac30c7ee2b54111a03534722a61d"),
        .init(name: "06-while与break.maurya", sha256: "94f481e573e26867a055815bc8843abfb9e06e7a8c8b93896d4666c6311b5649"),
        .init(name: "07-repeat与continue.maurya", sha256: "4033f9b8f74759618d483fa0bcb5e65d0f308915c99967a4b17878f188ca3233"),
        .init(name: "08-运算状态与结束.maurya", sha256: "f313f444fb107a5f7855991f6b60baee733dc9220f783f53a64ee8d0d45f4337"),
    ]
}
