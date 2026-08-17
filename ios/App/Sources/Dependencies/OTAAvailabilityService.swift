import MauryaOTA

enum OTAPreflightState: Equatable, Sendable {
    case checking
    case unavailable([String])
    case ready
}

@MainActor
protocol OTAAvailabilityService: AnyObject {
    var preflight: OTAPreflightState { get }
    var workflowSnapshot: OTAWorkflowSnapshot { get }
    var errorMessage: String? { get }
    var canStart: Bool { get }
    func refresh()
    func start() async
    func cancel() async
}
