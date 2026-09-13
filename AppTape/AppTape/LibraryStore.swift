//
//  LibraryStore.swift
//  AppTape
//

import AppKit
import Foundation
import Observation

/// The **Library/Recording store** seam: the one thing the editor renders and mutates, and the
/// one thing that touches the folder. ADR-0006 makes the Library an ordinary visible folder with
/// no index of its own, so Finder is a legitimate second UI and this cannot assume it owns the
/// directory. It therefore watches the folder with a `DispatchSource` and re-reads on activation,
/// and reconciles the result against what it already holds:
///
/// - a **rename or move** is followed silently — the xattr identity travels with the file, and a
///   surviving path keeps its existing `Recording` object, so a live Trim and a built envelope
///   are not thrown away by a refresh;
/// - a file that has **changed length** since it was opened is re-adopted rather than followed:
///   the object's `frameCount` and everything else read at open no longer describe it (ADR-0021);
/// - a **new** file is adopted;
/// - a **vanished** file drops out, and if it was the open Recording the editor is told, so it
///   can close rather than hold a stale window.
///
/// The listing and the reconciliation are pure functions over injected inputs, so they are
/// tested without the disk or the watcher.
@MainActor
@Observable
final class LibraryStore {
    /// Newest first. The only view of the folder the editor ever sees.
    private(set) var recordings: [Recording] = []

    /// The directory being listed. `~/Music/AppTape/` in the app (ADR-0006); injectable so a
    /// test can point it at a scratch folder.
    let directory: URL

    /// The one thing that reads a file. Accepted rather than created, so the reconcile below is a
    /// pure function of what the reader says the folder holds — which is what lets the suite drive
    /// a rename, a re-adoption and a vanish with no disk at all.
    @ObservationIgnored private let reader: any RecordingReading

    @ObservationIgnored private var source: DispatchSourceFileSystemObject?
    @ObservationIgnored private var watchedFD: Int32 = -1
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var started = false

    /// The production wiring: the real folder and the real reader. Its own initializer rather than
    /// a default argument, because a default argument is evaluated in a nonisolated context and the
    /// reader is main-actor isolated — the same reason `RecordingController` has two.
    convenience init() {
        self.init(directory: LibraryLocation.directory, reader: RecordingReader())
    }

    /// For a test: a scratch folder, or a reader with no disk behind it at all.
    init(directory: URL, reader: any RecordingReading) {
        self.directory = directory
        self.reader = reader
    }

