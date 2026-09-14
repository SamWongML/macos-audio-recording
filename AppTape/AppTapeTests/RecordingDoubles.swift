import AVFoundation
import Foundation
import Testing
@testable import AppTape

/// The `Recording.stub(…)` every suite builds its Recordings with lives in the app target now, in
/// `PreviewFixtures.swift` under `#if DEBUG`, because the previews need the same fixture and two
/// definitions of "an ordinary Recording" would drift apart.

/// A reader over an in-memory Library: the test says what the folder holds and what each file reads
/// as, and reads back how often it was asked.
@MainActor
final class StubRecordingReader: RecordingReading {
    /// The folder's contents, in listing order. `RecordingReader` returns them unordered, so a
    /// test that cares about order is testing the store's sort, not this.
    var files: [URL] = []
    /// What each file reads as. A url listed but absent here is one the gate declines.
    var adopted: [URL: Recording] = [:]
    /// What each file's length reads as *now* — the number the staleness check turns on.
    /// `place` keeps it agreeing with the Recording; `grow` is what makes them disagree.
    var byteCounts: [URL: Int64] = [:]
    var identities: [URL: FileIdentity] = [:]

    private(set) var adoptCount = 0
    private(set) var probeCount = 0

    /// Every file in the folder is a settled Recording: it lists, it adopts, and its length and
    /// identity agree with what it read. The state every case starts from.
    @discardableResult
    func place(_ name: String = "Google Chrome 2026-09-13 at 21.51.03",
               seconds: Double = 90,
               source: String? = "Google Chrome",
               recordedAt: Date? = nil,
               storedTrim: Trim? = nil,
               dropouts: [Dropout] = [],
               isOpenable: Bool = true) -> Recording {
        nextInode += 1
        let recording = Recording.stub(name, seconds: seconds, storedSource: source,
                                       recordedAt: recordedAt,
                                       identity: FileIdentity(device: 1, inode: nextInode),
                                       storedTrim: storedTrim, dropouts: dropouts, isOpenable: isOpenable)
        register(recording)
        return recording
    }

    /// Register a Recording as the settled reading of its own url, listing it if it is new.
    func register(_ recording: Recording) {
        if !files.contains(recording.url) { files.append(recording.url) }
        adopted[recording.url] = recording
        byteCounts[recording.url] = recording.openedByteCount
        if let identity = recording.fileIdentity { identities[recording.url] = identity }
    }

    /// The file grew, and a fresh read of it is `replacement` — a master mid-capture, or a large
    /// file still being copied in. The url keeps its identity: it is the same file.
    func grow(_ recording: Recording, to replacement: Recording) {
        byteCounts[recording.url] = (recording.openedByteCount ?? 0) + 1
        adopted[recording.url] = replacement
    }

    /// Move a file to a new path without changing what it is — what Finder does, and what the
    /// store must follow rather than treat as one Recording vanishing and another appearing.
    func move(_ recording: Recording, to newURL: URL) {
        files = files.map { $0 == recording.url ? newURL : $0 }
        let identity = identities.removeValue(forKey: recording.url)
        let length = byteCounts.removeValue(forKey: recording.url)
        adopted.removeValue(forKey: recording.url)
        identities[newURL] = identity
        byteCounts[newURL] = length
        // A re-adopt of the new path reads the same file, so it reads the same facts.
        adopted[newURL] = Recording.stub(newURL.deletingPathExtension().lastPathComponent,
                                         seconds: recording.duration,
                                         storedSource: recording.storedSource,
                                         recordedAt: recording.recordedAt,
                                         byteCount: recording.openedByteCount,
                                         identity: identity,
                                         in: newURL.deletingLastPathComponent())
    }

    /// The file is gone.
    func remove(_ recording: Recording) {
        files.removeAll { $0 == recording.url }
        adopted.removeValue(forKey: recording.url)
        byteCounts.removeValue(forKey: recording.url)
        identities.removeValue(forKey: recording.url)
    }

    // MARK: - RecordingReading

    func audioFiles(in directory: URL) -> [URL] { files }

    func adopt(_ url: URL) -> Recording? {
        adoptCount += 1
        return adopted[url]
    }

    func byteCount(of url: URL) -> Int64? {
        probeCount += 1
        return byteCounts[url]
    }

    func identity(of url: URL) -> FileIdentity? {
        probeCount += 1
        return identities[url]
    }

    private var nextInode: ino_t = 0
}
