import Foundation

/// Pure list and generated-pattern builtins kept separate from interpreter
/// control flow so they can be golden-tested without mutable runtime state.
public enum EffectPatternMath: Sendable {
    public static func mirror<Value: Sendable>(_ values: [Value]) -> [Value] {
        guard values.isEmpty == false else { return [] }
        return values.indices.map { index in
            values[Swift.min(index, values.count - 1 - index)]
        }
    }

    public static func rotate<Value: Sendable>(_ values: [Value], shift: Int) -> [Value] {
        guard values.isEmpty == false else { return [] }
        let normalizedShift = positiveModulo(shift, divisor: values.count)
        return values.indices.map { index in
            values[positiveModulo(index - normalizedShift, divisor: values.count)]
        }
    }

    public static func centerSpread<Value: Sendable>(_ values: [Value]) throws -> [Value] {
        try reorderSeven(values, order: [3, 2, 4, 1, 5, 0, 6])
    }

    public static func centerContract<Value: Sendable>(_ values: [Value]) throws -> [Value] {
        try reorderSeven(values, order: [0, 6, 1, 5, 2, 4, 3])
    }

    public static func chase(progress: Double) -> [Double] {
        // Kotlin's `Double.mod(1.0)` keeps a negative remainder. The Android
        // interpreter then floors and clamps it, so every negative phase
        // selects the first group instead of wrapping to the last group.
        let remainder = progress.truncatingRemainder(dividingBy: 1)
        let active =
            remainder.isFinite
            ? Int(Foundation.floor(remainder * 7)).clamped(to: 0...6)
            : 0
        return (0..<7).map { $0 == active ? 1 : 0 }
    }

    public static func wave(progress: Double) -> [Double] {
        (0..<7).map { index in
            let phase = Double(index) / 7
            return (Foundation.sin((progress + phase) * .pi * 2) + 1) / 2
        }
    }

    private static func reorderSeven<Value: Sendable>(
        _ values: [Value],
        order: [Int]
    ) throws -> [Value] {
        guard values.count == 7 else {
            throw EffectRuntimeError.patternRequiresSevenValues(actual: values.count)
        }
        return order.map { values[$0] }
    }

    private static func normalizedUnit(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 1)
        return remainder < 0 ? remainder + 1 : remainder
    }

    private static func positiveModulo(_ value: Int, divisor: Int) -> Int {
        let remainder = value % divisor
        return remainder < 0 ? remainder + divisor : remainder
    }
}
