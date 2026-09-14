//
//  LibraryStoreTests.swift
//  AppTapeTests
//

import Testing
import Foundation
@testable import AppTape

/// The Library/Recording store seam (ADR-0006): listing the folder and reconciling a fresh scan
/// against what is already held. The `DispatchSource` watch and the activation re-read are thin
/// wrappers over these two functions, which are what the tests pin.
///
/// Reconciling is **bookkeeping**, not audio — which Recording object survives a refresh, which is
/// re-read, which drops out — so most of it runs against `StubRecordingReader` and never touches a
/// file. What is left on disk below is the handful of cases where the file genuinely is the subject.
@MainActor
struct LibraryStoreTests {

    // MARK: - Reconciling, over a Library that is not on disk

    @Test func aSurvivingURLKeepsItsSameRecordingObject() {
        let reader = StubRecordingReader()
        let a = reader.place("A")
        let b = reader.place("B")
        // A live Trim on the object that survives must not be discarded by a refresh.
        b.trim.setStart(0.5)
        reader.remove(a)
        let c = reader.place("C")

        let reconciled = LibraryStore.reconcile(existing: [a, b], urls: reader.files, reader: reader)

        #expect(reconciled.count == 2)
        #expect(reconciled.contains { $0 === b })                 // same object, not a fresh read
        #expect(abs(b.trim.start - 0.5) < 1e-9)                   // its live Trim survived
        #expect(reconciled.contains { $0.url == c.url })          // the new file was adopted
        #expect(!reconciled.contains { $0.url == a.url })         // the vanished file dropped out
    }

    @Test func aRenamedFileIsFollowedSilentlyNotDroppedAndReadded() {
        // ADR-0006 / issue #53: a rename is followed silently, so the open Recording is not closed.
        // The file is the same (same inode) at a new path — reconcile must relocate the existing
        // object, keeping its live Trim, rather than drop it and adopt a stranger.
        let reader = StubRecordingReader()
        let recording = reader.place("Google Chrome", seconds: 5)
        recording.trim.setStart(1.0)

        let renamed = recording.url.deletingLastPathComponent().appendingPathComponent("Kettle noises.caf")
        reader.move(recording, to: renamed)

        let reconciled = LibraryStore.reconcile(existing: [recording], urls: reader.files, reader: reader)
        #expect(reconciled.count == 1)
        #expect(reconciled[0] === recording)                  // same object, not a re-adopt
        #expect(reconciled[0].url == renamed)                 // relocated to the new path
        #expect(reconciled[0].name == "Kettle noises")        // the filename is the name
        #expect(abs(reconciled[0].trim.start - 1.0) < 1e-9)   // its live Trim survived
    }

    @Test func aFileThatChangedLengthIsReAdoptedNotFollowed() {
        // ADR-0021: keeping the object preserved a *reading*, and a reading of a file still being
        // written is not worth keeping. The length is the whole condition.
        let reader = StubRecordingReader()
        let adoptedEarly = reader.place("growing", seconds: 1)
        let freshRead = Recording.stub("growing", seconds: 5)
        reader.grow(adoptedEarly, to: freshRead)

        let reconciled = LibraryStore.reconcile(existing: [adoptedEarly], urls: reader.files, reader: reader)
        #expect(reconciled.count == 1)
        #expect(reconciled[0] !== adoptedEarly)               // re-adopted, not followed
        #expect(reconciled[0].frameCount > adoptedEarly.frameCount)
    }