    /// Idempotent. Reads the folder once, begins watching it, and re-reads whenever the app is
    /// activated — the two triggers ADR-0006 names. Safe to call on every editor open.
    func start() {
        guard !started else { return }
        started = true
        refresh()
        beginWatching()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Re-list the folder and reconcile, preserving surviving `Recording` objects. Also (re-)opens
    /// the watch if the folder has since come into existence — it is created lazily at the first
    /// captured frame (ADR-0016), so it may not have existed when `start()` first ran.
    func refresh() {
        let urls = reader.audioFiles(in: directory)
        // Newest first, by the **one** notion of a Recording's date there is (ADR-0031). The folder
        // used to be sorted before any Recording existed, which meant re-deriving `recordedAt`'s
        // rule from the url — twice per comparison — and hoping the two spellings agreed. Sorting
        // the Recordings instead makes that agreement structural, and costs no syscall at all.
        recordings = Self.reconcile(existing: recordings, urls: urls, reader: reader)
            .sorted { ($0.recordedAt ?? .distantPast) > ($1.recordedAt ?? .distantPast) }
        for recording in recordings { EnvelopeLoader.load(recording) }
        if source == nil { beginWatching() }
    }

    /// Move a Recording's file to the Trash and re-list. The Library is an ordinary folder
    /// (ADR-0006), so this is the same `trashItem` Finder does — best-effort, and the reconcile
    /// then drops the row. The escape hatch for a can't-open adopted file, whose only action is to
    /// be deleted (ADR-0015).
    func trash(_ recording: Recording) {
        try? FileManager.default.trashItem(at: recording.url, resultingItemURL: nil)
        refresh()
    }

    /// Rename a Recording from inside the app. ADR-0006 already made Finder a legitimate second
    /// UI and a rename something the store follows silently; this is that same file rename,
    /// initiated here (ADR-0020). The rules live in `LibraryLocation.rename`, which is pure; this
    /// does only the impure half and hands the outcome back so the row can tell a refusal.
    ///
    /// The object is relocated **before** the re-list so the selection, which is keyed on the url,
    /// follows in the same turn. `reconcile` would reach the same place a refresh later by
    /// device+inode, which is what makes the open Recording survive its own rename: same object,
    /// same envelope, same live Trim, no "vanished" close.
    @discardableResult
    func rename(_ recording: Recording, to proposed: String) -> LibraryLocation.RenameOutcome {
        let outcome = LibraryLocation.rename(recording.url.lastPathComponent,
                                             to: proposed,
                                             existingFileNames: recordings.map { $0.url.lastPathComponent })
        guard case .rename(let fileName) = outcome else { return outcome }
        let destination = recording.url.deletingLastPathComponent().appendingPathComponent(fileName)
        do {
            try FileManager.default.moveItem(at: recording.url, to: destination)
        } catch {
            return .refused(.diskRefused)
        }
        recording.relocate(to: destination)
        refresh()
        return outcome
    }

    // MARK: - Pure core (tested)

    /// Reconcile a fresh set of `urls` against the `Recording` objects already held. Order follows
    /// `urls` — `refresh` sorts the result — and each surviving Recording keeps
    /// its **same object** (so its envelope and any live Trim are not discarded):
    ///
    /// - an unchanged path keeps its object;
    /// - a path that changed but points at the **same file** (matched by device+inode) is a
    ///   rename or move, followed silently by relocating the existing object to the new url —
    ///   never dropping it, so a live editor on it is not closed (ADR-0006);
    /// - a genuinely new file becomes a new `Recording`;
    /// - a Recording whose file is gone simply falls out; likewise a url whose file is not
    ///   readable audio yields no Recording, so an adopted junk file is not listed.
    ///
    /// Both of the keep-the-object cases carry the same condition: the file must still have the
    /// length the object read (`stillDescribes`). Keeping the object is how a *reading* survives a
    /// refresh, and a reading is only worth keeping while it is still true — so a master that has
    /// grown since it was listed, which is every master adopted mid-capture, is re-read instead
    /// (ADR-0021). Extended attributes sit outside the data length, so persisting a Trim, a Gain
    /// or the Seams never trips this.
    static func reconcile(existing: [Recording], urls: [URL],
                          reader: any RecordingReading) -> [Recording] {
        let byURL = Dictionary(existing.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        var byIdentity: [FileIdentity: Recording] = [:]
        for recording in existing {
            if let identity = recording.fileIdentity { byIdentity[identity] = recording }
        }
        var claimed = Set<ObjectIdentifier>()

        return urls.compactMap { url -> Recording? in
            if let recording = byURL[url],
               recording.stillDescribes(byteCount: reader.byteCount(of: url)) {
                claimed.insert(ObjectIdentifier(recording))
                return recording
            }
            // Same file at a new path: follow the rename rather than drop-and-re-add.
            if let identity = reader.identity(of: url), let recording = byIdentity[identity],
               !claimed.contains(ObjectIdentifier(recording)),
               recording.stillDescribes(byteCount: reader.byteCount(of: url)) {
                claimed.insert(ObjectIdentifier(recording))
                recording.relocate(to: url)
                return recording
            }
            return reader.adopt(url)
        }
    }

    // MARK: - Watching

    private func beginWatching() {
        guard source == nil else { return }
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }   // folder not there yet; a later refresh retries
        watchedFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename, .revoke], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            // The folder itself was deleted or moved: drop the watch and re-establish it on the
            // next refresh, when the path may exist again.
            if source.data.contains(.delete) || source.data.contains(.revoke) {
                self.stopWatching()
            }
            self.refresh()
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.watchedFD, fd >= 0 { close(fd) }
            self?.watchedFD = -1
        }
        self.source = source
        source.resume()
    }

    private func stopWatching() {
        source?.cancel()
        source = nil
    }

    deinit {
        source?.cancel()
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    }
}
