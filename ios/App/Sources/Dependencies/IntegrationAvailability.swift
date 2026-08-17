enum IntegrationAvailability: Equatable, Sendable {
    case unavailable(reason: String)
    case available
}
