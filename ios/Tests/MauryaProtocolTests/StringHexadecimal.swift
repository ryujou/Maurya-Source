import Foundation

extension String {
    func hexadecimalData() throws -> Data {
        let characters = Array(utf8)
        guard characters.count.isMultiple(of: 2) else {
            throw GoldenVectorFileError.invalidHexadecimal(self)
        }

        var data = Data()
        data.reserveCapacity(characters.count / 2)
        for offset in stride(from: 0, to: characters.count, by: 2) {
            guard let high = hexadecimalNibble(characters[offset]),
                let low = hexadecimalNibble(characters[offset + 1])
            else {
                throw GoldenVectorFileError.invalidHexadecimal(self)
            }
            data.append((high << 4) | low)
        }
        return data
    }

    private func hexadecimalNibble(_ character: UInt8) -> UInt8? {
        switch character {
        case 48...57:
            character - 48
        case 97...102:
            character - 97 + 10
        case 65...(65 + 5):
            character - 65 + 10
        default:
            nil
        }
    }
}
