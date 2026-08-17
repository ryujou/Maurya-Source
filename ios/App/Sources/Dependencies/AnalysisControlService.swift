import MauryaAnalysis
import MauryaEffects

enum AnalysisMode: String, CaseIterable, Identifiable, Sendable {
    case motion
    case audio
    case virtual
    var id: Self { self }
}

enum AnalysisPresentationState: Equatable, Sendable {
    case idle
    case starting(AnalysisMode)
    case running(AnalysisMode)
    case unavailable(String)
    case failed(String)
}

@MainActor
protocol AnalysisControlService: AnyObject {
    var state: AnalysisPresentationState { get }
    var snapshot: AnalysisInputSnapshot? { get }
    var virtualInputsEnabled: Bool { get }
    var audioSensitivity: Double { get }
    func start(_ mode: AnalysisMode)
    func stop()
    func setVirtualInputsEnabled(_ enabled: Bool)
    func setVirtualInput(_ key: RuntimeInputKey, value: Double)
    func zeroAttitude()
    func setAudioSensitivity(_ value: Double)
}
