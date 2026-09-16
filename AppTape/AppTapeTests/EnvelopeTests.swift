import AVFoundation
import Foundation
import Testing

@testable import AppTape

/// The peak envelope: where its scan runs, and what a Recording's own load does to its neighbours.
struct EnvelopeTests {

    /// The envelope scan must never run on the main actor — a full-file decode there freezes the editor.
    @Test func theEnvelopeScanNeverRunsOnTheMainThread() async throws {
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Long enough to publish more than once, so the sample lands inside the read loop.
        let url = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("probe.caf"), seconds: 4)

        let touchedMainThread = await Task.detached {
            nonisolated(unsafe) var onMain = false
            await EnvelopeLoader.scan(url: url) { _ in
                if pthread_main_np() != 0 { onMain = true }
            }
            return onMain
        }.value

        #expect(!touchedMainThread)
    }

    /// A Recording's load is its own: a sidebar that shows one row must not scan the whole folder.
    @MainActor
    @Test func loadingOneRecordingLeavesTheOthersIdle() throws {
        let cache = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }
        let wanted = Recording.stub("wanted")
        let others = [Recording.stub("a"), Recording.stub("b")]

        EnvelopeLoader.load(wanted, cacheDirectory: cache)

        #expect(wanted.envelopeState != .idle)
        #expect(others.allSatisfy { $0.envelopeState == .idle })
    }

    /// Scans are admitted a few at a time. Every Recording starting at once competes for the same
    /// cores and the same disk, which is slower than doing them in order.
    @MainActor
    @Test func atMostThreeRecordingsScanAtOnce() throws {
        let cache = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }
        let recordings = (0..<5).map { Recording.stub("r\($0)") }

        for recording in recordings { EnvelopeLoader.load(recording, cacheDirectory: cache) }

        let building = recordings.filter { $0.envelopeState == .building }.count
        let queued = recordings.filter { $0.envelopeState == .queued }.count
        #expect(building <= 3)  // the cap holds
        #expect(queued >= 2)  // and the ones over it waited rather than starting
        #expect(building + queued == 5)  // none was dropped
    }
}
