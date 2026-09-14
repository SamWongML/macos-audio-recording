import AVFoundation
import Foundation
import Observation

/// One Recording, as defines it: a file in `~/Music/AppTape/` whose name is its name.
@Observable
final class Recording: Identifiable {
    /// The file's current path.
    private(set) var url: URL
    let frameCount: AVAudioFramePosition
    let sampleRate: Double

    /// The file's data length at the moment this Recording was read.
    let openedByteCount: Int64?

    /// The source's channel count and sample bit depth, read at open.
    let channelCount: Int
    let sourceBitsPerChannel: Int

    /// Whether the file actually opened.
    let isOpenable: Bool

    /// The source format the Export inspector estimates and encodes from.
    var sourceFormat: SourceFormat {
        SourceFormat(sampleRate: sampleRate, channelCount: channelCount, bitsPerChannel: sourceBitsPerChannel)
    }

    /// The file's `dev`+`inode`, captured when it was read (while the file certainly exists) and
    /// stable across a rename or move — so the store can recognise a renamed file as the *same*
    /// Recording.
    let fileIdentity: FileIdentity?

    /// Trim, in seconds.
    var trim: Trim

    /// Gain in dB: the manual Level offset applied on top of any Loudness correction at Export and
    /// in playback.
    var gain: Double

    /// The Dropouts padded into this Recording's master, read once at open.
    let dropouts: [Dropout]

    /// Whether the Recording carries the Dropout mark — a single Dropout ≥ 250 ms or a total ≥ 250 ms.
    var isSurfacedForDropouts: Bool { DropoutSurfacing.isSurfaced(dropouts, sampleRate: sampleRate) }

    /// The Dropouts big enough to draw as hatched bands in the waveform lane.
    var laneDropouts: [Dropout] { DropoutSurfacing.laneVisible(dropouts, sampleRate: sampleRate) }

    /// The one-line editor summary of Dropouts too small to draw, or nil when there are none. Every
    /// Dropout is recorded even when it is not surfaced, and this is where the small ones are told.
    var dropoutSummary: LocalizedStringResource? {
        guard !dropouts.isEmpty, sampleRate > 0 else { return nil }
        let subThreshold = DropoutSurfacing.subThreshold(dropouts, sampleRate: sampleRate)
        let total = DropoutSurfacing.totalSeconds(dropouts, sampleRate: sampleRate)
        if isSurfacedForDropouts {
            return "^[\(dropouts.count) Dropout](inflect: true) · \(Self.paddedDurationText(total)) of silence padded in"
        }
        guard !subThreshold.isEmpty else { return nil }
        let subTotal = DropoutSurfacing.totalSeconds(subThreshold, sampleRate: sampleRate)
        return "^[\(subThreshold.count) brief Dropout](inflect: true) · \(Self.paddedDurationText(subTotal)) padded, too short to hear"
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

    /// The filename without extension — the Recording's name.
    var name: String { url.deletingPathExtension().lastPathComponent }

    /// What the Library calls this Recording in a row.
    var displayName: String {
        LibraryLocation.isGeneratedName(name) ? source : name
    }

    var duration: Double { sampleRate > 0 ? Double(frameCount) / sampleRate : 0 }

    /// The Source xattr, read once at open, or nil for a file that has none — a
    /// hand-adopted file the app never captured, which is what the filename fallback below is for.
    let storedSource: String?

    /// The Source rides in an xattr written at capture; the filename is the fallback.
    var source: String { storedSource ?? Self.parsedSource(from: name) }

    /// The Source capture's own generated filename carries, which is everything before the date
    /// pattern. A name without that pattern is the user's, and is its own Source.
    static func parsedSource(from name: String) -> String {
        guard let range = name.range(of: #" \d{4}-\d{2}-\d{2} at "#, options: .regularExpression)
        else { return name }
        return String(name[name.startIndex..<range.lowerBound])
    }

    /// When this Recording was made — its creation, not its last write.
    let recordedAt: Date?

    /// What the editor window's title bar says beneath the name.
    var windowSubtitle: String {
        let origin = displayName == source ? nil : source
        let when = recordedAt?.formatted(date: .abbreviated, time: .shortened)
        return [origin, when].compactMap { $0 }.joined(separator: " · ")
    }

    /// A Recording, already read.
    init(url: URL,
         frameCount: AVAudioFramePosition,
         sampleRate: Double,
         channelCount: Int = 2,
         sourceBitsPerChannel: Int = 32,
         isOpenable: Bool = true,
         openedByteCount: Int64? = nil,
         fileIdentity: FileIdentity? = nil,
         storedSource: String? = nil,
         recordedAt: Date? = nil,
         storedTrim: Trim? = nil,
         gain: Double = 0,
         dropouts: [Dropout] = []) {
        self.url = url
        self.frameCount = frameCount
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.sourceBitsPerChannel = sourceBitsPerChannel
        self.isOpenable = isOpenable
        self.openedByteCount = openedByteCount
        self.fileIdentity = fileIdentity
        self.storedSource = storedSource
        self.recordedAt = recordedAt
        self.gain = gain
        self.dropouts = dropouts
        // A missing or malformed Trim attribute reads as the full range, and the stored one has
        // already been clamped against this duration by `Trim` itself.
        let duration = sampleRate > 0 ? Double(frameCount) / sampleRate : 0
        self.trim = storedTrim ?? Trim(duration: duration)
        self.envelope = Envelope(sampleRate: sampleRate)
    }

    /// Whether this Recording's reading still describes the file at `url` — that is, whether the
    /// file still has the length it had when this object read it.
    func stillDescribes(byteCount: Int64?) -> Bool {
        byteCount == openedByteCount
    }

    /// Whether the Recording has any audio at all.
    var isEmpty: Bool { frameCount == 0 }

    /// Follow a rename/move: the same file at a new path. Only the path changes — the
    /// audio, the envelope and the in-memory Trim are the same file's, so they are kept as-is.
    func relocate(to newURL: URL) { url = newURL }

    var trimmedDuration: Double { trim.length }
    var isTrimmed: Bool { !trim.isWholeRecording }

    /// The Trim as a `(startFrame, frameCount)` pair, clamped into the file, rounded to nearest —
    /// so Export and the Loudness measurement read exactly the same frames (/-0013), and so
    /// `ExportReadiness` can ask about emptiness in the unit the encoder reads.
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

    /// Reset Trim restores the full range and persists it (no undo stack — the range *is* the
    /// state).
    func resetTrim() {
        trim.reset()
        persistTrim()
    }

    /// Writes the Trim xattr once. Called at gesture-end and on reset — never per drag frame.
    /// Best-effort: losing the write degrades gracefully, so a failure is swallowed.
    func persistTrim() {
        try? RecordingMetadata.writeTrim(trim, to: url)
    }

    /// Writes the Gain xattr once. Called at slider-drag end and on reset — never per drag frame,
    /// like `persistTrim`. Best-effort: a lost write degrades gracefully.
    func persistGain() {
        try? RecordingMetadata.writeGain(gain, to: url)
    }
}

/// A file's identity on disk — device and inode — which survives a rename or a move within the
/// volume, unlike its path.
struct FileIdentity: Hashable {
    let device: dev_t
    let inode: ino_t
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
