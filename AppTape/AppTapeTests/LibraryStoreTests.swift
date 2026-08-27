//
//  LibraryStoreTests.swift
//  AppTapeTests
//

import Testing
import Foundation
@testable import AppTape

/// The Library/Recording store seam (ADR-0006): listing the folder and reconciling a fresh scan
/// against what is already held. The `DispatchSource` watch and the activation re-read are thin
/// wrappers over these two pure functions, which are what the tests pin.
@MainActor
struct LibraryStoreTests {
    @Test func aSurvivingURLKeepsItsSameRecordingObject() throws {
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("A.caf"))
        let b = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("B.caf"))
        let c = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("C.caf"))

        let recA = try #require(Recording(url: a))
        let recB = try #require(Recording(url: b))
        // A live Trim on the object that survives must not be discarded by a refresh.
        recB.trim.setStart(0.5)

        let reconciled = LibraryStore.reconcile(existing: [recA, recB], urls: [b, c])

        #expect(reconciled.count == 2)
        #expect(reconciled[0] === recB)                 // same object, not a fresh read
        #expect(abs(reconciled[0].trim.start - 0.5) < 1e-9)   // its live Trim survived
        #expect(reconciled[1].url == c)                 // the new file was adopted
        #expect(!reconciled.contains { $0.url == a })   // the vanished file dropped out
    }

    @Test func aRenamedFileIsFollowedSilentlyNotDroppedAndReadded() throws {
        // ADR-0006 / issue #53: a rename is followed silently, so the open Recording is not
        // closed. The file is the same (same inode) at a new path — reconcile must relocate the
        // existing object, keeping its live Trim, rather than drop it and adopt a stranger.
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let original = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("Google Chrome.caf"), seconds: 5)

        let recording = try #require(Recording(url: original))
        recording.trim.setStart(1.0)   // an in-memory Trim (valid on a 5 s file) that must survive the rename

        // Rename in place, as Finder would — same file, new path.
        let renamed = dir.appendingPathComponent("Kettle noises.caf")
        try FileManager.default.moveItem(at: original, to: renamed)

        let reconciled = LibraryStore.reconcile(existing: [recording], urls: [renamed])
        #expect(reconciled.count == 1)
        #expect(reconciled[0] === recording)                  // same object, not a re-adopt
        #expect(reconciled[0].url == renamed)                 // relocated to the new path
        #expect(reconciled[0].name == "Kettle noises")        // the filename is the name
        #expect(abs(reconciled[0].trim.start - 1.0) < 1e-9)   // its live Trim survived
    }

    @Test func reconcileOrderFollowsTheProvidedURLs() throws {
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("A.caf"))
        let b = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("B.caf"))

        let reconciled = LibraryStore.reconcile(existing: [], urls: [b, a])
        #expect(reconciled.map(\.url) == [b, a])
    }

    @Test func anUnreadableFileIsNotListed() throws {
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let good = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("good.caf"))
        let junk = dir.appendingPathComponent("notaudio.caf")
        try Data("not audio".utf8).write(to: junk)

        let reconciled = LibraryStore.reconcile(existing: [], urls: [good, junk])
        #expect(reconciled.map(\.url) == [good])   // the junk file is simply not a Recording
    }

    @Test func audioFilesSkipsSubdirectoriesAndHiddenFilesNewestFirst() throws {
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let older = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("older.caf"))
        let newer = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("newer.caf"))
        setModified(older, Date(timeIntervalSince1970: 1_000))
        setModified(newer, Date(timeIntervalSince1970: 2_000))

        // A subdirectory and a hidden file, neither of which should appear.
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("sub", isDirectory: true), withIntermediateDirectories: true)
        try Data().write(to: dir.appendingPathComponent(".hidden.caf"))

        // Compare by name: contentsOfDirectory may normalise the path differently from a
        // hand-built URL, and the point here is the filter and the order, not URL spelling.
        let listed = LibraryStore.audioFiles(in: dir).map(\.lastPathComponent)
        #expect(listed == ["newer.caf", "older.caf"])   // newest first, folder and hidden excluded
    }

    @Test func audioFilesOfAMissingDirectoryIsEmpty() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("apptape-nope-\(UUID().uuidString)", isDirectory: true)
        #expect(LibraryStore.audioFiles(in: missing).isEmpty)
    }

    private func setModified(_ url: URL, _ date: Date) {
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
}
