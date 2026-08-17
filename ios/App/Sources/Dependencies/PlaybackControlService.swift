enum PlaybackPresentationState: Equatable, Sendable {
    case idle
    case unavailable(String)
    case preparing
    case running
    case paused
    case stopping
    case failed(String)
}

@MainActor
protocol PlaybackControlService: AnyObject {
    var state: PlaybackPresentationState { get }
    @discardableResult func start() -> PlaybackPresentationState
    func pause()
    func resume()
    func stop()
    func connectionLost()
    func suspendForBackground()
}
