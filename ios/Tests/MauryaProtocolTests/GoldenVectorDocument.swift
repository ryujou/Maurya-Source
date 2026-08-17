struct GoldenVectorDocument: Decodable, Sendable {
    let vectorVersion: String
    let schemaFile: String
    let crc: [GoldenCRCVector]
    let frames: [GoldenFrameVector]
    let mapping: [GoldenMappingVector]
}
