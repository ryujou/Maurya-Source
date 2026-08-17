struct GoldenFrameVector: Decodable, Sendable {
    let id: String
    let family: String
    let hex: String
    let completeFrameBytes: Int
}
