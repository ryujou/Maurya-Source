struct GoldenCRCVector: Decodable, Sendable {
    let id: String
    let inputHex: String
    let crcValueHex: String
    let wireSuffixHex: String
}
