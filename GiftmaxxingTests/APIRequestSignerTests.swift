import XCTest
import CryptoKit
@testable import Giftmaxxing

final class APIRequestSignerTests: XCTestCase {
    func testEnvelopeRoundTrip() throws {
        let json = Data(#"{"surface":"challenge_learn"}"#.utf8)
        let wire = ProtobufEnvelope.encode(json: json, requestId: "test-request", serverTimeMs: 42)
        XCTAssertEqual(try ProtobufEnvelope.decodeJSON(wire), json)
    }

    func testSignedBodyUsesRequiredHeaders() throws {
        let signed = try APIRequestSigner(
            testingPrivateKey: P256.Signing.PrivateKey(), keyId: "unit-test-device"
        ).sign(method: "POST", path: "/v2/recommendations", json: Data("{}".utf8))
        XCTAssertFalse(signed.data.isEmpty)
        XCTAssertEqual(signed.headers["Content-Type"], "application/x-protobuf")
        XCTAssertNotNil(signed.headers["X-API-Signature"])
        XCTAssertNotNil(signed.headers["X-API-Nonce"])
    }
}
