//
//  RecordingSeamsTests.swift
//  AppTapeTests
//

import Testing
import Foundation
@testable import AppTape

/// A Recording reads its Seams from the xattr at open and surfaces them by the 250 ms single-or-total
/// rule (ADR-0010). The mark describes the master, and a hand-adopted file with no attribute is clean.
struct RecordingSeamsTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("apptape-seam-\(UUID().uuidString).caf")
    }

    @Test func aCleanRecordingIsUnmarked() throws {
        let url = try AudioFixtures.writeCAF(at: tempURL(), seconds: 3)
        defer { try? FileManager.default.removeItem(at: url) }

        let recording = try #require(Recording(url: url))
        #expect(recording.seams.isEmpty)
        #expect(recording.isSurfacedForSeams == false)
        #expect(recording.laneSeams.isEmpty)
        #expect(recording.seamSummary == nil)
    }

    @Test func aRebuildSeamSurfacesAndDrawsInTheLane() throws {
        let url = try AudioFixtures.writeCAF(at: tempURL(), seconds: 5)
        defer { try? FileManager.default.removeItem(at: url) }

        // A 1 s rebuild Seam (well over 250 ms) plus a tiny overrun that does not draw.
        try RecordingMetadata.writeSeams([
            Seam(start: 48_000, frames: 48_000, cause: .rebuild),
            Seam(start: 200_000, frames: 512, cause: .overrun),
        ], to: url)

        let recording = try #require(Recording(url: url))
        #expect(recording.seams.count == 2)
        #expect(recording.isSurfacedForSeams)
        #expect(recording.laneSeams == [Seam(start: 48_000, frames: 48_000, cause: .rebuild)])
        #expect(recording.seamSummary != nil)
    }

    @Test func onlySubThresholdSeamsAreNotSurfacedButAreSummarised() throws {
        let url = try AudioFixtures.writeCAF(at: tempURL(), seconds: 5)
        defer { try? FileManager.default.removeItem(at: url) }

        // Two 100 ms overruns total 200 ms — under 250 ms, and neither is individually over.
        try RecordingMetadata.writeSeams([
            Seam(start: 10_000, frames: 4_800, cause: .overrun),
            Seam(start: 90_000, frames: 4_800, cause: .overrun),
        ], to: url)

        let recording = try #require(Recording(url: url))
        #expect(recording.isSurfacedForSeams == false)   // no glyph
        #expect(recording.laneSeams.isEmpty)             // nothing drawn in the lane
        #expect(recording.seamSummary != nil)            // but told in the one-line summary
    }
}
