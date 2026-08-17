import Foundation
import Testing

@testable import MauryaEffects

struct EffectTypesTests {
    struct InputFixture: Sendable {
        let key: RuntimeInputKey
        let rawValue: String
        let type: EffectValueType
    }

    static let inputFixtures: [InputFixture] = [
        .init(key: .sensorAccelX, rawValue: "SENSOR_ACCEL_X", type: .number),
        .init(key: .sensorAccelY, rawValue: "SENSOR_ACCEL_Y", type: .number),
        .init(key: .sensorAccelZ, rawValue: "SENSOR_ACCEL_Z", type: .number),
        .init(key: .sensorMotion, rawValue: "SENSOR_MOTION", type: .number),
        .init(key: .sensorShake, rawValue: "SENSOR_SHAKE", type: .number),
        .init(key: .sensorGyroX, rawValue: "SENSOR_GYRO_X", type: .number),
        .init(key: .sensorGyroY, rawValue: "SENSOR_GYRO_Y", type: .number),
        .init(key: .sensorGyroZ, rawValue: "SENSOR_GYRO_Z", type: .number),
        .init(key: .sensorPitch, rawValue: "SENSOR_PITCH", type: .number),
        .init(key: .sensorRoll, rawValue: "SENSOR_ROLL", type: .number),
        .init(key: .sensorYaw, rawValue: "SENSOR_YAW", type: .number),
        .init(key: .sensorLight, rawValue: "SENSOR_LIGHT", type: .number),
        .init(key: .sensorNear, rawValue: "SENSOR_NEAR", type: .number),
        .init(key: .sensorHeading, rawValue: "SENSOR_HEADING", type: .number),
        .init(key: .sensorPressure, rawValue: "SENSOR_PRESSURE", type: .number),
        .init(key: .audioLevel, rawValue: "AUDIO_LEVEL", type: .number),
        .init(key: .audioPeak, rawValue: "AUDIO_PEAK", type: .number),
        .init(key: .audioBass, rawValue: "AUDIO_BASS", type: .number),
        .init(key: .audioMid, rawValue: "AUDIO_MID", type: .number),
        .init(key: .audioTreble, rawValue: "AUDIO_TREBLE", type: .number),
        .init(key: .audioBeat, rawValue: "AUDIO_BEAT", type: .boolean),
        .init(key: .audioBPM, rawValue: "AUDIO_BPM", type: .number),
    ]

    @Test(arguments: inputFixtures)
    func runtimeInputKeysMatchAndroid(_ fixture: InputFixture) {
        #expect(fixture.key.rawValue == fixture.rawValue)
        #expect(fixture.key.valueType == fixture.type)
    }

    @Test
    func runtimeInputInventoryHasNoMissingOrDuplicateEntries() {
        #expect(RuntimeInputKey.allCases.count == Self.inputFixtures.count)
        #expect(Set(RuntimeInputKey.allCases.map(\.rawValue)).count == Self.inputFixtures.count)
    }

    @Test
    func runtimeValueReportsAndroidCompatibleTypes() {
        #expect(EffectValue.number(1).type == .number)
        #expect(EffectValue.boolean(true).type == .boolean)
        #expect(EffectValue.colour(.init(hue: 1, saturation: 2, value: 3)).type == .colour)
        #expect(EffectValue.target(.group7).type == .target)
        #expect(EffectValue.list(elementType: .number, values: []).type == .numberList)
        #expect(EffectValue.list(elementType: .boolean, values: []).type == .booleanList)
        #expect(EffectValue.list(elementType: .colour, values: []).type == .colourList)
        #expect(EffectValue.list(elementType: .target, values: []).type == .targetList)
    }

    @Test
    func schemaVersionsMatchAndroid421() {
        #expect(EffectProgramSchemas.editor == 4)
        #expect(EffectProgramSchemas.program == 6)
    }

    @Test
    func colourNormalizationUses42EraAndroidSemantics() {
        #expect(
            EffectColour(hue: -1, saturation: -5, value: 300).normalized
                == EffectColour(hue: 359, saturation: 0, value: 255)
        )
    }

    @Test
    func rgbRejectsOutOfRangeComponents() {
        #expect(throws: EffectRuntimeError.invalidRGB(red: -1, green: 0, blue: 0)) {
            try EffectRGB(red: -1, green: 0, blue: 0)
        }
        #expect(throws: Never.self) {
            _ = try EffectRGB(red: 0, green: 255, blue: 128)
        }
    }

    @Test
    func coreErrorsExposeStableTaxonomyWithoutBilingualLocalizedText() {
        #expect(EffectProgramError.invalidField("source").code == "EFFECT_IMPORT_INVALID_FIELD")
        #expect(EffectAsyncExecutionError.deadlineExceeded.code == "EFFECT_EXECUTION_DEADLINE_EXCEEDED")
        #expect(
            EffectRuntimeError.execution(code: .divisionByZero)
                == .execution(code: .divisionByZero)
        )
        #expect((EffectProgramError.invalidJSON as any Error) is LocalizedError == false)
        #expect((EffectAsyncExecutionError.cancelled as any Error) is LocalizedError == false)
    }

    @Test
    func compileDiagnosticSelectsExactlyOneLanguage() {
        let issue = EffectCompileIssue(code: "TEST", messageZh: "中文", messageJa: "日本語")
        #expect(issue.message(for: .simplifiedChinese) == "中文")
        #expect(issue.message(for: .japanese) == "日本語")
        #expect(issue.message(for: .simplifiedChinese).contains(" / ") == false)
        #expect(issue.message(for: .japanese).contains(" / ") == false)
    }
}
