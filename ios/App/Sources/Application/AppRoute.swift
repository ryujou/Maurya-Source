enum AppRoute: Hashable, Sendable {
    case deviceDetail(id: String)
    case shareImport(token: String?)
    case resources
    case effects
    case editor
    case analysis
    case playback
    case ota
    case reviewerGuide
    case legalPrivacy
}
