import Foundation
import Testing

@testable import MauryaEffects

struct EffectBlocklyCatalogTests {
    @Test func catalogHasNoMissingOrExtraAndroidTypes() {
        #expect(EffectCompiler.supportedStatementTypes == Self.androidStatements)
        #expect(EffectCompiler.supportedExpressionTypes == Self.androidExpressions)
    }

    @Test func everyAndroidExpressionTypeCompilesThroughItsTypedConsumer() {
        for type in Self.androidExpressions.sorted() {
            do {
                let fixture = Self.expression(type)
                let consumer: JSON
                switch fixture.valueType {
                case .number:
                    consumer = Self.block(
                        "maurya_wait_value", "consumer", fields: ["UNIT": "MS"], inputs: ["DURATION": fixture.block], next: Self.wait())
                case .boolean:
                    consumer = Self.block(
                        "maurya_if", "consumer", inputs: ["IF": fixture.block, "DO": Self.wait()], next: Self.wait("tail"))
                case .colour:
                    consumer = Self.block("maurya_set_color_value", "consumer", inputs: ["COLOR": fixture.block], next: Self.wait())
                case .numberList:
                    let length = Self.block("maurya_list_length", "length", inputs: ["LIST": fixture.block])
                    consumer = Self.block("maurya_wait_value", "consumer", inputs: ["DURATION": length], next: Self.wait())
                case .colourList:
                    consumer = Self.block("maurya_apply_colour_list", "consumer", inputs: ["LIST": fixture.block], next: Self.wait())
                default:
                    Issue.record("Unexpected fixture type \(String(describing: fixture.valueType)) for \(type)")
                    continue
                }
                _ = try EffectCompiler.compile(blocklyJSON: Self.workspace(main: consumer))
            } catch {
                Issue.record("Android expression type \(type) failed: \(error)")
            }
        }
    }

    @Test func everyAndroidStatementTypeCompiles() {
        for type in Self.androidStatements.subtracting(["maurya_start", "maurya_function_def"]).sorted() {
            do {
                _ = try EffectCompiler.compile(
                    blocklyJSON: Self.workspace(
                        main: try Self.statement(type), functions: type == "maurya_function_call" ? [Self.functionDefinition()] : []))
            } catch {
                Issue.record("Android statement type \(type) failed: \(error)")
            }
        }
        _ = try? EffectCompiler.compile(blocklyJSON: Self.workspace(main: Self.wait(), functions: [Self.functionDefinition()]))
    }

