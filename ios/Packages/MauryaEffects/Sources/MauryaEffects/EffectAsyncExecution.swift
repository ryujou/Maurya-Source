import Foundation

public enum EffectAsyncExecutionError: Error, Equatable, Sendable {
    case cancelled
    case deadlineExceeded
}

extension EffectAsyncExecutionError {
    public var code: String {
        switch self {
        case .cancelled: "EFFECT_EXECUTION_CANCELLED"
        case .deadlineExceeded: "EFFECT_EXECUTION_DEADLINE_EXCEEDED"
        }
    }
}

typealias EffectExecutionCheckpoint = @Sendable () throws -> Void

enum EffectExecutionControl {
    static func checkpoint(deadline: ContinuousClock.Instant?) -> EffectExecutionCheckpoint {
        let clock = ContinuousClock()
        return {
            guard !Task.isCancelled else { throw EffectAsyncExecutionError.cancelled }
            if let deadline, clock.now >= deadline { throw EffectAsyncExecutionError.deadlineExceeded }
        }
    }
}

/// Structured, cooperative async entry points for CPU-bound effect compilation.
public enum EffectAsyncCompiler: Sendable {
    @concurrent public static func compileScript(
        _ source: String,
        deadline: ContinuousClock.Instant? = nil
    ) async throws -> CompiledEffect {
        let checkpoint = EffectExecutionControl.checkpoint(deadline: deadline)
        try checkpoint()
        return try EffectScriptCompiler.compile(source, checkpoint: checkpoint)
    }

    @concurrent public static func compileBlockly(
        _ blocklyJSON: String,
        deadline: ContinuousClock.Instant? = nil
    ) async throws -> CompiledEffect {
        let checkpoint = EffectExecutionControl.checkpoint(deadline: deadline)
        try checkpoint()
        return try EffectCompiler.compile(blocklyJSON: blocklyJSON, checkpoint: checkpoint)
    }
}

/// Actor-isolated facade preserving interpreter state between structured async calls.
public actor EffectAsyncInterpreter {
    private var interpreter: EffectInterpreter

    public init(_ compiled: CompiledEffect, initialGroups: [EffectGroupState]) throws {
        interpreter = try EffectInterpreter(compiled, initialGroups: initialGroups)
    }

    public func frame(
        at elapsedMilliseconds: Int64,
        snapshot: EffectRuntimeSnapshot = .empty,
        deadline: ContinuousClock.Instant? = nil
    ) async throws -> EffectFrame {
        let checkpoint = EffectExecutionControl.checkpoint(deadline: deadline)
        try checkpoint()
        var candidate = interpreter
        let frame = try candidate.frame(at: elapsedMilliseconds, snapshot: snapshot, checkpoint: checkpoint)
        interpreter = candidate
        return frame
    }

    public var isInfinite: Bool { interpreter.isInfinite }
    public var durationMilliseconds: Int64? { interpreter.durationMilliseconds }
}
