//
//  RecordingReader.swift
//  AppTape
//

import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// Everything that reads a Recording's facts off the disk. `Recording` itself reads nothing, so
/// this is the only module in the app that opens a file to answer a question about one.
///
/// **A file is read once, completely.** There is deliberately no `refreshSource(of:)` or
/// `rereadDate(of:)` here: ADR-0021 rejected re-reading a Recording field by field ("re-adoption
/// with extra steps"), so the only way a Recording's facts change is a fresh `adopt`. The two
/// probes below exist to decide *whether* to re-adopt, never to patch an object in place.
@MainActor
struct RecordingReader {
    /// Every playable-looking file directly in `directory`, in whatever order the folder hands
    /// them over. Hidden files and subdirectories are skipped (ADR-0006 lists the folder, not a
    /// tree), and a hidden name is why `LibraryLocation.rename` refuses a leading dot (ADR-0020).
    ///
    /// Unsorted on purpose: the store orders Recordings by `recordedAt` once they are read, so
    /// there is one notion of a Recording's date rather than a second one derived from the url.
    func audioFiles(in directory: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])) ?? []
        return urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true }
    }

    /// The adoption gate (ADR-0015), and the one `AVAudioFile` open in the app. Nil when the file
    /// is not audio at all — a stray `.txt`, an image — so it is simply not adopted. A file that is
    /// typed as audio but will not decode (WMA, DRM, a corrupt header) still becomes a Recording,
    /// in its `isOpenable == false` state, so the user can see why it did not play and delete it.
    func adopt(_ url: URL) -> Recording? {
        guard Self.conformsToAudio(url) else { return nil }

        // Read **before** the decode, not after. A file growing under us then records a length no
        // greater than the one `frameCount` was derived from, so the next reconcile sees a mismatch
        // and re-reads. Reading it after the decode could record the *later*, larger length and
        // freeze the stale reading in place — the failure this whole mechanism exists to prevent.
        let info = Self.fileStat(url)
        // Creation over modification, and why: `Recording.recordedAt` (ADR-0031).
        let dates = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        // Only the Source xattr is read here; the filename fallback is a parse `Recording` does for
        // itself, so a rename still moves it (ADR-0006).
        let storedSource = RecordingMetadata.readSource(from: url)

        // One construction, whether or not the file decoded: an undecodable one is an empty,
        // zero-length Recording, and its metadata is not read because nothing can have written any.
        let file = try? AVAudioFile(forReading: url)
        let sampleRate = file?.fileFormat.sampleRate ?? 0
        let frameCount = file?.length ?? 0
        let duration = sampleRate > 0 ? Double(frameCount) / sampleRate : 0
        // A compressed adopted file may report 0 bits/channel; fall back to the master's 32 so the
        // ALAC estimate stays sane (which presets an adopted file even offers is ADR-0015's call).
        let bits = file.map { Int($0.fileFormat.streamDescription.pointee.mBitsPerChannel) } ?? 0

        return Recording(url: url,
                         frameCount: frameCount,
                         sampleRate: sampleRate,
                         channelCount: max(1, Int(file?.fileFormat.channelCount ?? 1)),
                         sourceBitsPerChannel: bits > 0 ? bits : 32,
                         isOpenable: file != nil,
                         openedByteCount: info.map { Int64($0.st_size) },
                         fileIdentity: info.map { FileIdentity(device: $0.st_dev, inode: $0.st_ino) },
                         storedSource: storedSource,
                         recordedAt: dates?.creationDate ?? dates?.contentModificationDate,
                         storedTrim: file == nil ? nil : RecordingMetadata.readTrim(from: url, duration: duration),
                         gain: file == nil ? 0 : RecordingMetadata.readGain(from: url),
                         seams: file == nil ? [] : RecordingMetadata.readSeams(from: url))
    }

    /// The file's data length, or nil if it cannot be stat'd. Extended attributes live outside it,
    /// so writing the Trim, Gain or Seams xattr never changes this — which is what keeps ADR-0006's
    /// same-object guarantee intact for everything the app itself writes.
    ///
    /// A bare `stat`, and **not** `URL.resourceValues(forKeys: [.fileSizeKey])`: resource values are
    /// cached on the bridged `NSURL`, so asking the same URL a second time can hand back the length
    /// from before the file grew — precisely the staleness this exists to catch.
    func byteCount(of url: URL) -> Int64? {
        Self.fileStat(url).map { Int64($0.st_size) }
    }

    /// The file's `dev`+`inode`, which survives a rename or a move within the volume unlike its
    /// path. The store uses it to follow a rename silently (ADR-0006).
    func identity(of url: URL) -> FileIdentity? {
        Self.fileStat(url).map { FileIdentity(device: $0.st_dev, inode: $0.st_ino) }
    }

    /// One `stat` of the path. Both the length and the identity come out of it — `Recording.init?`
    /// used to stat the same path twice, once for each.
    private static func fileStat(_ url: URL) -> stat? {
        var info = stat()
        guard url.withUnsafeFileSystemRepresentation({ path in
            path != nil && stat(path, &info) == 0
        }) else { return nil }
        return info
    }

    /// Whether the file's UTType conforms to `public.audio` — the cheap listing half of the
    /// adoption gate (ADR-0015). Read from the file's own content type, so it follows the real type
    /// rather than trusting the extension alone; a file with no resolvable audio type is not adopted.
    private static func conformsToAudio(_ url: URL) -> Bool {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else { return false }
        return type.conforms(to: .audio)
    }
}
