import XCTest
@testable import Giftmaxxing
import GiftmaxxingCore

// Wire-format contract with the web app: /invite/<base64url(JSON)> links built
// on iOS must decode with web/lib/invite.ts decodeInvite(). These tests pin the
// encoding so a refactor can't silently break cross-platform links.
final class InviteLinkTests: XCTestCase {

    // Replicates the web's decodeInvite (base64url → JSON object).
    private func decode(_ code: String) throws -> [String: Any] {
        var padded = code.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 { padded += "=" }
        let data = try XCTUnwrap(Data(base64Encoded: padded), "code is not valid base64url")
        let obj = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(obj as? [String: Any], "payload is not a JSON object")
    }

    func testRoundtripMatchesWebFormat() throws {
        let url = try XCTUnwrap(InviteLink.buildURL(
            inviterName: "Alex",
            senderId: "anon-1234",
            to: "Sam",
            occasion: "birthday",
            date: "2026-08-01"
        ))

        XCTAssertTrue(url.absoluteString.hasPrefix("\(InviteLink.siteURL)/invite/"))

        let payload = try decode(url.lastPathComponent)
        XCTAssertEqual(payload["name"] as? String, "Alex")
        XCTAssertEqual(payload["senderId"] as? String, "anon-1234")
        XCTAssertEqual(payload["to"] as? String, "Sam")
        XCTAssertEqual(payload["occasion"] as? String, "birthday")
        XCTAssertEqual(payload["date"] as? String, "2026-08-01")
    }

    func testCodeIsURLSafe() throws {
        // Long unicode-ish name forces base64 padding + high bytes.
        let url = try XCTUnwrap(InviteLink.buildURL(
            inviterName: "Zoë Werkmeister-Ångström",
            senderId: "anon-x"
        ))
        let code = url.lastPathComponent
        XCTAssertFalse(code.contains("="), "base64url must strip padding")
        XCTAssertFalse(code.contains("+"), "base64url must not contain +")
        XCTAssertFalse(code.contains("/"), "base64url must not contain /")
        let payload = try decode(code)
        XCTAssertEqual(payload["name"] as? String, "Zoë Werkmeister-Ångström")
    }

    func testBlankNameFallsBackToAFriend() throws {
        let url = try XCTUnwrap(InviteLink.buildURL(inviterName: "   ", senderId: nil))
        let payload = try decode(url.lastPathComponent)
        XCTAssertEqual(payload["name"] as? String, "A friend")
    }

    func testEmptyOptionalsAreOmitted() throws {
        let url = try XCTUnwrap(InviteLink.buildURL(
            inviterName: "Alex",
            senderId: nil,
            to: "  ",
            occasion: "",
            date: nil
        ))
        let payload = try decode(url.lastPathComponent)
        XCTAssertNil(payload["senderId"])
        XCTAssertNil(payload["to"])
        XCTAssertNil(payload["occasion"])
        XCTAssertNil(payload["date"])
        XCTAssertNil(payload["challengeId"], "no server challenge → key omitted (legacy local-deck flow)")
    }

    // Server-side challenge links: the guest page keys off payload.challengeId
    // to fetch GET /challenges/{id} instead of building a local deck.
    func testChallengeIdRidesInPayload() throws {
        let url = try XCTUnwrap(InviteLink.buildURL(
            inviterName: "Alex",
            senderId: "user_1",
            to: "Sam",
            challengeId: "chal_abc123"
        ))
        let payload = try decode(url.lastPathComponent)
        XCTAssertEqual(payload["challengeId"] as? String, "chal_abc123")
        XCTAssertEqual(payload["name"] as? String, "Alex")
    }
}