    @Test func aGrownFileIsReAdoptedEvenWhenItHasAlsoBeenRenamed() {
        // The rename path carries the same condition, and asks it about the *new* path — the
        // surviving object still holds the old one (ADR-0021).
        let reader = StubRecordingReader()
        let adoptedEarly = reader.place("growing", seconds: 1)
        let renamed = adoptedEarly.url.deletingLastPathComponent().appendingPathComponent("Interview.caf")
        reader.move(adoptedEarly, to: renamed)
        reader.byteCounts[renamed] = (adoptedEarly.openedByteCount ?? 0) + 1
        reader.adopted[renamed] = Recording.stub("Interview", seconds: 5)

        let reconciled = LibraryStore.reconcile(existing: [adoptedEarly], urls: reader.files, reader: reader)
        #expect(reconciled.count == 1)
        #expect(reconciled[0] !== adoptedEarly)
        #expect(reconciled[0].url == renamed)
    }

    @Test func oneRecordingCannotBeFollowedByTwoURLs() {
        // Two names for one inode — a hard link. The first url follows the held object; the second
        // cannot follow it too, so it is adopted in its own right rather than aliasing the first.
        let reader = StubRecordingReader()
        let recording = reader.place("A")
        let identity = recording.fileIdentity   // `place` always gives one
        let first = recording.url.deletingLastPathComponent().appendingPathComponent("first.caf")
        let second = recording.url.deletingLastPathComponent().appendingPathComponent("second.caf")
        reader.remove(recording)
        for url in [first, second] {
            reader.files.append(url)
            reader.identities[url] = identity
            reader.byteCounts[url] = recording.openedByteCount
            reader.adopted[url] = Recording.stub(url.deletingPathExtension().lastPathComponent,
                                                 byteCount: recording.openedByteCount)
        }

        let reconciled = LibraryStore.reconcile(existing: [recording], urls: [first, second], reader: reader)
        #expect(reconciled.count == 2)
        #expect(reconciled.filter { $0 === recording }.count == 1)   // followed exactly once
        #expect(reconciled[0] === recording)
        #expect(reconciled[1] !== recording)
    }

    @Test func aURLTheGateDeclinesYieldsNoRow() {
        // A url the reader will not adopt — not audio at all (ADR-0015) — simply does not list.
        let reader = StubRecordingReader()
        let good = reader.place("good")
        let notes = good.url.deletingLastPathComponent().appendingPathComponent("notes.txt")
        reader.files.append(notes)          // listed by the folder, but nothing reads it as a Recording

        let reconciled = LibraryStore.reconcile(existing: [], urls: reader.files, reader: reader)
        #expect(reconciled.map(\.url) == [good.url])
    }

    @Test func reconcileOrderFollowsTheProvidedURLs() {
        let reader = StubRecordingReader()
        let a = reader.place("A")
        let b = reader.place("B")

        let reconciled = LibraryStore.reconcile(existing: [], urls: [b.url, a.url], reader: reader)
        #expect(reconciled.map(\.url) == [b.url, a.url])
    }

    /// The sidebar's order and `RecordingDay`'s grouping are one notion of a Recording's date
    /// (ADR-0031) — so the store sorts the Recordings it read, not the urls it listed. The reader
    /// hands them over oldest-first here, which is what makes the sort visible.
    @Test func theStoreOrdersRecordingsNewestFirst() {
        let reader = StubRecordingReader()
        reader.place("older", recordedAt: Date(timeIntervalSince1970: 1_000))
        reader.place("newer", recordedAt: Date(timeIntervalSince1970: 2_000))

        let store = LibraryStore(directory: URL(filePath: "/Library"), reader: reader)
        store.refresh()
        #expect(store.recordings.map(\.name) == ["newer", "older"])
    }

    /// A Recording whose date could not be read sorts last rather than first, and never traps.
    @Test func aRecordingWithNoDateSortsLast() {
        let reader = StubRecordingReader()
        reader.place("undated", recordedAt: nil)
        reader.place("dated", recordedAt: Date(timeIntervalSince1970: 1_000))

        let store = LibraryStore(directory: URL(filePath: "/Library"), reader: reader)
        store.refresh()
        #expect(store.recordings.map(\.name) == ["dated", "undated"])
    }

    // MARK: - On disk, where the file is the subject

