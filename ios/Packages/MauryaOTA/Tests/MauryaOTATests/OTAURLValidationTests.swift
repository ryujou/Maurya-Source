import Foundation
import Testing

@testable import MauryaOTA

@Suite("OTA URL validation")
struct OTAURLValidationTests {
    private let hosts: Set<String> = ["updates.example"]

    @Test func acceptsOnlyAllowlistedHTTPSURL() throws {
        try URLSessionOTAClient.validate(
            url: try #require(URL(string: "https://updates.example/stable/firmware.bin")),
            allowedHosts: hosts
        )
    }

    @Test(arguments: [
        "http://updates.example/firmware.bin",
        "https://attacker.example/firmware.bin",
        "https://user:secret@updates.example/firmware.bin",
    ])
    func rejectsUnsafeInitialOrRedirectDestination(value: String) throws {
        let url = try #require(URL(string: value))
        #expect(throws: OTAFailure.self) {
            try URLSessionOTAClient.validate(url: url, allowedHosts: hosts)
        }
    }
}
