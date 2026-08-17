enum AppContentState: Equatable, Sendable {
    case loading
    case empty
    case error(message: String)
    case permissionRequired
    case disconnected
}
