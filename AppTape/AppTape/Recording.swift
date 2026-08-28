//
//  Recording.swift
//  AppTape
//

import AVFoundation
import Foundation
import Observation

/// One Recording, as ADR-0006 defines it: a file in `~/Music/AppTape/` whose **name is its
/// name**. Nothing here indexes the folder; the file is the truth, and Trim and Gain ride in
/// its extended attributes so a Finder rename or move is followed silently.
@Observable
final class Recording: Identifiable {
    /// The file's current path. Not `let`: a Finder rename or move within the Library changes
    /// the path but not the file, and ADR-0006 says that is **followed silently** — the store
    /// relocates the same object rather than treating it as one Recording vanishing and another
    /// appearing (which would drop a live editor's window). `name`, `source` and the rest are
    /// computed from it, so they simply read the new location.
    private(set) var url: URL
    let frameCount: AVAudioFramePosition
    let sampleRate: Double

    /// The source's channel count and sample bit depth, read at open. Export carries both through
    /// untouched — no downmix, no resample (ADR-0005, ADR-0012) — and the size estimate reads the
    /// bit depth to scale the Master-quality (ALAC) rung from the source's own footprint.
    let channelCount: Int
    let sourceBitsPerChannel: Int

    /// The source format the Export inspector estimates and encodes from.
    var sourceFormat: SourceFormat {
        SourceFormat(sampleRate: sampleRate, channelCount: channelCount, bitsPerChannel: sourceBitsPerChannel)
    }

    /// The file's `dev`+`inode`, captured at open (while the file certainly exists) and stable
    /// across a rename or move — so the store can recognise a renamed file as the *same*
    /// Recording. Captured once rather than re-stat'd, because after a rename this object still
    /// holds the old path, which no longer stats.
    let fileIdentity: FileIdentity?

    /// Trim, in seconds. Never alters the file. Mutate it only through `Trim`'s own operations —
    /// nothing outside that type clamps. It is **not** persisted on every mutation: the drag
    /// moves it live, and `persistTrim()` writes the xattr once, at gesture-end (issue #7).
    var trim: Trim

    /// Gain in dB (ADR-0013): the manual Level offset applied on top of any Loudness correction at
    /// Export and in playback. Like Trim it is **not** persisted on every mutation — the slider moves
    /// it live so playback tracks it, and `persistGain()` writes the xattr once, at gesture-end.
    var gain: Double

    /// The Seams padded into this Recording's master (ADR-0010), read once at open. The mark
    /// describes the **master, not the Trim** — ADR-0003 makes the master immutable and the Trim a
    /// view over it, so a badge that vanished when a handle moved would read as a repair. An absent
    /// or unreadable attribute reads as **none**, so a hand-adopted file the app never captured is
    /// correctly unmarked. Immutable like `frameCount`: capture writes it at Stop, the editor reads it.
    let seams: [Seam]

    /// Whether the Recording carries the Seam mark — a single Seam ≥ 250 ms or a total ≥ 250 ms.
    var isSurfacedForSeams: Bool { SeamSurfacing.isSurfaced(seams, sampleRate: sampleRate) }

    /// The Seams big enough to draw as hatched bands in the waveform lane (ADR-0010).
    var laneSeams: [Seam] { SeamSurfacing.laneVisible(seams, sampleRate: sampleRate) }

    /// The one-line editor summary of Seams too small to draw, or nil when there are none. Every
    /// Seam is recorded even when it is not surfaced, and this is where the small ones are told.
    var seamSummary: String? {
        guard !seams.isEmpty, sampleRate > 0 else { return nil }
        let subThreshold = SeamSurfacing.subThreshold(seams, sampleRate: sampleRate)
        let total = SeamSurfacing.totalSeconds(seams, sampleRate: sampleRate)
        if isSurfacedForSeams {
            return "^[\(seams.count) Seam](inflect: true) · \(Self.paddedDurationText(total)) of silence padded in"
        }
        guard !subThreshold.isEmpty else { return nil }
        let subTotal = SeamSurfacing.totalSeconds(subThreshold, sampleRate: sampleRate)
        return "^[\(subThreshold.count) brief Seam](inflect: true) · \(Self.paddedDurationText(subTotal)) padded, too short to hear"
    }

    /// Padded silence read as milliseconds under a second, seconds above — the scale the user can act on.
    private static func paddedDurationText(_ seconds: Double) -> String {
        seconds < 1 ? "\(Int((seconds * 1000).rounded())) ms" : String(format: "%.1f s", seconds)
    }

    /// The peak envelope lives on the Recording, not in a side table (see `EnvelopeLoader`).
    var envelope: Envelope
    var envelopeState: EnvelopeState = .idle

    enum EnvelopeState { case idle, building, done }

    var id: URL { url }

    /// The filename without extension — the Recording's name (ADR-0006).
    var name: String { url.deletingPathExtension().lastPathComponent }

    var duration: Double { sampleRate > 0 ? Double(frameCount) / sampleRate : 0 }

