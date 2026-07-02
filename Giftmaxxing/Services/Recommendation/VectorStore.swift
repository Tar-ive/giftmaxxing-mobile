import Foundation
import Accelerate

// On-device embedding cache + similarity math. The server's S3 Vectors index
// stores 1024-d Titan Multimodal embeddings; GET /vectors serves them int8-
// quantized (~1 KB each). We cache the vectors of items the user has actually
// seen or engaged with, then do the taste-centroid + cosine math locally with
// vDSP instead of a Lambda GetVectors call per recommendation request.
//
// Size budget: 4096 vectors x 1 KB ≈ 4 MB on disk / in RAM — far below any
// iOS memory or app-size concern. A full 150-candidate similarity pass is a
// few hundred microseconds of vDSP time, so battery impact is negligible.

actor VectorStore {
    static let shared = VectorStore()

    struct QuantizedVector: Codable {
        let scale: Float
        let data: Data          // int8 components, value[i] = Int8(bitPattern:) * scale
        var lastAccess: Double

        func dequantized() -> [Float] {
            var out = [Float](repeating: 0, count: data.count)
            data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                let int8Buf = raw.bindMemory(to: Int8.self)
                vDSP.convertElements(of: int8Buf, to: &out)
            }
            vDSP.multiply(scale, out, result: &out)
            return out
        }
    }

    private var vectors: [String: QuantizedVector] = [:]
    private var loaded = false
    private var saveTask: Task<Void, Never>?
    private static let capacity = 4096

    // MARK: - Ingest

    // Server payload: base64(int8 bytes) + per-vector scale (unit-normalized
    // before quantization server-side, so dot product ≈ cosine similarity).
    func upsert(key: String, base64: String, scale: Float) {
        loadIfNeeded()
        guard let data = Data(base64Encoded: base64), !data.isEmpty else { return }
        vectors[key] = QuantizedVector(scale: scale, data: data, lastAccess: Date().timeIntervalSince1970)
        evictIfNeeded()
        scheduleSave()
    }

    func contains(_ key: String) -> Bool {
        loadIfNeeded()
        return vectors[key] != nil
    }

    func missingKeys(from keys: [String]) -> [String] {
        loadIfNeeded()
        return keys.filter { vectors[$0] == nil }
    }

    var count: Int {
        loadIfNeeded()
        return vectors.count
    }

    // MARK: - Similarity math (all vDSP)

    // Mean of the seed vectors = the user's taste point in Titan space.
    // Mirrors getCentroid() in infra/src/handler.mjs, moved on-device.
    func centroid(of keys: [String]) -> [Float]? {
        loadIfNeeded()
        let found = keys.compactMap { touch($0) }
        guard !found.isEmpty, let dim = found.first?.count else { return nil }
        var acc = [Float](repeating: 0, count: dim)
        for v in found where v.count == dim {
            vDSP.add(acc, v, result: &acc)
        }
        vDSP.divide(acc, Float(found.count), result: &acc)
        return acc
    }

    // Cosine similarity of one cached item against a query vector.
    func similarity(key: String, to query: [Float]) -> Float? {
        loadIfNeeded()
        guard let v = touch(key), v.count == query.count else { return nil }
        return Self.cosine(v, query)
    }

    // Batch: similarity for each requested key (nil-skipped), e.g. scoring a
    // candidate page against the taste centroid.
    func similarities(keys: [String], to query: [Float]) -> [String: Float] {
        loadIfNeeded()
        var out: [String: Float] = [:]
        out.reserveCapacity(keys.count)
        for key in keys {
            if let v = touch(key), v.count == query.count {
                out[key] = Self.cosine(v, query)
            }
        }
        return out
    }

    // Local kNN over everything cached — powers instant/offline "similar to
    // your taste" rows without any server round trip.
    func nearest(to query: [Float], k: Int, excluding: Set<String> = []) -> [(key: String, score: Float)] {
        loadIfNeeded()
        var scored: [(String, Float)] = []
        scored.reserveCapacity(vectors.count)
        for (key, qv) in vectors where !excluding.contains(key) {
            let v = qv.dequantized()
            guard v.count == query.count else { continue }
            scored.append((key, Self.cosine(v, query)))
        }
        return Array(scored.sorted { $0.1 > $1.1 }.prefix(k))
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        let dot = vDSP.dot(a, b)
        let na = sqrt(vDSP.sumOfSquares(a))
        let nb = sqrt(vDSP.sumOfSquares(b))
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na * nb)
    }

    // MARK: - Internals

    private func touch(_ key: String) -> [Float]? {
        guard var qv = vectors[key] else { return nil }
        qv.lastAccess = Date().timeIntervalSince1970
        vectors[key] = qv
        return qv.dequantized()
    }

    private func evictIfNeeded() {
        guard vectors.count > Self.capacity else { return }
        // Drop the least-recently-used fifth in one pass.
        let sorted = vectors.sorted { $0.value.lastAccess < $1.value.lastAccess }
        for (key, _) in sorted.prefix(Self.capacity / 5) {
            vectors.removeValue(forKey: key)
        }
    }

    // MARK: - Persistence

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recommendation", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("vector-cache.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode([String: QuantizedVector].self, from: data) {
            vectors = decoded
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [vectors] in
            try? await Task.sleep(nanoseconds: 5_000_000_000) // debounce 5s
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(vectors) {
                try? data.write(to: Self.fileURL, options: .atomic)
            }
        }
    }
}