    @Test func catalogRejectsUnknownAndMalformedInputs() {
        #expect(throws: EffectCompileError.self) {
            try EffectCompiler.compile(blocklyJSON: Self.workspace(main: Self.block("maurya_future", "unknown")))
        }
        #expect(throws: EffectCompileError.self) {
            try EffectCompiler.compile(blocklyJSON: Self.workspace(main: Self.block("maurya_wait_value", "missing")))
        }
        #expect(throws: EffectCompileError.self) {
            let bad = Self.block("maurya_wait_value", "mismatch", inputs: ["DURATION": Self.bool()])
            _ = try EffectCompiler.compile(blocklyJSON: Self.workspace(main: bad))
        }
        #expect(throws: EffectCompileError.self) {
            let recursive = Self.functionDefinition(
                name: "loop", body: Self.block("maurya_function_call", "recursive", fields: ["NAME": "loop"]))
            _ = try EffectCompiler.compile(blocklyJSON: Self.workspace(main: Self.wait(), functions: [recursive]))
        }
        #expect(throws: EffectCompileError.self) {
            let fractional = Self.block(
                "maurya_set_pixel_at_color_value", "fractional", inputs: ["INDEX": Self.number(1.5), "COLOR": Self.colour()],
                next: Self.wait())
            _ = try EffectCompiler.compile(blocklyJSON: Self.workspace(main: fractional))
        }
    }

    @Test func pixelHSVAndColourListMatchAndroidFrames() throws {
        let hsv = Self.block("maurya_set_all_pixels_hsv_value", "all-hsv", inputs: Self.hsvInputs(), next: Self.wait())
        var hsvInterpreter = try EffectInterpreter(
            EffectCompiler.compile(blocklyJSON: Self.workspace(main: hsv)),
            initialGroups: Array(repeating: EffectGroupState(), count: 7)
        )
        let hsvPixels = try #require(hsvInterpreter.frame(at: 0).pixels)
        #expect(hsvPixels.count == 42)
        #expect(hsvPixels.allSatisfy { $0 == (try? EffectRGB(red: 0, green: 255, blue: 0)) })

        let palette = Self.block("maurya_apply_pixel_colour_list", "palette", inputs: ["LIST": Self.colourList()], next: Self.wait())
        var paletteInterpreter = try EffectInterpreter(
            EffectCompiler.compile(blocklyJSON: Self.workspace(main: palette)),
            initialGroups: Array(repeating: EffectGroupState(), count: 7)
        )
        let palettePixels = try #require(paletteInterpreter.frame(at: 0).pixels)
        #expect(palettePixels.count == 42)
        #expect(palettePixels[0] == palettePixels[7])
        #expect(palettePixels[6] == palettePixels[41])
    }

    @Test func blockRuntimeInputIsCollectedAndEvaluated() throws {
        let runtime = Self.block("maurya_runtime_number", "motion", fields: ["KEY": "SENSOR_MOTION"])
        let set = Self.block(
            "maurya_set_hsv_value", "set", inputs: ["H": runtime, "S": Self.number(255), "V": Self.number(255)], next: Self.wait())
        let compiled = try EffectCompiler.compile(blocklyJSON: Self.workspace(main: set))
        #expect(compiled.requiredInputs == [.sensorMotion])
        var interpreter = try EffectInterpreter(compiled, initialGroups: Array(repeating: EffectGroupState(), count: 7))
        let snapshot = EffectRuntimeSnapshot(capturedAtMilliseconds: 0, values: [.sensorMotion: .number(210)])
        #expect(try interpreter.frame(at: 0, snapshot: snapshot).groups[0].hue == 210)
    }

    private typealias JSON = [String: Any]
    private struct Fixture { let block: JSON; let valueType: EffectValueType }

    private static func expression(_ type: String) -> Fixture {
        let value: JSON
        let result: EffectValueType
        switch type {
        case "math_number": value = number(); result = .number
        case "logic_boolean": value = bool(); result = .boolean
        case "maurya_colour_literal": value = colour(); result = .colour
        case "maurya_var_get_number": value = block(type, "expr", fields: variable("number")); result = .number
        case "maurya_var_get_boolean": value = block(type, "expr", fields: variable("boolean")); result = .boolean
        case "maurya_var_get_colour": value = block(type, "expr", fields: variable("colour")); result = .colour
        case "maurya_elapsed": value = block(type, "expr"); result = .number
        case "maurya_group_value": value = block(type, "expr", fields: ["GROUP": 2, "PROPERTY": "V"]); result = .number
        case "maurya_algorithm_unary": value = block(type, "expr", fields: ["FUNCTION": "ABS"], inputs: ["A": number()]); result = .number
        case "maurya_algorithm_binary":
            value = block(type, "expr", fields: ["FUNCTION": "MIN"], inputs: ["A": number(), "B": number(2)]); result = .number
        case "maurya_algorithm_ternary":
            value = block(type, "expr", fields: ["FUNCTION": "CLAMP"], inputs: ["A": number(), "B": number(), "C": number(2)]);
            result = .number
        case "maurya_wave":
            value = block(type, "expr", fields: ["FUNCTION": "SINE_WAVE"], inputs: ["PERIOD": number(1_000), "PHASE": number()]);
            result = .number
        case "maurya_square_wave":
            value = block(type, "expr", inputs: ["PERIOD": number(1_000), "DUTY": number(0.5), "PHASE": number()]); result = .number
        case "maurya_noise":
            value = block(
                type, "expr", fields: ["FUNCTION": "FBM_NOISE"], inputs: ["X": number(), "OCTAVES": number(3), "SEED": number(7)]);
            result = .number
        case "maurya_random_number": value = block(type, "expr", inputs: ["LOW": number(), "HIGH": number(1)]); result = .number
        case "maurya_random_colour": value = block(type, "expr"); result = .colour
        case "maurya_colour_unary":
            value = block(type, "expr", fields: ["FUNCTION": "COMPLEMENT"], inputs: ["COLOUR": colour()]); result = .colour
        case "maurya_colour_adjust":
            value = block(type, "expr", fields: ["FUNCTION": "ROTATE_HUE"], inputs: ["COLOUR": colour(), "AMOUNT": number(30)]);
            result = .colour
        case "maurya_colour_mix":
            value = block(
                type, "expr", fields: ["FUNCTION": "MIX_HSV"], inputs: ["A": colour(), "B": colour("#00FF00"), "AMOUNT": number(0.5)]);
            result = .colour
        case "maurya_runtime_number": value = block(type, "expr", fields: ["KEY": "SENSOR_MOTION"]); result = .number
        case "maurya_audio_number": value = block(type, "expr", fields: ["KEY": "AUDIO_LEVEL"]); result = .number
        case "maurya_audio_beat": value = block(type, "expr"); result = .boolean
        case "maurya_time_phase":
            value = block(type, "expr", fields: ["FUNCTION": "BAR_PHASE"], inputs: ["A": number(120), "B": number(4), "C": number(4)]);
            result = .number
        case "maurya_colour_list7": value = colourList(); result = .colourList
        case "maurya_number_list7": value = numberList(); result = .numberList
        case "maurya_colour_list_get": value = block(type, "expr", inputs: ["LIST": colourList(), "INDEX": number()]); result = .colour
        case "maurya_number_list_get": value = block(type, "expr", inputs: ["LIST": numberList(), "INDEX": number()]); result = .number
        case "maurya_list_length": value = block(type, "expr", inputs: ["LIST": numberList()]); result = .number
        case "maurya_pattern":
            value = block(type, "expr", fields: ["FUNCTION": "CHASE"], inputs: ["PROGRESS": number(0.2)]); result = .numberList
        case "maurya_pattern_list":
            value = block(type, "expr", fields: ["FUNCTION": "ROTATE_PATTERN"], inputs: ["LIST": numberList(), "OFFSET": number(1)]);
            result = .numberList
        case "math_arithmetic":
            value = block(type, "expr", fields: ["OP": "POWER"], inputs: ["A": number(2), "B": number(3)]); result = .number
        case "math_modulo": value = block(type, "expr", inputs: ["DIVIDEND": number(7), "DIVISOR": number(3)]); result = .number
        case "maurya_minmax": value = block(type, "expr", fields: ["OP": "MAX"], inputs: ["A": number(), "B": number(2)]); result = .number
        case "maurya_clamp": value = block(type, "expr", inputs: ["VALUE": number(), "LOW": number(), "HIGH": number(1)]); result = .number
        case "logic_compare":
            value = block(type, "expr", fields: ["OP": "LTE"], inputs: ["A": number(), "B": number(1)]); result = .boolean
        case "logic_operation":
            value = block(type, "expr", fields: ["OP": "OR"], inputs: ["A": bool(), "B": bool(false)]); result = .boolean
        case "logic_negate": value = block(type, "expr", inputs: ["BOOL": bool()]); result = .boolean
        case "maurya_hsv_colour":
            value = block(type, "expr", inputs: ["H": number(120), "S": number(255), "V": number(255)]); result = .colour
        default: fatalError("Missing expression fixture: \(type)")
        }
        return Fixture(block: value, valueType: result)
    }

    private static func statement(_ type: String) throws -> JSON {
        let tail = wait("tail")
        switch type {
        case "maurya_set_all_pixels_color_value": return block(type, "subject", inputs: ["COLOR": colour()], next: tail)
        case "maurya_set_all_pixels_hsv_value": return block(type, "subject", inputs: hsvInputs(), next: tail)
        case "maurya_set_pixel_color_value":
            return block(type, "subject", inputs: ["GROUP": number(1), "PIXEL": number(1), "COLOR": colour()], next: tail)
        case "maurya_set_pixel_hsv_value":
            return block(type, "subject", inputs: ["GROUP": number(1), "PIXEL": number(1)].merging(hsvInputs()) { $1 }, next: tail)
        case "maurya_set_pixel_at_color_value": return block(type, "subject", inputs: ["INDEX": number(1), "COLOR": colour()], next: tail)
        case "maurya_set_pixel_at_hsv_value":
            return block(type, "subject", inputs: ["INDEX": number(1)].merging(hsvInputs()) { $1 }, next: tail)
        case "maurya_apply_pixel_colour_list": return block(type, "subject", inputs: ["LIST": colourList()], next: tail)
        case "maurya_set_color": return block(type, "subject", fields: ["TARGET": "ALL", "COLOR": "#FF0000"], next: tail)
        case "maurya_set_color_value": return block(type, "subject", inputs: ["COLOR": colour()], next: tail)
        case "maurya_fade": return block(type, "subject", fields: ["COLOR": "#FF0000", "DURATION": 100])
        case "maurya_fade_value": return block(type, "subject", inputs: ["COLOR": colour(), "DURATION": number(100)])
        case "maurya_set_hsv": return block(type, "subject", fields: ["H": 120, "S": 255, "V": 255], next: tail)
        case "maurya_set_hsv_value", "maurya_adjust_hsv_value": return block(type, "subject", inputs: hsvInputs(), next: tail)
        case "maurya_adjust_hsv": return block(type, "subject", fields: ["H": 1, "S": 0, "V": 0], next: tail)
        case "maurya_mode": return block(type, "subject", fields: ["MODE": "3", "PARAM": 128], next: tail)
        case "maurya_wait": return wait("subject")
        case "maurya_wait_value": return block(type, "subject", inputs: ["DURATION": number(100)])
        case "maurya_seed_random": return block(type, "subject", inputs: ["SEED": number(7)], next: tail)
        case "maurya_function_call": return block(type, "subject", fields: ["NAME": "helper"], next: tail)
        case "maurya_apply_colour_list": return block(type, "subject", inputs: ["LIST": colourList()], next: tail)
        case "maurya_var_set_number": return block(type, "subject", fields: variable("number"), inputs: ["VALUE": number()], next: tail)
        case "maurya_var_set_boolean": return block(type, "subject", fields: variable("boolean"), inputs: ["VALUE": bool()], next: tail)
        case "maurya_var_set_colour": return block(type, "subject", fields: variable("colour"), inputs: ["VALUE": colour()], next: tail)
        case "maurya_var_change_number": return block(type, "subject", fields: variable("number"), inputs: ["VALUE": number(1)], next: tail)
        case "maurya_if", "maurya_if_else":
            return block(type, "subject", inputs: ["IF": bool(), "DO": wait("then"), "ELSE": wait("else")], next: tail)
        case "maurya_repeat": return block(type, "subject", fields: ["COUNT": 2], inputs: ["DO": wait("body")])
        case "maurya_forever": return block(type, "subject", inputs: ["DO": wait("body")])
        case "maurya_for":
            return block(
                type, "subject", fields: variable("number"),
                inputs: ["FROM": number(), "TO": number(2), "BY": number(1), "DO": wait("body")])
        case "maurya_while": return block(type, "subject", inputs: ["IF": bool(false), "DO": wait("body")], next: tail)
        case "maurya_break", "maurya_continue":
            return block("maurya_repeat", "outer", fields: ["COUNT": 1], inputs: ["DO": block(type, "subject")], next: tail)
        case "maurya_end": return block(type, "subject")
        default: throw CatalogFixtureError.missing(type)
        }
    }

    private static func workspace(main: JSON, functions: [JSON] = []) throws -> String {
        let start = block("maurya_start", "start", next: main)
        let root: JSON = [
            "variables": [
                ["name": "number", "id": "var-number", "type": "Number"],
                ["name": "boolean", "id": "var-boolean", "type": "Boolean"],
                ["name": "colour", "id": "var-colour", "type": "Colour"],
            ],
            "blocks": ["languageVersion": 0, "blocks": [start] + functions],
        ]
        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private static func block(_ type: String, _ id: String, fields: JSON = [:], inputs: [String: JSON] = [:], next: JSON? = nil) -> JSON {
        var result: JSON = ["type": type, "id": id]
        if fields.isEmpty == false { result["fields"] = fields }
        if inputs.isEmpty == false { result["inputs"] = inputs.mapValues { ["block": $0] } }
        if let next { result["next"] = ["block": next] }
        return result
    }

    private static func number(_ value: Double = 100) -> JSON { block("math_number", UUID().uuidString, fields: ["NUM": value]) }
    private static func bool(_ value: Bool = true) -> JSON {
        block("logic_boolean", UUID().uuidString, fields: ["BOOL": value ? "TRUE" : "FALSE"])
    }
    private static func colour(_ value: String = "#FF0000") -> JSON {
        block("maurya_colour_literal", UUID().uuidString, fields: ["COLOR": value])
    }
    private static func wait(_ id: String = "wait") -> JSON { block("maurya_wait", id, fields: ["DURATION": 100, "UNIT": "MS"]) }
    private static func hsvInputs() -> [String: JSON] { ["H": number(120), "S": number(255), "V": number(255)] }
    private static func variable(_ name: String) -> JSON { ["VAR": ["id": "var-\(name)"]] }
    private static func colourList() -> JSON {
        let values = ["#FF0000", "#00FF00", "#0000FF", "#FFFF00", "#00FFFF", "#FF00FF", "#FFFFFF"]
        return block(
            "maurya_colour_list7", UUID().uuidString,
            inputs: Dictionary(uniqueKeysWithValues: (1...7).map { ("C\($0)", colour(values[$0 - 1])) }))
    }
    private static func numberList() -> JSON {
        block(
            "maurya_number_list7", UUID().uuidString,
            inputs: Dictionary(uniqueKeysWithValues: (1...7).map { ("N\($0)", number(Double($0))) }))
    }
    private static func functionDefinition(name: String = "helper", body: JSON = wait("function-body")) -> JSON {
        block("maurya_function_def", "function-\(name)", fields: ["NAME": name], inputs: ["BODY": body])
    }

    private enum CatalogFixtureError: Error { case missing(String) }

    private static let androidStatements: Set<String> = [
        "maurya_start", "maurya_function_def", "maurya_set_all_pixels_color_value", "maurya_set_all_pixels_hsv_value",
        "maurya_set_pixel_color_value", "maurya_set_pixel_hsv_value", "maurya_set_pixel_at_color_value", "maurya_set_pixel_at_hsv_value",
        "maurya_apply_pixel_colour_list", "maurya_set_color", "maurya_set_color_value", "maurya_fade", "maurya_fade_value",
        "maurya_set_hsv", "maurya_set_hsv_value", "maurya_adjust_hsv", "maurya_adjust_hsv_value", "maurya_mode", "maurya_wait",
        "maurya_wait_value", "maurya_seed_random", "maurya_function_call", "maurya_apply_colour_list", "maurya_var_set_number",
        "maurya_var_set_boolean", "maurya_var_set_colour", "maurya_var_change_number", "maurya_if", "maurya_if_else", "maurya_repeat",
        "maurya_forever", "maurya_for", "maurya_while", "maurya_break", "maurya_continue", "maurya_end",
    ]
    private static let androidExpressions: Set<String> = [
        "math_number", "logic_boolean", "maurya_colour_literal", "maurya_var_get_number", "maurya_var_get_boolean",
        "maurya_var_get_colour", "maurya_elapsed", "maurya_group_value", "maurya_algorithm_unary", "maurya_algorithm_binary",
        "maurya_algorithm_ternary", "maurya_wave", "maurya_square_wave", "maurya_noise", "maurya_random_number",
        "maurya_random_colour", "maurya_colour_unary", "maurya_colour_adjust", "maurya_colour_mix", "maurya_runtime_number",
        "maurya_audio_number", "maurya_audio_beat", "maurya_time_phase", "maurya_colour_list7", "maurya_number_list7",
        "maurya_colour_list_get", "maurya_number_list_get", "maurya_list_length", "maurya_pattern", "maurya_pattern_list",
        "math_arithmetic", "math_modulo", "maurya_minmax", "maurya_clamp", "logic_compare", "logic_operation",
        "logic_negate", "maurya_hsv_colour",
    ]
}
