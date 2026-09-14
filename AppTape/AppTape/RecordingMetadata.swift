import Foundation

/// A Recording's metadata rides in extended attributes on the file itself, so the filename
/// stays the name and the attributes survive a Finder move or an APFS clone.
nonisolated enum RecordingMetadata {
    /// The Source the Recording was captured from.
    static let sourceKey = "com.apptape.source"
    /// The Trim, as `"start,end"` in seconds.
    static let trimKey = "com.apptape.trim"
    /// The hand-chosen Gain offset in dB (/#25 own its meaning; the editor only persists it).
    static let gainKey = "com.apptape.gain"
    /// The Dropout list, a JSON array of `{start, frames, cause}` in master frames.
    static let dropoutsKey = "com.apptape.seams"

    static func writeSource(_ source: String, to url: URL) throws {
        try write(source, forKey: sourceKey, to: url)
    }

    static func readSource(from url: URL) -> String? {
        read(forKey: sourceKey, from: url)
    }

    /// The Trim xattr is written once on gesture-end, never per drag frame.
    static func writeTrim(_ trim: Trim, to url: URL) throws {
        try write("\(trim.start),\(trim.end)", forKey: trimKey, to: url)
    }

    /// Hands whatever it found to `Trim`, which is the only thing that decides what a valid Trim is
    /// — it does not validate here (the old reader's own validation could trap).
    static func readTrim(from url: URL, duration: Double) -> Trim? {
        guard let raw = read(forKey: trimKey, from: url) else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return Trim(start: parts[0], end: parts[1], duration: duration)
    }

    static func writeGain(_ gain: Double, to url: URL) throws {
        try write(String(gain), forKey: gainKey, to: url)
    }

    /// Non-finite or missing Gain reads as zero — no offset — rather than poisoning playback.
    static func readGain(from url: URL) -> Double {
        guard let raw = read(forKey: gainKey, from: url), let value = Double(raw), value.isFinite
        else { return 0 }
        return value
    }

    /// A Dropout list rides in one JSON xattr, written once at Stop like the others — never
    /// per frame. `start` and `frames` are integers, so there is no `NaN` to reach the file.
    static func writeDropouts(_ dropouts: [Dropout], to url: URL) throws {
        let dto = dropouts.map { DropoutDTO(start: $0.start, frames: $0.frames, cause: $0.cause.rawValue) }
        let data = try JSONEncoder().encode(dto)
        guard let json = String(data: data, encoding: .utf8) else { return }
        try write(json, forKey: dropoutsKey, to: url)
    }

    /// An unreadable or absent value reads as a clean Recording — the safe direction, and the
    /// same graceful degradation the other attributes give.
    static func readDropouts(from url: URL) -> [Dropout] {
        guard let raw = read(forKey: dropoutsKey, from: url),
            let data = raw.data(using: .utf8),
            let dto = try? JSONDecoder().decode([DropoutDTO].self, from: data)
        else { return [] }
        return dto.compactMap { entry in
            guard let cause = Dropout.Cause(rawValue: entry.cause), entry.frames > 0, entry.start >= 0
            else { return nil }
            return Dropout(start: entry.start, frames: entry.frames, cause: cause)
        }
    }

    private struct DropoutDTO: Codable { var start: Int; var frames: Int; var cause: String }

    private static func write(_ value: String, forKey key: String, to url: URL) throws {
        let data = Data(value.utf8)
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            data.withUnsafeBytes { bytes in
                setxattr(path, key, bytes.baseAddress, data.count, 0, 0)
            }
        }
        if result != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    private static func read(forKey key: String, from url: URL) -> String? {
        url.withUnsafeFileSystemRepresentation { path -> String? in
            let length = getxattr(path, key, nil, 0, 0, 0)
            guard length > 0 else { return nil }
            var data = Data(count: length)
            let read = data.withUnsafeMutableBytes { getxattr(path, key, $0.baseAddress, length, 0, 0) }
            guard read >= 0 else { return nil }
            return String(data: data.prefix(read), encoding: .utf8)
        }
    }
}