    /// The Source rides in an xattr written at capture (ADR-0006); the filename is the fallback.
    /// A Finder rename that drops the date pattern drops the parsed Source with it — which is why
    /// capture writes the xattr, so a renamed Recording still knows where it came from.
    var source: String {
        if let stored = RecordingMetadata.readSource(from: url) { return stored }
        guard let range = name.range(of: #" \d{4}-\d{2}-\d{2} at "#, options: .regularExpression)
        else { return name }
        return String(name[name.startIndex..<range.lowerBound])
    }

    var recordedAt: Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// Any playable file in the folder is adopted (ADR-0006); an unreadable one is simply not a
    /// Recording, so this fails rather than inventing a broken row.
    init?(url: URL) {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        self.url = url
        self.fileIdentity = FileIdentity(url: url)
        self.frameCount = file.length
        self.sampleRate = file.fileFormat.sampleRate
        self.channelCount = max(1, Int(file.fileFormat.channelCount))
        // A compressed adopted file may report 0 bits/channel; fall back to the master's 32 so the
        // ALAC estimate stays sane (which presets an adopted file even offers is issue #30's call).
        let bits = Int(file.fileFormat.streamDescription.pointee.mBitsPerChannel)
        self.sourceBitsPerChannel = bits > 0 ? bits : 32
        let duration = self.sampleRate > 0 ? Double(file.length) / self.sampleRate : 0
        self.trim = RecordingMetadata.readTrim(from: url, duration: duration) ?? Trim(duration: duration)
        self.gain = RecordingMetadata.readGain(from: url)
        self.seams = RecordingMetadata.readSeams(from: url)
        self.envelope = Envelope(sampleRate: file.fileFormat.sampleRate)
    }

    /// Follow a rename/move: the same file at a new path (ADR-0006). Only the path changes — the
    /// audio, the envelope and the in-memory Trim are the same file's, so they are kept as-is.
    func relocate(to newURL: URL) { url = newURL }

    var trimmedDuration: Double { trim.length }
    var isTrimmed: Bool { !trim.isWholeRecording }

    /// The Trim as a `(startFrame, frameCount)` pair, clamped into the file. The one place the
    /// seconds→frames rounding lives, so Export and the Loudness measurement read exactly the same
    /// frames (ADR-0012/-0013).
    var trimmedFrameRange: (start: Int64, count: Int64) {
        guard sampleRate > 0 else { return (0, 0) }
        let start = Int64((trim.lowerBound * sampleRate).rounded())
        let end = Int64((trim.upperBound * sampleRate).rounded())
        let clampedStart = max(0, min(start, frameCount))
        let clampedEnd = max(clampedStart, min(end, frameCount))
        return (clampedStart, clampedEnd - clampedStart)
    }

    /// The Trim range as `"0:02 – 0:08"`. One place, because the waveform ruler, the transport
    /// and the inspector all show it.
    var trimRangeText: String {
        "\(Format.time(trim.lowerBound)) – \(Format.time(trim.upperBound))"
    }

    /// Reset Trim restores the full range and persists it (issue #7: no undo stack — the range
    /// *is* the state). A whole-Recording Trim is written back as the full range explicitly so a
    /// reopen reads it as untrimmed.
    func resetTrim() {
        trim.reset()
        persistTrim()
    }

    /// Writes the Trim xattr once. Called at gesture-end and on reset — never per drag frame.
    /// Best-effort: losing the write degrades gracefully (ADR-0006), so a failure is swallowed.
    func persistTrim() {
        try? RecordingMetadata.writeTrim(trim, to: url)
    }

    /// Writes the Gain xattr once. Called at slider-drag end and on reset — never per drag frame,
    /// like `persistTrim()`. Best-effort: a lost write degrades gracefully (ADR-0006).
    func persistGain() {
        try? RecordingMetadata.writeGain(gain, to: url)
    }
}

/// A file's identity on disk — device and inode — which survives a rename or a move within the
/// volume, unlike its path. The store uses it to follow a rename silently (ADR-0006).
struct FileIdentity: Hashable {
    let device: dev_t
    let inode: ino_t

    init?(url: URL) {
        var info = stat()
        guard url.withUnsafeFileSystemRepresentation({ path in
            path != nil && stat(path, &info) == 0
        }) else { return nil }
        self.device = info.st_dev
        self.inode = info.st_ino
    }
}

/// A day's worth of Recordings, so the sidebar can group a Library that spans more than one day:
/// with many Recordings a bare "21:51" cannot tell today's Spotify from last Tuesday's, and the
/// same Source repeats within a day.
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

    /// Newest day first, newest Recording first within a day.
    static func group(_ recordings: [Recording]) -> [RecordingDay] {
        let calendar = Calendar.current
        let buckets = Dictionary(grouping: recordings) {
            calendar.startOfDay(for: $0.recordedAt ?? .distantPast)
        }
        return buckets.keys.sorted(by: >).map { RecordingDay(date: $0, recordings: buckets[$0]!) }
    }
}
