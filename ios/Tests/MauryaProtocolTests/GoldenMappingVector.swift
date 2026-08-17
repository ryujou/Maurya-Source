struct GoldenMappingVector: Decodable, Sendable {
    let groupOneBased: Int
    let pixelInGroupOneBased: Int
    let globalOneBased: Int
    let linearZeroBased: Int
}
