import Foundation

public enum WriteFragmenter {
    public static func chunks(for payload: Data, maximumLength: Int) throws -> [Data] {
        guard maximumLength > 0 else {
            throw BluetoothFailure(.writeUnsupported, detail: "Maximum write length must be positive")
        }
        guard payload.isEmpty == false else { return [] }

        var chunks: [Data] = []
        chunks.reserveCapacity((payload.count + maximumLength - 1) / maximumLength)
        var offset = payload.startIndex
        while offset < payload.endIndex {
            let end =
                payload.index(offset, offsetBy: maximumLength, limitedBy: payload.endIndex)
                ?? payload.endIndex
            chunks.append(Data(payload[offset..<end]))
            offset = end
        }
        return chunks
    }
}
