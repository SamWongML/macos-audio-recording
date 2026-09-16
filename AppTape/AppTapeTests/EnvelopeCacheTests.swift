import AVFoundation
import Foundation
import Testing

@testable import AppTape

/// The envelope cache: derived data, keyed on the file's identity and length, holding a picture
/// and never a fact.
struct EnvelopeCacheTests {

    private func sampleEnvelope() -> Envelope {
        var envelope = Envelope(framesPerBucket: 256, sampleRate: 44_100)
        envelope.mins = [-0.5, -0.25, 0]
        envelope.maxs = [0.5, 0.25, 0]
        envelope.rms = [0.35, 0.18, 0]
        envelope.complete = true
        return envelope
    }

    private let identity = FileIdentity(device: 1, inode: 42)

    @Test func anEnvelopeSurvivesARoundTripThroughTheCache() throws {
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = EnvelopeCache.key(identity: identity, byteCount: 1_000)

        EnvelopeCache.write(sampleEnvelope(), key: key, in: dir)
        let read = try #require(EnvelopeCache.read(key: key, in: dir))

        #expect(read == sampleEnvelope())
    }

    @Test func aCorruptCacheFileFallsBackToAScan() throws {
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = EnvelopeCache.key(identity: identity, byteCount: 1_000)
        EnvelopeCache.write(sampleEnvelope(), key: key, in: dir)
        let url = dir.appendingPathComponent(key)
        let good = try Data(contentsOf: url)

        // A wrong magic: something else wrote this file.
        var wrongMagic = good
        wrongMagic.replaceSubrange(0..<4, with: Data("XXXX".utf8))
        try wrongMagic.write(to: url)
        #expect(EnvelopeCache.read(key: key, in: dir) == nil)

        // A version this build does not know how to read.
        var wrongVersion = good
        wrongVersion.replaceSubrange(4..<8, with: withUnsafeBytes(of: UInt32(99).littleEndian) { Data($0) })
        try wrongVersion.write(to: url)
        #expect(EnvelopeCache.read(key: key, in: dir) == nil)

        // Truncated: the header promises more buckets than the file holds.
        try good.prefix(good.count - 4).write(to: url)
        #expect(EnvelopeCache.read(key: key, in: dir) == nil)

        // A file shorter than the header itself.
        try Data("AP".utf8).write(to: url)
        #expect(EnvelopeCache.read(key: key, in: dir) == nil)
    }

    @Test func aRenamedFileKeepsItsCachedEnvelope() {
        // The key is the file's identity and length, neither of which a rename touches.
        let before = EnvelopeCache.key(identity: identity, byteCount: 1_000)
        let after = EnvelopeCache.key(identity: identity, byteCount: 1_000)
        #expect(before == after)
    }

    @Test func aChangedFileMissesItsCachedEnvelope() throws {
        // A file that grew has a different length, so it keys differently and is rescanned —
        // the same invalidation rule re-adoption already turns on.
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = EnvelopeCache.key(identity: identity, byteCount: 1_000)
        EnvelopeCache.write(sampleEnvelope(), key: key, in: dir)

        let grown = EnvelopeCache.key(identity: identity, byteCount: 2_000)
        #expect(grown != key)
        #expect(EnvelopeCache.read(key: grown, in: dir) == nil)
    }

    @Test func purgingDropsOnlyTheKeysNoRecordingClaims() throws {
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let kept = EnvelopeCache.key(identity: identity, byteCount: 1_000)
        let stale = EnvelopeCache.key(identity: FileIdentity(device: 1, inode: 43), byteCount: 7)
        EnvelopeCache.write(sampleEnvelope(), key: kept, in: dir)
        EnvelopeCache.write(sampleEnvelope(), key: stale, in: dir)

        EnvelopeCache.purge(keeping: [kept], in: dir)

        #expect(EnvelopeCache.read(key: kept, in: dir) != nil)
        #expect(EnvelopeCache.read(key: stale, in: dir) == nil)
    }

    /// A cache hit opens no audio file — proved by deleting the audio before the load.
    @MainActor
    @Test func aCachedEnvelopeCostsNoAudioRead() async throws {
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cacheDir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDir) }
        let url = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("cached.caf"), seconds: 1)
        let recording = try #require(AudioFixtures.adopt(url))

        EnvelopeLoader.load(recording, cacheDirectory: cacheDir)
        try await AudioFixtures.waitUntil { recording.envelopeState == .done }
        let scanned = recording.envelope
        #expect(scanned.complete)
        #expect(!scanned.mins.isEmpty)

        // The audio is gone; only the cache can answer now.
        try FileManager.default.removeItem(at: url)
        let reopened = Recording.stub(
            "cached", seconds: 1, byteCount: recording.openedByteCount,
            identity: recording.fileIdentity, in: dir)

        EnvelopeLoader.load(reopened, cacheDirectory: cacheDir)
        try await AudioFixtures.waitUntil { reopened.envelopeState == .done }

        #expect(reopened.envelope == scanned)
    }
}
