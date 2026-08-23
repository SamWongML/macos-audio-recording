//  PROTOTYPE — throwaway. The Library is the folder (ADR-0006), so this is a directory
//  listing plus the extended attributes that carry Trim and Gain.

import AVFoundation
import Foundation


/// A Trim: the two points that select which part of a Recording is Exported.
///
/// **Invalid states are unrepresentable.** Every mutation goes through this type, so no call
/// site ever clamps, and the three invariants below hold by construction:
///
/// - `0 <= start`
/// - `end <= duration`
/// - `end - start >= minimumLength` (unless the Recording is itself shorter than that, in
///   which case the Trim is the whole thing and neither point can move)
///
/// This exists because the ad-hoc version did not hold any of them. The clamping was written
/// out by hand at five separate call sites — drag, keyboard nudge, Mark In, Mark Out, and the
/// extended attribute reader — as a pair of nested `min`/`max` per site. Two constraints, applied
/// in sequence, and **whichever was applied second won**, so each one could push the value
/// straight through the other. Fuzzing the old logic produced all four failures:
///
/// ```
/// dragEnd    from (29.900, 29.950) -> t=-5   gives  (29.900, 30.100)   past the end of the file
/// dragStart  from ( 0.000,  0.050) -> t=-5   gives  (-0.150,  0.050)   before the beginning
/// markOut    from (30.000, 30.000) -> p=-5   gives  (30.000, 30.000)   start and end crossed
/// markIn     from ( 0.000,  0.050) -> p=-5   gives  ( 0.000,  0.050)   shorter than the minimum
/// ```
///
/// The fix is not a better pair of clamps. It is to clamp **once**, into an interval that is
/// provably non-empty, and to have exactly one place that knows how.
struct Trim: Equatable {
    /// An Export has to contain something.
    static let minimumLength = 0.2

    private(set) var start: Double
    private(set) var end: Double
    let duration: Double

    /// A Recording shorter than the minimum cannot be trimmed at all — the whole thing is the
    /// Trim. #30 owns what else an adopted file that short should do.
    var isFixed: Bool { duration < Self.minimumLength }

    init(duration: Double) {
        self.duration = duration.isFinite ? Swift.max(0, duration) : 0
        self.start = 0
        self.end = self.duration
    }

    /// Sanitising initialiser: takes any two numbers from anywhere — an extended attribute
    /// written by an older build, a file that has since been replaced by a shorter one — and
    /// lands on a valid Trim rather than trusting them or trapping.
    init(start: Double, end: Double, duration: Double) {
        self = Trim(duration: duration)
        guard !isFixed else { return }
        setEnd(end)
        setStart(start)
    }

    var range: ClosedRange<Double> { start...end }
    var lowerBound: Double { start }
    var upperBound: Double { end }
    var length: Double { end - start }
    var isWholeRecording: Bool { start <= 0.0005 && end >= duration - 0.0005 }

    /// The interval `start` is allowed to occupy. Non-empty whenever the Recording is longer
    /// than the minimum, because `end` is itself never below `minimumLength`.
    private var startLimits: ClosedRange<Double> { 0...Swift.max(0, end - Self.minimumLength) }
    private var endLimits: ClosedRange<Double> {
        Swift.min(duration, start + Self.minimumLength)...duration
    }

    /// Non-finite input leaves the Trim alone rather than moving a handle to nowhere.
    /// NaN is reachable: the lane converts a pixel to a time with `px / width * span`, and a
    /// zero-width lane during a layout pass makes that `inf * 0`. `min` and `max` propagate
    /// NaN silently, so without this guard a single bad layout would write `nan` into the
    /// extended attribute and the Recording would come back broken on the next launch.
    /// Fuzzing found this and nothing else once the clamping was centralised.
    mutating func setStart(_ t: Double) {
        guard !isFixed, t.isFinite else { return }
        start = t.clamped(to: startLimits)
    }

    mutating func setEnd(_ t: Double) {
        guard !isFixed, t.isFinite else { return }
        end = t.clamped(to: endLimits)
    }

    mutating func nudgeStart(by delta: Double) { setStart(start + delta) }
    mutating func nudgeEnd(by delta: Double) { setEnd(end + delta) }

    mutating func reset() {
        start = 0
        end = duration
    }
}

extension Double {
    func clamped(to limits: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, limits.lowerBound), limits.upperBound)
    }
}

/// One Recording, as ADR-0006 defines it: a file in ~/Music/AppTape whose *name is its name*.
@Observable
final class Recording: Identifiable {
    let url: URL
    let frameCount: AVAudioFramePosition
    let sampleRate: Double

    /// Trim, in seconds. Never alters the file — written back as an xattr on change.
    /// Mutate it only through `Trim`'s own operations; nothing outside that type clamps.
    var trim: Trim {
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
        self.trim = Xattr.readTrim(from: url, duration: duration) ?? Trim(duration: duration)
        self.envelope = Envelope(sampleRate: file.fileFormat.sampleRate)
    }

    var trimmedDuration: Double { trim.length }
    var isTrimmed: Bool { !trim.isWholeRecording }

    func resetTrim() { trim.reset() }
}

/// A day's worth of Recordings. Any sidebar over a Library that spans more than one day
/// needs this: with 28 Recordings the row subtitle "21:51" cannot tell today's Spotify from
/// last Tuesday's, and three of the Sources repeat.
struct RecordingDay: Identifiable {
    let date: Date
    let recordings: [Recording]
    var id: Date { date }

    var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: date, to: .now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
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

    /// Newest day first, newest Recording first within a day.
    static func grouped(_ recordings: [Recording]) -> [RecordingDay] {
        let calendar = Calendar.current
        let buckets = Dictionary(grouping: recordings) {
            calendar.startOfDay(for: $0.recordedAt ?? .distantPast)
        }
        return buckets.keys.sorted(by: >).map { RecordingDay(date: $0, recordings: buckets[$0]!) }
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

    /// Note what this no longer does: it does not validate. It hands whatever it found to
    /// `Trim`, which is the only thing that decides what a valid Trim is. The old version
    /// checked `parts[1] > parts[0]` and then applied `min(parts[1], duration)`, which could
    /// pull the end back below the start and trap on `a...b` — reachable simply by pointing
    /// the app at a shorter file with the same name.
    static func readTrim(from url: URL, duration: Double) -> Trim? {
        guard let raw = readString(trimKey, from: url) else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return Trim(start: parts[0], end: parts[1], duration: duration)
    }

    static func writeTrim(_ trim: Trim, to url: URL) {
        writeString("\(trim.start),\(trim.end)", name: trimKey, to: url)
    }
}
