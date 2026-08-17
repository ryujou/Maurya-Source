import Testing

@testable import Maurya

struct SupportColorSelectionTests {
    @Test(
        "RGB support colors map to device HSV",
        arguments: [
            ("#FF0000", UInt16(0), UInt16(255), UInt16(255)),
            ("#00FF00", UInt16(120), UInt16(255), UInt16(255)),
            ("#0000FF", UInt16(240), UInt16(255), UInt16(255)),
            ("#808080", UInt16(0), UInt16(0), UInt16(128)),
        ]
    )
    func hsvMapping(fixture: (String, UInt16, UInt16, UInt16)) throws {
        let hsv = try #require(SupportColorSelection.deviceHSV(hex: fixture.0))

        #expect(hsv.hue == fixture.1)
        #expect(hsv.saturation == fixture.2)
        #expect(hsv.value == fixture.3)
    }
}
