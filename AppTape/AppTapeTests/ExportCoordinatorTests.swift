//
//  ExportCoordinatorTests.swift
//  AppTapeTests
//

import AVFoundation
import Testing
import Foundation
@testable import AppTape

/// The non-modal export flow's file handling (ADR-0012). The save panel and the state machine are
/// AppKit-bound, but the two properties the acceptance criteria hinge on are testable directly: the
/// atomic swap finishes to the chosen file, and a cancel/failure leaves that file **untouched**
/// because the encode only ever writes the sibling temp.
struct ExportCoordinatorTests {
    private func encode(_ source: URL, to dest: URL, frames: Int64 = 48_000,
                        preset: QualityPreset = .high) throws {
        try ExportEncoder().run(ExportRequest(source: source, destination: dest,
                                              startFrame: 0, frameCount: frames, preset: preset)) { _ in }
    }

    @Test func commitOverASiblingReplacesTheChosenFileAtomically() throws {
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("master.caf"), seconds: 2)

        // A pre-existing file at the destination the user is overwriting.
        let dest = dir.appendingPathComponent("Export.m4a")
        try Data("ORIGINAL".utf8).write(to: dest)

        // Encode to a sibling temp, then swap it in.
        let temp = dir.appendingPathComponent(".apptape-export-\(UUID().uuidString).m4a")
        try encode(source, to: temp)
        try ExportCoordinator.commit(temp: temp, to: dest)

        #expect(!FileManager.default.fileExists(atPath: temp.path))   // temp consumed by the swap
        let out = try AVAudioFile(forReading: dest)                   // dest is now a real m4a
        #expect(out.length > 0)
    }

    @Test func aNewDestinationNameIsMovedIntoPlace() throws {
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("master.caf"), seconds: 2)

        let dest = dir.appendingPathComponent("Brand New.m4a")   // does not exist yet
        let temp = dir.appendingPathComponent(".apptape-export-\(UUID().uuidString).m4a")
        try encode(source, to: temp)
        try ExportCoordinator.commit(temp: temp, to: dest)

        #expect(FileManager.default.fileExists(atPath: dest.path))
        #expect(!FileManager.default.fileExists(atPath: temp.path))
    }

    @Test func aCancelledExportLeavesTheChosenFileUntouched() throws {
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("master.caf"), seconds: 2)

        let dest = dir.appendingPathComponent("Keep Me.m4a")
        try Data("ORIGINAL".utf8).write(to: dest)

        // A cancelled encode throws before writing a usable temp; the flow then discards the temp
        // and never commits, so the destination is exactly as it was (ADR-0012).
        let temp = dir.appendingPathComponent(".apptape-export-\(UUID().uuidString).m4a")
        let encoder = ExportEncoder()
        encoder.cancel()
        #expect(throws: ExportEncoder.Failure.self) {
            try encoder.run(ExportRequest(source: source, destination: temp,
                                          startFrame: 0, frameCount: 48_000, preset: .high)) { _ in }
        }
        try? FileManager.default.removeItem(at: temp)

        #expect(try Data(contentsOf: dest) == Data("ORIGINAL".utf8))   // untouched
    }
}
