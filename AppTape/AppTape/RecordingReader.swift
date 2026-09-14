import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// Everything that reads a Recording's facts off the disk. `Recording` itself reads nothing, so
/// this is the only thing in the app that opens a file to answer a question about one.
@MainActor
protocol RecordingReading {
    func audioFiles(in directory: URL) -> [URL]
    func adopt(_ url: URL) -> Recording?
    func byteCount(of url: URL) -> Int64?
    func identity(of url: URL) -> FileIdentity?
}

/// The production reader: the real file system.
@MainActor
struct RecordingReader: RecordingReading {
    /// Every playable-looking file directly in `directory`, in whatever order the folder hands them
    /// over.
    func audioFiles(in directory: URL) -> [URL] {
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])) ?? []
        return urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true }
    }

    /// The adoption gate, and the one `AVAudioFile` open in the app.
    func adopt(_ url: URL) -> Recording? {
        guard Self.conformsToAudio(url) else { return nil }

        // Read before the decode, not after.
        let info = Self.fileStat(url)
        // Creation over modification, and why: `Recording.recordedAt`.
        let dates = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        // Only the Source xattr is read here; the filename fallback is a parse `Recording` does for
        // itself, so a rename still moves it.
        let storedSource = RecordingMetadata.readSource(from: url)

        // One construction, whether or not the file decoded: an undecodable one is an empty,
        // zero-length Recording, and its metadata is not read because nothing can have written any.
        let file = try? AVAudioFile(forReading: url)
        let sampleRate = file?.fileFormat.sampleRate ?? 0
        let frameCount = file?.length ?? 0
        let duration = sampleRate > 0 ? Double(frameCount) / sampleRate : 0
        // A compressed adopted file may report 0 bits/channel; fall back to the master's 32 so the
        // ALAC estimate stays sane (which presets an adopted file even offers is the call).
        let bits = file.map { Int($0.fileFormat.streamDescription.pointee.mBitsPerChannel) } ?? 0

        return Recording(
            url: url,
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
            dropouts: file == nil ? [] : RecordingMetadata.readDropouts(from: url))
    }

    /// The file's data length, or nil if it cannot be stat'd.
    func byteCount(of url: URL) -> Int64? {
        Self.fileStat(url).map { Int64($0.st_size) }
    }

    /// The file's `dev`+`inode`, which survives a rename or a move within the volume unlike its
    /// path. The store uses it to follow a rename silently.
    func identity(of url: URL) -> FileIdentity? {
        Self.fileStat(url).map { FileIdentity(device: $0.st_dev, inode: $0.st_ino) }
    }

    /// One `stat` of the path. Both the length and the identity come out of it — `Recording.init?`
    /// used to stat the same path twice, once for each.
    private static func fileStat(_ url: URL) -> stat? {
        var info = stat()
        guard
            url.withUnsafeFileSystemRepresentation({ path in
                path != nil && stat(path, &info) == 0
            })
        else { return nil }
        return info
    }

    /// Whether the file's UTType conforms to `public.audio` — the cheap listing half of the
    /// adoption gate.
    private static func conformsToAudio(_ url: URL) -> Bool {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else { return false }
        return type.conforms(to: .audio)
    }
}
