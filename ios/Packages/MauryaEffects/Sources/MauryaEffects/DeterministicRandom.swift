/// Xorshift generator matching Android `DeterministicRandom` bit-for-bit.
///
/// This is a mutable value type so independent effect sessions cannot race on
/// shared RNG state. Zero seed maps to the same nonzero Android fallback.
public struct DeterministicRandom: Sendable {
    private static let zeroSeedFallback: UInt64 = 0x6A09_E667_F3BC_C909
    private var state: UInt64

    public init(seed: Int64) {
        state = seed == 0 ? Self.zeroSeedFallback : UInt64(bitPattern: seed)
    }

    public mutating func reseed(_ seed: Int64) {
        state = seed == 0 ? Self.zeroSeedFallback : UInt64(bitPattern: seed)
    }

    public mutating func nextDouble() -> Double {
        var value = state
        value ^= value << 13
        value ^= value >> 7
        value ^= value << 17
        state = value
        return (Double(value >> 11) / 9_007_199_254_740_992).clamped(to: 0...1)
    }
}
