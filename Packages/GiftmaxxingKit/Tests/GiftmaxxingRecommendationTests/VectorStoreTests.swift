import XCTest
@testable import GiftmaxxingRecommendation
import GiftmaxxingCore

// The on-device vector math that replaced the server's per-request similarity
// scoring (GET /vectors int8 payloads → cosine against the taste centroid).
final class VectorStoreTests: XCTestCase {

    // ── Pure cosine ──────────────────────────────────────────────────────────

    func testCosineOfIdenticalVectorsIsOne() {
        let v: [Float] = [0.3, -0.5, 0.8, 0.1]
        XCTAssertEqual(VectorStore.cosine(v, v), 1.0, accuracy: 1e-5)
    }

    func testCosineOfOrthogonalVectorsIsZero() {
        XCTAssertEqual(VectorStore.cosine([1, 0], [0, 1]), 0.0, accuracy: 1e-6)
    }

    func testCosineOfOppositeVectorsIsMinusOne() {
        XCTAssertEqual(VectorStore.cosine([1, 2, 3], [-1, -2, -3]), -1.0, accuracy: 1e-5)
    }

    func testCosineWithZeroVectorIsZeroNotNaN() {
        let c = VectorStore.cosine([0, 0, 0], [1, 2, 3])
        XCTAssertEqual(c, 0)
        XCTAssertFalse(c.isNaN)
    }

    // ── int8 quantization roundtrip (server wire format) ────────────────────

    // Quantize exactly like the server (infra/src/handler.mjs /vectors route):
    // unit-normalize, scale = maxAbs/127, int8 round, base64.
    private func serverQuantize(_ vector: [Float]) -> (base64: String, scale: Float) {
        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        let unit = vector.map { $0 / norm }
        let maxAbs = unit.map(abs).max() ?? 1
        let scale = maxAbs > 0 ? maxAbs / 127 : 1
        let quantized = unit.map { Int8(max(-127, min(127, ($0 / scale).rounded()))) }
        let data = quantized.withUnsafeBufferPointer { Data(buffer: $0) }
        return (data.base64EncodedString(), scale)
    }

    private func randomVector(dim: Int, seed: UInt64) -> [Float] {
        var state = seed
        return (0..<dim).map { _ in
            // xorshift64 — deterministic across runs, no Foundation RNG needed.
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Float(Int64(bitPattern: state) % 1000) / 1000.0
        }
    }

    func testQuantizationRoundtripPreservesSimilarity() async throws {
        let store = VectorStore()
        let original = randomVector(dim: 1024, seed: 42)
        let (base64, scale) = serverQuantize(original)

        await store.upsert(key: "test-roundtrip-a", base64: base64, scale: scale)
        let sim = await store.similarity(key: "test-roundtrip-a", to: original)

        let unwrapped = try XCTUnwrap(sim)
        XCTAssertEqual(unwrapped, 1.0, accuracy: 0.005, "int8 roundtrip should lose <0.5% cosine fidelity")
    }

    func testCentroidAveragesCachedVectors() async throws {
        let store = VectorStore()
        let a = randomVector(dim: 64, seed: 7)
        let b = randomVector(dim: 64, seed: 99)
        let (qa, sa) = serverQuantize(a)
        let (qb, sb) = serverQuantize(b)
        await store.upsert(key: "test-centroid-a", base64: qa, scale: sa)
        await store.upsert(key: "test-centroid-b", base64: qb, scale: sb)

        let centroid = await store.centroid(of: ["test-centroid-a", "test-centroid-b", "test-missing"])
        let c = try XCTUnwrap(centroid)
        XCTAssertEqual(c.count, 64)
        // The mean of two unit vectors must be positively similar to both.
        XCTAssertGreaterThan(VectorStore.cosine(c, a.unitNormalized()), 0)
        XCTAssertGreaterThan(VectorStore.cosine(c, b.unitNormalized()), 0)
    }

    func testMissingKeysReportsOnlyAbsentOnes() async {
        let store = VectorStore()
        let (q, s) = serverQuantize(randomVector(dim: 16, seed: 3))
        await store.upsert(key: "test-missing-present", base64: q, scale: s)

        let missing = await store.missingKeys(from: ["test-missing-present", "test-missing-absent"])
        XCTAssertEqual(missing, ["test-missing-absent"])
    }

    func testSimilarityForUnknownKeyIsNil() async {
        let store = VectorStore()
        let sim = await store.similarity(key: "test-never-upserted", to: [1, 2, 3])
        XCTAssertNil(sim)
    }
}

private extension Array where Element == Float {
    func unitNormalized() -> [Float] {
        let norm = sqrt(reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return self }
        return map { $0 / norm }
    }
}
