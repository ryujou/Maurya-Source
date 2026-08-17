import Foundation
import MauryaProtocol

public enum BluetoothAdvertisementMatcher: Sendable {
    public static func matches(
        filterMaurya: Bool,
        name: String?,
        advertisedServiceUUIDs: some Collection<String>
    ) -> Bool {
        guard filterMaurya else { return true }
        if name?.lowercased().hasPrefix("maurya-") == true { return true }
        return advertisedServiceUUIDs.contains { UUIDString in
            let normalized = UUIDString.uppercased()
            return normalized == "FFE0" || normalized == MauryaBluetoothUUID.service
        }
    }
}
