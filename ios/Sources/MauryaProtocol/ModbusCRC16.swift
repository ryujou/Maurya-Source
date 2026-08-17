import Foundation

public enum ModbusCRC16 {
    public static func checksum<C: Collection<UInt8>>(of bytes: C) -> UInt16 {
        var crc: UInt16 = 0xFFFF

        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                if crc & 0x0001 == 0x0001 {
                    crc = (crc >> 1) ^ 0xA001
                } else {
                    crc >>= 1
                }
            }
        }
        return crc
    }

    public static func appendingChecksum(to payload: Data) -> Data {
        var frame = payload
        let checksum = checksum(of: payload)
        frame.append(UInt8(truncatingIfNeeded: checksum))
        frame.append(UInt8(truncatingIfNeeded: checksum >> 8))
        return frame
    }

    public static func validates(_ frame: Data) -> Bool {
        guard frame.count >= 2 else { return false }
        let payloadEnd = frame.index(frame.endIndex, offsetBy: -2)
        let payload = frame[..<payloadEnd]
        let expected = checksum(of: payload)
        let low = UInt16(frame[payloadEnd])
        let highIndex = frame.index(after: payloadEnd)
        let high = UInt16(frame[highIndex])
        return expected == low | (high << 8)
    }
}
