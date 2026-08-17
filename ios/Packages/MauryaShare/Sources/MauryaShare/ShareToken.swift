import Foundation

public enum ShareToken {
    public static let origin = "https://xtbang.top"
    private static let alphabet = Set("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    public static func parse(_ raw: String) throws -> String {
        let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if isToken(candidate) { return candidate }
        if candidate.count == 11 {
            let characters = Array(candidate)
            if characters[5] == "-" {
                let joined = String(characters[0..<5] + characters[6..<11])
                if isToken(joined) { return joined }
            }
        }

        guard let components = URLComponents(string: candidate),
            components.scheme == "https",
            components.host == "xtbang.top",
            components.user == nil,
            components.password == nil,
            components.port == nil,
            components.query == nil,
            components.fragment == nil
        else {
            throw ShareValidationError.invalidToken
        }
        let path = components.percentEncodedPath
        let prefix = "/maurya/s/"
        guard path.hasPrefix(prefix) else { throw ShareValidationError.invalidToken }
        var token = String(path.dropFirst(prefix.count))
        if token.hasSuffix("/") { token.removeLast() }
        guard !token.contains("/"), isToken(token) else { throw ShareValidationError.invalidToken }
        return token
    }

    public static func shortCode(_ raw: String) throws -> String {
        let token = try parse(raw)
        let split = token.index(token.startIndex, offsetBy: 5)
        return "\(token[..<split])-\(token[split...])"
    }

    public static func canonicalURL(_ raw: String) throws -> URL {
        let token = try parse(raw)
        guard let result = URL(string: "\(origin)/maurya/s/\(token)") else {
            throw ShareValidationError.invalidToken
        }
        return result
    }

    private static func isToken(_ candidate: String) -> Bool {
        candidate.utf8.count == 10 && candidate.allSatisfy(alphabet.contains)
    }
}
