import CryptoKit
import Foundation

/// Signs the exact protobuf bytes sent to the v2 mobile API. The P-256 private
/// key is device-only Keychain material; the server stores only its public key.
public struct APIRequestSigner {
    public struct SignedBody {
        public let data: Data
        public let headers: [String: String]
    }

    private static let privateKeyKey = "api-signing-private-p256"
    private static let keyIdKey = "api-signing-key-id"

    private let privateKey: P256.Signing.PrivateKey
    public let keyId: String

    public init() throws {
        if let raw = KeychainStore.load(key: Self.privateKeyKey),
           let key = try? P256.Signing.PrivateKey(rawRepresentation: raw) {
            privateKey = key
        } else {
            let key = P256.Signing.PrivateKey()
            try KeychainStore.save(key: Self.privateKeyKey, data: key.rawRepresentation)
            privateKey = key
        }
        if let existing = KeychainStore.loadString(key: Self.keyIdKey) {
            keyId = existing
        } else {
            let fresh = UUID().uuidString.lowercased()
            try KeychainStore.saveString(key: Self.keyIdKey, value: fresh)
            keyId = fresh
        }
    }

    public init(testingPrivateKey: P256.Signing.PrivateKey, keyId: String) {
        privateKey = testingPrivateKey
        self.keyId = keyId
    }

    public var publicKeyBase64: String { privateKey.publicKey.x963Representation.base64EncodedString() }

    public func sign(method: String, path: String, json: Data) throws -> SignedBody {
        let body = ProtobufEnvelope.encode(json: json, requestId: UUID().uuidString, serverTimeMs: 0)
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let nonce = UUID().uuidString.lowercased()
        let digest = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        let canonical = "\(method.uppercased())\n\(path)\n\(timestamp)\n\(nonce)\n\(digest)"
        let signature = try privateKey.signature(for: Data(canonical.utf8)).derRepresentation.base64EncodedString()
        return SignedBody(data: body, headers: [
            "Content-Type": "application/x-protobuf",
            "Accept": "application/x-protobuf",
            "X-API-Key-ID": keyId,
            "X-API-Timestamp": String(timestamp),
            "X-API-Nonce": nonce,
            "X-API-Signature": signature,
        ])
    }
}

public enum ProtobufEnvelope {
    public static func encode(json: Data, requestId: String, serverTimeMs: Int64) -> Data {
        var output = Data()
        appendField(1, bytes: json, to: &output)
        appendField(2, bytes: Data(requestId.utf8), to: &output)
        output.append(0x18)
        appendVarint(UInt64(bitPattern: serverTimeMs), to: &output)
        return output
    }

    public static func decodeJSON(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        var cursor = 0
        while cursor < bytes.count {
            let key = try readVarint(bytes, cursor: &cursor)
            let field = Int(key >> 3), wire = Int(key & 7)
            if wire == 2 {
                let length = Int(try readVarint(bytes, cursor: &cursor))
                guard cursor + length <= bytes.count else { throw APIError.invalidResponse }
                let value = Data(bytes[cursor..<(cursor + length)])
                cursor += length
                if field == 1 { return value }
            } else if wire == 0 {
                _ = try readVarint(bytes, cursor: &cursor)
            } else {
                throw APIError.invalidResponse
            }
        }
        throw APIError.invalidResponse
    }

    private static func appendField(_ number: UInt64, bytes: Data, to output: inout Data) {
        appendVarint((number << 3) | 2, to: &output)
        appendVarint(UInt64(bytes.count), to: &output)
        output.append(bytes)
    }

    private static func appendVarint(_ value: UInt64, to output: inout Data) {
        var value = value
        repeat {
            var byte = UInt8(value & 0x7f)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            output.append(byte)
        } while value != 0
    }

    private static func readVarint(_ bytes: [UInt8], cursor: inout Int) throws -> UInt64 {
        var result: UInt64 = 0, shift: UInt64 = 0
        while cursor < bytes.count, shift <= 63 {
            let byte = bytes[cursor]
            cursor += 1
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        throw APIError.invalidResponse
    }
}
