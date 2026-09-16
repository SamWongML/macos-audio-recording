import Foundation

/// A Recording's peak envelope kept as derived data, so the first open after a restart does not
/// decode the whole Library again. It holds a picture, never a fact.
nonisolated enum EnvelopeCache {
    private static let magic = Data("APTP".utf8)
    private static let version: UInt32 = 1
    private static let headerLength = 24

    /// `~/Library/Caches/com.samwongml.AppTape/peaks/`. The app is not sandboxed, so this is the
    /// ordinary per-user cache location.
    static let directory: URL = {
        let caches =
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches", isDirectory: true)
        return
            caches
            .appendingPathComponent("com.samwongml.AppTape", isDirectory: true)
            .appendingPathComponent("peaks", isDirectory: true)
    }()

    /// The file's device, inode and length: a rename or a move within the volume keeps all three,
    /// and a file whose audio changed keeps none of them.
    static func key(identity: FileIdentity, byteCount: Int64) -> String {
        "\(identity.device)-\(identity.inode)-\(byteCount).peaks"
    }

    /// A wrong magic, an unknown version or a short file all read as a miss — a corrupt cache must
    /// degrade to a rescan, never to a wrong picture.
    static func read(key: String, in directory: URL) -> Envelope? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(key)),
            data.count >= headerLength,
            data.prefix(4) == magic
        else { return nil }

        return data.withUnsafeBytes { raw -> Envelope? in
            func u32(_ offset: Int) -> UInt32 {
                UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
            }
            guard u32(4) == version else { return nil }
            let sampleRate = Double(
                bitPattern: UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: 8, as: UInt64.self)))
            let framesPerBucket = Int(u32(16))
            let bucketCount = Int(u32(20))
            guard framesPerBucket > 0, data.count == headerLength + bucketCount * 12 else { return nil }

            // One copy per channel rather than one conversion per sample: a 20-minute master is
            // ~225,000 buckets, and macOS is little-endian, so the stored bytes are already Floats.
            func floats(at offset: Int) -> [Float] {
                guard bucketCount > 0, let base = raw.baseAddress else { return [] }
                return [Float](unsafeUninitializedCapacity: bucketCount) { buffer, count in
                    memcpy(buffer.baseAddress!, base + offset, bucketCount * MemoryLayout<Float>.size)
                    count = bucketCount
                }
            }
            var envelope = Envelope(framesPerBucket: framesPerBucket, sampleRate: sampleRate)
            envelope.mins = floats(at: headerLength)
            envelope.maxs = floats(at: headerLength + bucketCount * 4)
            envelope.rms = floats(at: headerLength + bucketCount * 8)
            envelope.complete = true
            return envelope
        }
    }

    /// Best-effort: a cache that cannot be written costs a rescan next time and nothing else.
    static func write(_ envelope: Envelope, key: String, in directory: URL) {
        let bucketCount = envelope.mins.count
        guard envelope.complete, envelope.maxs.count == bucketCount, envelope.rms.count == bucketCount
        else { return }
        ensure(directory)

        var data = Data(capacity: headerLength + bucketCount * 12)
        data.append(magic)
        data.append(littleEndian: version)
        data.append(littleEndian: envelope.sampleRate.bitPattern)
        data.append(littleEndian: UInt32(envelope.framesPerBucket))
        data.append(littleEndian: UInt32(bucketCount))
        for channel in [envelope.mins, envelope.maxs, envelope.rms] {
            channel.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                data.append(base.assumingMemoryBound(to: UInt8.self), count: raw.count)
            }
        }
        try? data.write(to: directory.appendingPathComponent(key), options: .atomic)
    }

    /// Drop every cached picture no current Recording claims.
    static func purge(keeping keys: Set<String>, in directory: URL) {
        let contents =
            (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
            ?? []
        for url in contents where !keys.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func ensure(_ directory: URL) {
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var mutable = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true  // derived data has no place in Time Machine
        try? mutable.setResourceValues(values)
    }
}

nonisolated extension Data {
    fileprivate mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
