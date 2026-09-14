import AudioToolbox
import Foundation

/// Writes the immutable Float32 CAF master with the raw `AudioFile` API, append-only, from the
/// non-realtime writer thread.
nonisolated final class CAFMasterWriter {
    let url: URL
    private var fileID: AudioFileID?
    private var asbd: AudioStreamBasicDescription
    private let channels: Int
    private(set) var framesWritten: Int64 = 0

    enum WriteError: Error { case create(OSStatus), setProperty(OSStatus), write(OSStatus) }

    /// Creates the file at `url` and stamps its metadata immediately, so even a first-frame crash
    /// leaves a labelled, backup-excluded file.
    init(url: URL, asbd: AudioStreamBasicDescription, sourceName: String) throws {
        self.url = url
        self.asbd = asbd
        self.channels = max(1, Int(asbd.mChannelsPerFrame))

        var file: AudioFileID?
        // Empty flags: do not erase.
        let create = AudioFileCreateWithURL(
            url as CFURL, kAudioFileCAFType, &self.asbd,
            AudioFileFlags(), &file)
        guard create == noErr, let file else { throw WriteError.create(create) }
        self.fileID = file

        // Defer size updates: the header is not rewritten per write, which is exactly what makes
        // the negative-mChunkSize crash story hold.
        var deferUpdates: UInt32 = 1
        let setDefer = AudioFileSetProperty(
            file, kAudioFilePropertyDeferSizeUpdates,
            UInt32(MemoryLayout<UInt32>.size), &deferUpdates)
        guard setDefer == noErr else {
            AudioFileClose(file)
            self.fileID = nil
            throw WriteError.setProperty(setDefer)
        }

        // Stamp metadata now, before any audio, so a crash leaves it in place.
        try? RecordingMetadata.writeSource(sourceName, to: url)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true  // a 1.4 GB/hour intermediate has no place in Time Machine
        var mutableURL = url
        try? mutableURL.setResourceValues(resourceValues)
    }

    /// Appends a block of interleaved samples. Realtime-unsafe by design — only the writer
    /// thread calls it.
    func write(_ samples: UnsafeBufferPointer<Float>) throws {
        guard let fileID, !samples.isEmpty else { return }
        let frameCount = samples.count / channels
        guard frameCount > 0 else { return }
        var numPackets = UInt32(frameCount)
        let byteCount = UInt32(samples.count * MemoryLayout<Float>.size)
        let status = AudioFileWritePackets(
            fileID, false, byteCount, nil,
            framesWritten, &numPackets, samples.baseAddress!)
        guard status == noErr else { throw WriteError.write(status) }
        framesWritten += Int64(numPackets)
    }

    /// Finalizes the header. The file was already valid before this — close just writes the
    /// exact sizes a deferred-update file otherwise infers from its length.
    func close() {
        if let fileID { AudioFileClose(fileID) }
        fileID = nil
    }

    deinit { close() }
}
