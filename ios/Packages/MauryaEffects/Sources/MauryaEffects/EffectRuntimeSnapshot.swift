public struct EffectRuntimeSnapshot: Equatable, Sendable {
    public let capturedAtMilliseconds: Int64
    public let values: [RuntimeInputKey: EffectValue]
    public let available: Set<RuntimeInputKey>
    public let updatedAtMilliseconds: [RuntimeInputKey: Int64]

    public init(
        capturedAtMilliseconds: Int64,
        values: [RuntimeInputKey: EffectValue],
        available: Set<RuntimeInputKey>? = nil,
        updatedAtMilliseconds: [RuntimeInputKey: Int64]? = nil
    ) {
        self.capturedAtMilliseconds = capturedAtMilliseconds
        self.values = values
        self.available = available ?? Set(values.keys)
        self.updatedAtMilliseconds =
            updatedAtMilliseconds
            ?? Dictionary(uniqueKeysWithValues: values.keys.map { ($0, capturedAtMilliseconds) })
    }

    public subscript(key: RuntimeInputKey) -> EffectValue {
        values[key] ?? (key == .audioBeat ? .boolean(false) : .number(0))
    }

    public func isStale(
        _ key: RuntimeInputKey,
        nowMilliseconds: Int64,
        timeoutMilliseconds: Int64 = 1_000
    ) -> Bool {
        guard available.contains(key) else { return true }
        let updatedAt = updatedAtMilliseconds[key] ?? 0
        return nowMilliseconds &- updatedAt > timeoutMilliseconds
    }

    public static let empty = EffectRuntimeSnapshot(
        capturedAtMilliseconds: 0,
        values: [:],
        available: []
    )
}

public protocol EffectInputProvider: Sendable {
    func snapshot() -> EffectRuntimeSnapshot
    func availableInputs() -> Set<RuntimeInputKey>
}
