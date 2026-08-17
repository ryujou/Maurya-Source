import Foundation
import MauryaResources
import Testing

struct CustomPaletteCoreTests {
    @Test func namesNormalizeAndRejectInvalidValues() throws {
        let names = try PaletteNames(zh: "  Cafe\u{301}  ", ja: " ")
        #expect(names.zh == "Café")
        #expect(names.displayName(locale: .japanese) == "Café")
        #expect(throws: CustomPaletteError.invalidName) { try PaletteNames(zh: "", ja: "") }
        #expect(throws: CustomPaletteError.invalidName) { try PaletteNames(zh: "bad\nname", ja: "") }
    }

    @Test(arguments: ["#12abEF", "#000000", "#FFFFFF"])
    func colorsNormalize(value: String) throws {
        let color = try #require(RGBHex(rawValue: value))
        #expect(color.rawValue == value.uppercased())
    }

    @Test func backupRejectsNonCanonicalBase64AndDuplicateIDs() throws {
        let id = UUID().uuidString.lowercased()
        let avatar = Fixtures.WebP96().base64EncodedString()
        let hash = try AvatarValidator.validate(Fixtures.WebP96()).sha256
        let item = """
            {"id":"\(id)","nameZh":"测试","nameJa":"","hex":"#112233","createdAt":"2026-08-08T00:00:00Z","updatedAt":"2026-08-08T00:00:00Z","avatarWebpBase64":"\(avatar)","avatarSha256":"\(hash)"}
            """
        let duplicate = Data("{\"schemaVersion\":1,\"exportedAt\":\"2026-08-08T00:00:00Z\",\"entries\":[\(item),\(item)]}".utf8)
        #expect(throws: CustomPaletteError.invalidBackup) { try CustomPaletteBackupCodec.decode(duplicate) }
    }
}
