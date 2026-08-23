//  PROTOTYPE — throwaway. The Library is the folder (ADR-0006), so this is a directory
//  listing plus the extended attributes that carry Trim and Gain.

import AVFoundation
import Foundation

/// One Recording, as ADR-0006 defines it: a file in ~/Music/AppTape whose *name is its name*.
@Observable
final class Recording: Identifiable {
    let url: URL
    let frameCount: AVAudioFramePosition
    let sampleRate: Double

    /// Trim, in seconds. Never alters the file — written back as an xattr on change.
    var trim: ClosedRange<Double> {
        didSet { Xattr.writeTrim(trim, to: url) }
    }

    /// Gain in dB. #24 / #25 own what this means at Export; the editor only reserves room.
    var gain: Double = 0

    /// The peak envelope lives on the Recording, not in a side table — see EnvelopeLoader.
    var envelope = Envelope()
    var envelopeState: EnvelopeState = .idle

    enum EnvelopeState { case idle, building, done }

    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
    var duration: Double { Double(frameCount) / sampleRate }

    /// "Google Chrome 2026-08-23 at 11.47.31" -> "Google Chrome". A Finder rename can break
    /// this, which is exactly the cost ADR-0006 accepted; the xattr is the fallback.
    var source: String {
        if let stored = Xattr.readString("com.samwongml.apptape.source", from: url) { return stored }
        guard let range = name.range(of: #" \d{4}-\d{2}-\d{2} at "#, options: .regularExpression)
        else { return name }
        return String(name[name.startIndex..<range.lowerBound])
    }

    var recordedAt: Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    var byteSize: Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
    }

    init?(url: URL) {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        self.url = url
        self.frameCount = file.length
        self.sampleRate = file.fileFormat.sampleRate
        let duration = Double(file.length) / file.fileFormat.sampleRate
        self.trim = Xattr.readTrim(from: url, duration: duration) ?? 0...duration
        self.envelope = Envelope(sampleRate: file.fileFormat.sampleRate)
    }

    var trimmedDuration: Double { trim.upperBound - trim.lowerBound }
    var isTrimmed: Bool { trim.lowerBound > 0.0005 || trim.upperBound < duration - 0.0005 }

    func resetTrim() { trim = 0...duration }
}

enum Library {
    static var folder: URL {
        FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0]
            .appending(path: "AppTape", directoryHint: .isDirectory)
    }

    /// Newest first. Any playable file in the folder is adopted (ADR-0006); #30 owns the limits.
    static func load() -> [Recording] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])) ?? []
        return urls.compactMap(Recording.init(url:))
            .sorted { ($0.recordedAt ?? .distantPast) > ($1.recordedAt ?? .distantPast) }
    }
}

// MARK: - Extended attributes

/// ADR-0006 puts Trim and Gain on the file itself so a Finder rename is followed silently.
/// Worth exercising in the prototype: quit, rename a fixture in Finder, reopen.
enum Xattr {
    static func readString(_ name: String, from url: URL) -> String? {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return nil }
            let size = getxattr(path, name, nil, 0, 0, 0)
            guard size > 0 else { return nil }
            var bytes = [UInt8](repeating: 0, count: size)
            guard getxattr(path, name, &bytes, size, 0, 0) == size else { return nil }
            return String(bytes: bytes, encoding: .utf8)
        }
    }

    static func writeString(_ value: String, name: String, to url: URL) {
        _ = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            let bytes = Array(value.utf8)
            return setxattr(path, name, bytes, bytes.count, 0, 0)
        }
    }

    private static let trimKey = "com.samwongml.apptape.trim"

    static func readTrim(from url: URL, duration: Double) -> ClosedRange<Double>? {
        guard let raw = readString(trimKey, from: url) else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2, parts[0] >= 0, parts[1] > parts[0] else { return nil }
        return parts[0]...min(parts[1], duration)
    }

    static func writeTrim(_ trim: ClosedRange<Double>, to url: URL) {
        writeString("\(trim.lowerBound),\(trim.upperBound)", name: trimKey, to: url)
    }
}
