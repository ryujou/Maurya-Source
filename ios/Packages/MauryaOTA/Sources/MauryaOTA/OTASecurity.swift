import CryptoKit
import Foundation
import Security

public struct RSASHA256ManifestVerifier: OTASignatureVerifying {
    private let publicKeys: [String: Data]

    /// Public keys are X.509 SubjectPublicKeyInfo DER values. Private signing
    /// material must remain in the release signing service and is never accepted here.
    public init(publicKeys: [String: Data]) {
        self.publicKeys = publicKeys
    }

    public func verify(message: Data, detachedSignature: Data, keyID: String) throws {
        guard let encodedKey = publicKeys[keyID] else {
            throw OTAFailure.unknownSigningKey(keyID)
        }
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
        ]
        var creationError: Unmanaged<CFError>?
        guard
            let key = SecKeyCreateWithData(
                encodedKey as CFData,
                attributes as CFDictionary,
                &creationError
            )
        else {
            _ = creationError?.takeRetainedValue()
            throw OTAFailure.invalidManifest("Invalid RSA public key for \(keyID)")
        }
        let signature = Self.decodeSignature(detachedSignature)
        var verificationError: Unmanaged<CFError>?
        let valid = SecKeyVerifySignature(
            key,
            .rsaSignatureMessagePKCS1v15SHA256,
            message as CFData,
            signature as CFData,
            &verificationError
        )
        if let verificationError {
            _ = verificationError.takeRetainedValue()
        }
        guard valid else { throw OTAFailure.invalidSignature }
    }

    private static func decodeSignature(_ signature: Data) -> Data {
        guard let text = String(data: signature, encoding: .ascii) else { return signature }
        return Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? signature
    }
}

enum OTADigest {
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func bytes(fromHex text: String) throws -> Data {
        guard text.count == 64, text.allSatisfy(\.isHexDigit) else {
            throw OTAFailure.invalidManifest("sha256 must contain exactly 64 hexadecimal characters")
        }
        var result = Data(capacity: 32)
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else {
                throw OTAFailure.invalidManifest("sha256 is malformed")
            }
            result.append(byte)
            index = next
        }
        return result
    }
}
