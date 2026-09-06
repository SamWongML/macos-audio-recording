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

    @Test func renamingFromInsideTheAppKeepsTheOpenRecording() throws {
        // The other half of ADR-0006's rename story: the app doing what Finder does. The object
        // must survive — same envelope, same live Trim — or the editor closes on its own rename.
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try AudioFixtures.writeCAF(
            at: dir.appendingPathComponent("Google Chrome 2026-08-27 at 20.05.03.caf"), seconds: 5)

        let store = LibraryStore(directory: dir)
        store.refresh()
        let recording = try #require(store.recordings.first)
        recording.trim.setStart(1.0)
        // While the filename is the one capture generated, the Library shows the Source — which
        // rides in the xattr the fixture writes, not in the filename.
        #expect(recording.displayName == "Test Source")

        let outcome = store.rename(recording, to: "Interview")

        #expect(outcome == .rename(to: "Interview.caf"))
        #expect(store.recordings.count == 1)
        #expect(store.recordings[0] === recording)             // same object, not a drop-and-re-add
        #expect(recording.name == "Interview")
        #expect(abs(recording.trim.start - 1.0) < 1e-9)        // its live Trim survived
        #expect(recording.displayName == "Interview")          // and the row now shows the new name
        #expect(recording.source == "Test Source")             // the Source xattr is never rewritten
        #expect(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("Interview.caf").path))
    }

    @Test func aRefusedRenameLeavesTheFileExactlyWhereItWas() throws {
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("A.caf"))
        _ = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("B.caf"))

        let store = LibraryStore(directory: dir)
        store.refresh()
        let a = try #require(store.recordings.first { $0.name == "A" })

        #expect(store.rename(a, to: "B") == .refused(.alreadyTaken("B.caf")))
        #expect(a.name == "A")
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("A.caf").path))
        #expect(store.recordings.count == 2)
    }

    @Test func aFileThatHasGrownSinceItWasOpenedIsReAdoptedNotFollowed() throws {
        // ADR-0021 / issue #80. A master adopted while capture was still writing it reads a
        // `frameCount` that is already wrong, and ADR-0006's same-object rule would preserve that
        // wrong reading forever — which is exactly what left a just-made Recording showing 0:00
        // with an empty lane until the app was relaunched.
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("growing.caf"), seconds: 1)

        let adoptedEarly = try #require(Recording(url: url))
        #expect(abs(adoptedEarly.duration - 1) < 0.05)

        // Grow the file **in place** — same device+inode, more audio — as capture does.
        try growInPlace(url, toSeconds: 5, in: dir)

        let reconciled = LibraryStore.reconcile(existing: [adoptedEarly], urls: [url])
        #expect(reconciled.count == 1)
        #expect(reconciled[0] !== adoptedEarly)                  // re-adopted, not followed
        #expect(abs(reconciled[0].duration - 5) < 0.05)          // and it reads the audio now there
        #expect(reconciled[0].frameCount > adoptedEarly.frameCount)
    }

    @Test func aGrownFileIsReAdoptedEvenWhenItHasAlsoBeenRenamed() throws {
        // The rename path takes the same condition. It asks the question about the *new* path,
        // because the surviving object still holds the old one (ADR-0021).
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let original = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("growing.caf"), seconds: 1)

        let adoptedEarly = try #require(Recording(url: original))
        try growInPlace(original, toSeconds: 5, in: dir)
        let renamed = dir.appendingPathComponent("Interview.caf")
        try FileManager.default.moveItem(at: original, to: renamed)

        let reconciled = LibraryStore.reconcile(existing: [adoptedEarly], urls: [renamed])
        #expect(reconciled.count == 1)
        #expect(reconciled[0] !== adoptedEarly)
        #expect(reconciled[0].url == renamed)
        #expect(abs(reconciled[0].duration - 5) < 0.05)
    }

    @Test func persistingTheTrimAndGainDoesNotCostTheRecordingItsObject() throws {
        // The other side of ADR-0021: re-adoption keys on the file's **data length**, and Trim,
        // Gain and Seams all ride in extended attributes, which sit outside it. If they did not,
        // every gesture-end would silently drop the open Recording's object — and with it the very
        // live Trim and built envelope ADR-0006's same-object rule exists to protect.
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("settled.caf"), seconds: 5)

        let recording = try #require(Recording(url: url))
        recording.trim.setStart(1.0)
        recording.persistTrim()
        recording.gain = -3
        recording.persistGain()

        let reconciled = LibraryStore.reconcile(existing: [recording], urls: [url])
        #expect(reconciled.count == 1)
        #expect(reconciled[0] === recording)                    // same object
        #expect(abs(reconciled[0].trim.start - 1.0) < 1e-9)     // and its live Trim survived
    }

    @Test func reconcileOrderFollowsTheProvidedURLs() throws {
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("A.caf"))
        let b = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("B.caf"))

        let reconciled = LibraryStore.reconcile(existing: [], urls: [b, a])
        #expect(reconciled.map(\.url) == [b, a])
    }

    @Test func aNonAudioFileIsNotAdopted() throws {
        // The adoption gate lists only files whose UTType conforms to public.audio (ADR-0015). A
        // plain-text file types as text, not audio, so it is never a Recording.
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let good = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("good.caf"))
        let notes = dir.appendingPathComponent("notes.txt")
        try Data("not audio".utf8).write(to: notes)

        #expect(Recording(url: notes) == nil)   // text is not public.audio
        let reconciled = LibraryStore.reconcile(existing: [], urls: [good, notes])
        #expect(reconciled.map(\.url) == [good])
    }

    @Test func aTypedButUndecodableFileIsAdoptedInACantOpenState() throws {
        // A `.caf` types as public.audio, so it is adopted and listed — but garbage in it won't
        // decode, so it lists in a "can't open" state rather than vanishing (ADR-0015), and stays
        // in the folder to be trashed.
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let good = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("good.caf"))
        let broken = dir.appendingPathComponent("broken.caf")
        try Data("not really a CAF".utf8).write(to: broken)

        let cantOpen = try #require(Recording(url: broken))
        #expect(cantOpen.isOpenable == false)
        #expect(cantOpen.duration == 0)

        let decodable = try #require(Recording(url: good))
        #expect(decodable.isOpenable == true)

        // Both are listed, newest-first order preserved — the can't-open row is not dropped.
        let reconciled = LibraryStore.reconcile(existing: [], urls: [good, broken])
        #expect(reconciled.map(\.url) == [good, broken])
        #expect(reconciled.map(\.isOpenable) == [true, false])
    }

    @Test func aSubMinimumFileAdoptsWithAFixedWholeTrim() throws {
        // A file shorter than the Trim minimum (0.2 s) is adopted and listed with Trim fixed to the
        // whole file — neither handle moves — and Exports whole (ADR-0015, issue #7).
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let short = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("blip.caf"), seconds: 0.1)

        let recording = try #require(Recording(url: short))
        #expect(recording.isOpenable)
        #expect(recording.trim.isFixed)                 // shorter than the minimum: the Trim cannot move
        #expect(!recording.isTrimmed)                   // the whole file is the Trim
        let (start, count) = recording.trimmedFrameRange
        #expect(start == 0)
        #expect(count == recording.frameCount)          // Exports whole
        #expect(count > 0)
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

    /// Replace a file's contents with a longer Recording **without replacing the file**: same
    /// device+inode, greater length — which is what a growing master looks like to the store, and
    /// what a fresh `writeCAF` at the same path would not reproduce (that makes a new inode).
    private func growInPlace(_ url: URL, toSeconds seconds: Double, in dir: URL) throws {
        let scratch = dir.appendingPathComponent("grow-\(UUID().uuidString).caf")
        try AudioFixtures.writeCAF(at: scratch, seconds: seconds)
        let longer = try Data(contentsOf: scratch)
        try FileManager.default.removeItem(at: scratch)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: longer)
        try handle.close()
    }

    private func setModified(_ url: URL, _ date: Date) {
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
}
