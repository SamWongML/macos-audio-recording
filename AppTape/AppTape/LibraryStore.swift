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

    @ObservationIgnored private var source: DispatchSourceFileSystemObject?
    @ObservationIgnored private var watchedFD: Int32 = -1
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var started = false

    init(directory: URL? = nil) {
        self.directory = directory ?? LibraryLocation.directory
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
        let urls = Self.audioFiles(in: directory)
        recordings = Self.reconcile(existing: recordings, urls: urls)
        for recording in recordings { EnvelopeLoader.load(recording) }
        if source == nil { beginWatching() }
    }

    // MARK: - Pure core (tested)

    /// Every playable-looking file directly in `directory`, newest first. Hidden files and
    /// subdirectories are skipped (ADR-0006 lists the folder, not a tree). Whether a file is
    /// actually a Recording is decided by `Recording.init?`, not here.
    static func audioFiles(in directory: URL) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])) ?? []
        return urls
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true }
            .sorted { modified($0) > modified($1) }
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }

    /// Reconcile a fresh set of `urls` against the `Recording` objects already held. Order follows
    /// `urls`, which the caller has already sorted newest-first, and each surviving Recording keeps
    /// its **same object** (so its envelope and any live Trim are not discarded):
    ///
    /// - an unchanged path keeps its object;
    /// - a path that changed but points at the **same file** (matched by device+inode) is a
    ///   rename or move, followed silently by relocating the existing object to the new url —
    ///   never dropping it, so a live editor on it is not closed (ADR-0006);
    /// - a genuinely new file becomes a new `Recording`;
    /// - a Recording whose file is gone simply falls out; likewise a url whose file is not
    ///   readable audio yields no Recording, so an adopted junk file is not listed.
    static func reconcile(existing: [Recording], urls: [URL]) -> [Recording] {
        let byURL = Dictionary(existing.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        var byIdentity: [FileIdentity: Recording] = [:]
        for recording in existing {
            if let identity = recording.fileIdentity { byIdentity[identity] = recording }
        }
        var claimed = Set<ObjectIdentifier>()

        return urls.compactMap { url -> Recording? in
            if let recording = byURL[url] {
                claimed.insert(ObjectIdentifier(recording))
                return recording
            }
            // Same file at a new path: follow the rename rather than drop-and-re-add.
            if let identity = FileIdentity(url: url), let recording = byIdentity[identity],
               !claimed.contains(ObjectIdentifier(recording)) {
                claimed.insert(ObjectIdentifier(recording))
                recording.relocate(to: url)
                return recording
            }
            return Recording(url: url)
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
