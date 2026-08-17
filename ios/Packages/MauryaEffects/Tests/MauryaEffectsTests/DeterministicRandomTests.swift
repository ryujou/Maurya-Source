import Testing

@testable import MauryaEffects

struct DeterministicRandomTests {
    @Test
    func seed42MatchesAndroidBitForBit() {
        var random = DeterministicRandom(seed: 42)
        let expected = [
            0x1.52aa290000000p-29,
            0x1.401555fbf0040p-1,
            0x1.16267339a3a29p-1,
            0x1.41dc47f2feff8p-3,
            0x1.3a457f8e2cd04p-2,
            0x1.182fe56866e03p-1,
            0x1.3d85fc354b652p-1,
            0x1.26e1eaedd8474p-1,
        ]

        for value in expected {
            #expect(random.nextDouble() == value)
        }
    }

    @Test
    func zeroSeedUsesAndroidFallbackSequence() {
        var random = DeterministicRandom(seed: 0)
        #expect(random.nextDouble() == 0x1.c8a01ac7bffb4p-2)
        #expect(random.nextDouble() == 0x1.f8d5294ab565fp-1)
        #expect(random.nextDouble() == 0x1.45d0248420a18p-3)
    }

    @Test
    func equalSeedsRemainEqualAndDifferentSeedsDiverge() {
        var first = DeterministicRandom(seed: 42)
        var second = DeterministicRandom(seed: 42)
        for _ in 0..<32 {
            #expect(first.nextDouble() == second.nextDouble())
        }

        var different = DeterministicRandom(seed: 43)
        var original = DeterministicRandom(seed: 42)
        #expect(original.nextDouble() != different.nextDouble())
    }

    @Test
    func reseedRestartsTheSequence() {
        var random = DeterministicRandom(seed: 99)
        let first = random.nextDouble()
        _ = random.nextDouble()
        random.reseed(99)
        #expect(random.nextDouble() == first)
    }
}
