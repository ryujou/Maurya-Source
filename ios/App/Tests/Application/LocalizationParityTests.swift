import Foundation
import Testing

@testable import Maurya

struct LocalizationParityTests {
    @Test func shippedLocalizationsHaveIdenticalKeySets() throws {
        let english = try keys(resource: "Localizable", localization: "en")

        #expect(try keys(resource: "Localizable", localization: "zh-Hans") == english)
        #expect(try keys(resource: "Localizable", localization: "ja") == english)
    }

    @Test func compiledPermissionCatalogIsCompleteAndLocalized() throws {
        let expected: Set<String> = [
            "NSBluetoothAlwaysUsageDescription",
            "NSCameraUsageDescription",
            "NSMicrophoneUsageDescription",
            "NSMotionUsageDescription",
        ]
        let english = try keys(resource: "InfoPlist", localization: "en")

        #expect(english == expected)
        #expect(try keys(resource: "InfoPlist", localization: "zh-Hans") == english)
        #expect(try keys(resource: "InfoPlist", localization: "ja") == english)
    }

    private func keys(resource: String, localization: String) throws -> Set<String> {
        let url = try #require(
            Bundle.main.url(
                forResource: resource,
                withExtension: "strings",
                subdirectory: nil,
                localization: localization
            ))
        let data = try Data(contentsOf: url)
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        let dictionary = try #require(object as? [String: String])
        return Set(dictionary.keys)
    }
}
