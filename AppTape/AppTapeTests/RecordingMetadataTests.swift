//
//  RecordingMetadataTests.swift
//  AppTapeTests
//

import Testing
import Foundation
@testable import AppTape

/// Trim and Gain ride in extended attributes on the file (ADR-0006), so they persist across an
/// editor reopen and travel with a Finder rename. Losing them degrades gracefully — a missing
/// attribute reads as the full-length Trim and zero Gain.
struct RecordingMetadataTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("apptape-meta-\(UUID().uuidString).caf")
    }

    @Test func trimRoundTripsThroughTheXattr() throws {
        let url = try AudioFixtures.writeCAF(at: tempURL(), seconds: 10)
        defer { try? FileManager.default.removeItem(at: url) }

        var trim = Trim(duration: 10)
        trim.setStart(2)
        trim.setEnd(8)
        try RecordingMetadata.writeTrim(trim, to: url)

        let read = try #require(RecordingMetadata.readTrim(from: url, duration: 10))
        #expect(abs(read.start - 2) < 1e-6)
        #expect(abs(read.end - 8) < 1e-6)
    }

    @Test func aMissingTrimReadsAsNil() throws {
        let url = try AudioFixtures.writeCAF(at: tempURL(), seconds: 3)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(RecordingMetadata.readTrim(from: url, duration: 3) == nil)
    }

    @Test func aTrimFromAShorterFileIsSanitisedNotTrusted() throws {
        // ADR-0006 permits pointing the app at a shorter file with the same name. A stored Trim
        // that no longer fits must land on a valid Trim, never trap.
        let url = try AudioFixtures.writeCAF(at: tempURL(), seconds: 30)
        defer { try? FileManager.default.removeItem(at: url) }

        var wide = Trim(duration: 30)
        wide.setStart(5); wide.setEnd(29)
        try RecordingMetadata.writeTrim(wide, to: url)

        // Reread against a much shorter duration — the file was "replaced".
        let read = try #require(RecordingMetadata.readTrim(from: url, duration: 4))
        #expect(read.start <= read.end)
        #expect(read.end <= 4 + 1e-9)
    }

    @Test func gainRoundTripsAndDefaultsToZero() throws {
        let url = try AudioFixtures.writeCAF(at: tempURL(), seconds: 2)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(RecordingMetadata.readGain(from: url) == 0)          // missing → 0
        try RecordingMetadata.writeGain(-3.5, to: url)
        #expect(abs(RecordingMetadata.readGain(from: url) - (-3.5)) < 1e-6)
    }

    @Test func recordingReadsPersistedTrimAndGainOnReopen() throws {
        let url = try AudioFixtures.writeCAF(at: tempURL(), seconds: 12)
        defer { try? FileManager.default.removeItem(at: url) }

        // First open: set a Trim and a Gain, persist them the way the editor does.
        let first = try #require(Recording(url: url))
        first.trim.setStart(1)
        first.trim.setEnd(9)
        first.persistTrim()
        first.gain = 4.5
        first.persistGain()

        // Reopen: a fresh Recording over the same file sees them.
        let reopened = try #require(Recording(url: url))
        #expect(abs(reopened.trim.start - 1) < 1e-6)
        #expect(abs(reopened.trim.end - 9) < 1e-6)
        #expect(abs(reopened.gain - 4.5) < 1e-6)
        #expect(reopened.isTrimmed)
    }

    @Test func seamsRoundTripThroughTheXattr() throws {
        let url = try AudioFixtures.writeCAF(at: tempURL(), seconds: 5)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(RecordingMetadata.readSeams(from: url).isEmpty)   // missing → clean

        let seams = [Seam(start: 1000, frames: 512, cause: .overrun),
                     Seam(start: 96_000, frames: 48_000, cause: .rebuild)]
        try RecordingMetadata.writeSeams(seams, to: url)
        #expect(RecordingMetadata.readSeams(from: url) == seams)
    }

    @Test func aMalformedSeamsValueReadsAsClean() throws {
        let url = try AudioFixtures.writeCAF(at: tempURL(), seconds: 2)
        defer { try? FileManager.default.removeItem(at: url) }

        // Write junk directly under the Seams key — an unreadable value reads as a clean Recording,
        // the safe direction (ADR-0010), never a trap.
        let junk = "not json at all"
        try junk.withCString { _ in
            _ = url.withUnsafeFileSystemRepresentation { path in
                junk.utf8CString.withUnsafeBytes { bytes in
                    setxattr(path, RecordingMetadata.seamsKey, bytes.baseAddress, junk.utf8.count, 0, 0)
                }
            }
        }
        #expect(RecordingMetadata.readSeams(from: url).isEmpty)
    }

    @Test func aSeamWithABadCauseIsDroppedNotFatal() throws {
        let url = try AudioFixtures.writeCAF(at: tempURL(), seconds: 2)
        defer { try? FileManager.default.removeItem(at: url) }

        // A future/unknown cause value drops just that entry, keeping the valid ones.
        let json = #"[{"start":0,"frames":512,"cause":"overrun"},{"start":9,"frames":9,"cause":"nonsense"}]"#
        _ = url.withUnsafeFileSystemRepresentation { path in
            json.utf8CString.withUnsafeBytes { bytes in
                setxattr(path, RecordingMetadata.seamsKey, bytes.baseAddress, json.utf8.count, 0, 0)
            }
        }
        #expect(RecordingMetadata.readSeams(from: url) == [Seam(start: 0, frames: 512, cause: .overrun)])
    }

    @Test func metadataTravelsWithARename() throws {
        let url = try AudioFixtures.writeCAF(at: tempURL(), seconds: 6, source: "Google Chrome")
        defer { try? FileManager.default.removeItem(at: url) }

        let original = try #require(Recording(url: url))
        original.trim.setStart(1.5)
        original.persistTrim()

        // Rename in place (what Finder does): the xattr identity travels with the file.
        let renamed = url.deletingLastPathComponent().appendingPathComponent("Kettle noises.caf")
        try? FileManager.default.removeItem(at: renamed)
        try FileManager.default.moveItem(at: url, to: renamed)
        defer { try? FileManager.default.removeItem(at: renamed) }

        let after = try #require(Recording(url: renamed))
        #expect(abs(after.trim.start - 1.5) < 1e-6)   // Trim survived
        #expect(after.source == "Google Chrome")       // Source xattr survived, not parsed from name
        #expect(after.name == "Kettle noises")         // the filename is the name (ADR-0006)
    }
}
