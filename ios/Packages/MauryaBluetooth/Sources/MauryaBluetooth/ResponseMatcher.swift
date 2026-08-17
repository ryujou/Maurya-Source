import Foundation

public enum ModbusResponseMatcher {
    /// Matches unit ID and function. Modbus exception responses are accepted
    /// for the corresponding request function and decoded by the caller.
    public static func matches(request: Data, response: Data) -> Bool {
        guard request.count >= 2, response.count >= 2 else { return false }
        let requestFunction = request[request.startIndex + 1]
        let responseFunction = response[response.startIndex + 1]
        guard request[request.startIndex] == response[response.startIndex],
            responseFunction == requestFunction || responseFunction == requestFunction | 0x80
        else {
            return false
        }

        // Vendor requests and responses echo the command as the first payload
        // byte. Match it so an unrelated 0x41 notification cannot consume the
        // active transaction. Modbus exception frames have no vendor payload.
        if requestFunction == 0x41, responseFunction == 0x41 {
            guard request.count >= 4, response.count >= 4 else { return false }
            return request[request.startIndex + 3] == response[response.startIndex + 3]
        }
        return true
    }
}
