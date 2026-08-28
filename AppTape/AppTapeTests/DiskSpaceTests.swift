//
//  DiskSpaceTests.swift
//  AppTapeTests
//

import Testing
import Foundation
@testable import AppTape

/// The Export pre-flight refuses over-large exports before writing (ADR-0012). The decision is a
/// pure byte comparison with a safety margin, tested here; the `statfs` read is exercised against
/// a real directory to prove it returns a plausible figure.
struct DiskSpaceTests {
    @Test func refusesWhenTheEstimatePlusItsErrorBandExceedsFreeSpace() {
        // 900 MB estimate against 1 GB free: rounded up by the ±3.5% band it needs 931.5 MB —
        // fits. A 970 MB estimate needs ~1004 MB and is refused just before it would overflow.
        #expect(DiskSpace.hasRoom(estimatedBytes: 900_000_000, freeBytes: 1_000_000_000))
        #expect(!DiskSpace.hasRoom(estimatedBytes: 970_000_000, freeBytes: 1_000_000_000))
    }

    @Test func aSmallExportFitsWhateverSpaceComfortablyHoldsIt() {
        // No invented floor: a 1 MB export against 10 MB free is allowed — the only slack is the
        // estimate's own error band, and 1.035 MB is well under 10 MB.
        #expect(DiskSpace.hasRoom(estimatedBytes: 1_000_000, freeBytes: 10_000_000))
    }

    @Test func anUnverifiableVolumeIsNotRefused() {
        // Could-not-stat (nil) means "cannot verify", not "no space" — the encode proceeds and a
        // genuine ENOSPC surfaces later as a plain failure with the temp discarded (ADR-0012).
        #expect(DiskSpace.hasRoom(estimatedBytes: 1_000_000_000_000, freeBytes: nil))
    }

    @Test func aZeroEstimateAlwaysFits() {
        #expect(DiskSpace.hasRoom(estimatedBytes: 0, freeBytes: 0))
    }

    @Test func freeBytesReadsAPlausibleFigureForARealDirectory() throws {
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let free = DiskSpace.freeBytes(forVolumeContaining: dir)
        #expect(free != nil)
        #expect((free ?? 0) > 0)

        // A not-yet-created file inside it stats the same volume, not nil.
        let notYetCreated = dir.appendingPathComponent("export-\(UUID().uuidString).m4a")
        #expect(DiskSpace.freeBytes(forVolumeContaining: notYetCreated) != nil)
    }
}