    @Test func persistingTheTrimAndGainDoesNotCostTheRecordingItsObject() throws {
        // The other side of ADR-0021: re-adoption keys on the file's **data length**, and Trim,
        // Gain and Seams all ride in extended attributes, which sit outside it. If they did not,
        // every gesture-end would silently drop the open Recording's object — and with it the very
        // live Trim and built envelope ADR-0006's same-object rule exists to protect. This one is
        // measured against the real file system on purpose: it is a claim about `st_size`.
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("settled.caf"), seconds: 5)

        let reader = RecordingReader()
        let recording = try #require(reader.adopt(url))
        recording.trim.setStart(1.0)
        recording.persistTrim()
        recording.gain = -3
        recording.persistGain()

        let reconciled = LibraryStore.reconcile(existing: [recording], urls: [url], reader: reader)
        #expect(reconciled.count == 1)
        #expect(reconciled[0] === recording)                    // same object
        #expect(abs(reconciled[0].trim.start - 1.0) < 1e-9)     // and its live Trim survived
    }

    @Test func aRealFileThatGrewInPlaceIsReAdopted() throws {
        // ADR-0021 / issue #80, against a real growing file: a master adopted while capture was
        // still writing it reads a `frameCount` that is already wrong, and the same-object rule
        // would preserve that wrong reading forever. The stub pins the bookkeeping; this pins that
        // a `stat` of a file growing under us actually reports the change.
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("growing.caf"), seconds: 1)

        let reader = RecordingReader()
        let adoptedEarly = try #require(reader.adopt(url))
        #expect(abs(adoptedEarly.duration - 1) < 0.05)

        try growInPlace(url, toSeconds: 5, in: dir)

        let reconciled = LibraryStore.reconcile(existing: [adoptedEarly], urls: [url], reader: reader)
        #expect(reconciled.count == 1)
        #expect(reconciled[0] !== adoptedEarly)
        #expect(abs(reconciled[0].duration - 5) < 0.05)          // it reads the audio now there
    }

    @Test func aNonAudioFileIsNotAdopted() throws {
        // The adoption gate lists only files whose UTType conforms to public.audio (ADR-0015). A
        // plain-text file types as text, not audio, so it is never a Recording — and only a real
        // file has a real content type to be read from.
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let notes = dir.appendingPathComponent("notes.txt")
        try Data("not audio".utf8).write(to: notes)

        #expect(RecordingReader().adopt(notes) == nil)
    }

    @Test func aTypedButUndecodableFileIsAdoptedInACantOpenState() throws {
        // A `.caf` types as public.audio, so it is adopted and listed — but garbage in it won't
        // decode, so it lists in a "can't open" state rather than vanishing (ADR-0015), and stays
        // in the folder to be trashed. Only `AVAudioFile` can refuse it, so this needs the file.
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let good = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("good.caf"))
        let broken = dir.appendingPathComponent("broken.caf")
        try Data("not really a CAF".utf8).write(to: broken)

        let reader = RecordingReader()
        let cantOpen = try #require(reader.adopt(broken))
        #expect(cantOpen.isOpenable == false)
        #expect(cantOpen.duration == 0)
        #expect(try #require(reader.adopt(good)).isOpenable)

        // Both are listed — the can't-open row is not dropped.
        let reconciled = LibraryStore.reconcile(existing: [], urls: [good, broken], reader: reader)
        #expect(reconciled.map(\.isOpenable) == [true, false])
    }

    @Test func audioFilesSkipsSubdirectoriesAndHiddenFiles() throws {
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try AudioFixtures.writeCAF(at: dir.appendingPathComponent("older.caf"))
        try AudioFixtures.writeCAF(at: dir.appendingPathComponent("newer.caf"))

        // A subdirectory and a hidden file, neither of which should appear.
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("sub", isDirectory: true), withIntermediateDirectories: true)
        try Data().write(to: dir.appendingPathComponent(".hidden.caf"))

        // Compare by name: contentsOfDirectory may normalise the path differently from a
        // hand-built URL, and the point here is the filter, not URL spelling. The listing is
        // deliberately unordered — `refresh` sorts Recordings by `recordedAt` instead.
        let listed = RecordingReader().audioFiles(in: dir).map(\.lastPathComponent).sorted()
        #expect(listed == ["newer.caf", "older.caf"])
    }

    @Test func audioFilesOfAMissingDirectoryIsEmpty() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("apptape-nope-\(UUID().uuidString)", isDirectory: true)
        #expect(RecordingReader().audioFiles(in: missing).isEmpty)
    }

    @Test func renamingFromInsideTheAppKeepsTheOpenRecording() throws {
        // The other half of ADR-0006's rename story: the app doing what Finder does. The object
        // must survive — same envelope, same live Trim — or the editor closes on its own rename.
        // A real `moveItem`, because that is the half of `rename` that is not pure.
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try AudioFixtures.writeCAF(
            at: dir.appendingPathComponent("Google Chrome 2026-08-27 at 20.05.03.caf"), seconds: 5)

        let store = LibraryStore(directory: dir, reader: RecordingReader())
        store.refresh()
        let recording = try #require(store.recordings.first)
        recording.trim.setStart(1.0)
        #expect(recording.displayName == "Test Source")   // the Source rides in the xattr

        #expect(store.rename(recording, to: "Interview") == .rename(to: "Interview.caf"))
        #expect(store.recordings.count == 1)
        #expect(store.recordings[0] === recording)             // same object, not a drop-and-re-add
        #expect(recording.name == "Interview")
        #expect(abs(recording.trim.start - 1.0) < 1e-9)        // its live Trim survived
        #expect(recording.displayName == "Interview")          // and the row now shows the new name
        #expect(recording.source == "Test Source")             // the Source xattr is never rewritten
        #expect(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("Interview.caf").path))
    }

    /// Issue #127, end to end: a rename **while that Recording's own Export is running**. The store
    /// relocates the object and the telling has to come with it, or the dock — which shows a phase
    /// only while `subjectURL` matches the Recording on screen — swaps the progress bar and Cancel
    /// button for `An Export is already running.` and the encode finishes unseen.
    ///
    /// A real `moveItem` and a real `RecordingReader`, like the rename case above: this is the wiring
    /// between the store's relocate and the coordinator's subject, and a stub on either side would
    /// leave it unpinned.
    @Test func aRenameDuringAnExportKeepsTheTellingWithItsRecording() throws {
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("Google Chrome 2026-08-27 at 20.05.03.caf"),
                                       seconds: 5)

        let store = LibraryStore(directory: dir, reader: RecordingReader())
        store.refresh()
        let recording = try #require(store.recordings.first)

        let coordinator = ExportCoordinator()
        coordinator.park(in: .running(fraction: 0.42), subject: recording)

        #expect(store.rename(recording, to: "Interview") == .rename(to: "Interview.caf"))

        #expect(store.recordings[0] === recording)                     // the rename was followed
        #expect(coordinator.subjectURL == recording.url)               // and so was the telling
        #expect(coordinator.subjectURL?.lastPathComponent == "Interview.caf")
        #expect(coordinator.phase == .running(fraction: 0.42))         // still running, still shown
    }

    @Test func aRefusedRenameLeavesTheFileExactlyWhereItWas() throws {
        let dir = try AudioFixtures.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("A.caf"))
        _ = try AudioFixtures.writeCAF(at: dir.appendingPathComponent("B.caf"))

        let store = LibraryStore(directory: dir, reader: RecordingReader())
        store.refresh()
        let a = try #require(store.recordings.first { $0.name == "A" })

        #expect(store.rename(a, to: "B") == .refused(.alreadyTaken("B.caf")))
        #expect(a.name == "A")
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("A.caf").path))
        #expect(store.recordings.count == 2)
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
}
