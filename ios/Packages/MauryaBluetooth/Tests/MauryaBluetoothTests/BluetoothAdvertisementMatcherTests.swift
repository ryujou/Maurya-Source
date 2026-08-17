import Foundation
import Testing

@testable import MauryaBluetooth

@Suite("Bluetooth advertisement matcher")
struct BluetoothAdvertisementMatcherTests {
    @Test func foregroundConfigurationDoesNotEnableStateRestorationByDefault() {
        #expect(BluetoothTransportConfiguration().restorationIdentifier == nil)
    }

    @Test func acceptsMauryaNameWhenServiceIsOmitted() {
        #expect(
            BluetoothAdvertisementMatcher.matches(
                filterMaurya: true,
                name: "Maurya-2601",
                advertisedServiceUUIDs: []
            ))
    }

    @Test func acceptsShortAndFullFFE0Service() {
        #expect(
            BluetoothAdvertisementMatcher.matches(
                filterMaurya: true,
                name: nil,
                advertisedServiceUUIDs: ["FFE0"]
            ))
        #expect(
            BluetoothAdvertisementMatcher.matches(
                filterMaurya: true,
                name: nil,
                advertisedServiceUUIDs: ["0000FFE0-0000-1000-8000-00805F9B34FB"]
            ))
    }

    @Test func rejectsUnrelatedPeripheralAndSupportsUnfilteredMode() {
        #expect(
            BluetoothAdvertisementMatcher.matches(
                filterMaurya: true,
                name: "midea",
                advertisedServiceUUIDs: [UUID().uuidString]
            ) == false)
        #expect(
            BluetoothAdvertisementMatcher.matches(
                filterMaurya: false,
                name: "midea",
                advertisedServiceUUIDs: []
            ))
    }
}
