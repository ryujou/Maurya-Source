import Foundation
import MauryaShare

enum DeepLinkParser {
    static func route(from url: URL) -> AppRoute? {
        if url.scheme?.lowercased() == "https" {
            guard let token = try? ShareToken.parse(url.absoluteString) else { return nil }
            return .shareImport(token: token)
        }

        guard url.scheme?.lowercased() == "maurya",
            url.user == nil,
            url.password == nil,
            url.port == nil,
            url.query == nil,
            url.fragment == nil
        else { return nil }

        let segments = ([url.host].compactMap { $0 } + url.pathComponents)
            .filter { $0 != "/" && $0.isEmpty == false }

        switch segments.first?.lowercased() {
        case "device":
            guard segments.count == 2,
                segments[1].isEmpty == false,
                segments[1].contains("/") == false
            else { return nil }
            return .deviceDetail(id: segments[1])
        case "share":
            guard segments.count <= 2 else { return nil }
            guard let rawToken = segments.dropFirst().first else {
                return .shareImport(token: nil)
            }
            guard let token = try? ShareToken.parse(rawToken) else { return nil }
            return .shareImport(token: token)
        default:
            return nil
        }
    }
}
