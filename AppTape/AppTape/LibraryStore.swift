import AppKit
import Foundation
import Observation

/// The Library/Recording store dropout: the one thing the editor renders and mutates, and the
/// one thing that touches the folder. makes the Library an ordinary visible folder with no index of
/// its own, so Finder is a legitimate second UI and this cannot assume it owns the directory.
@MainActor
@Observable
final class LibraryStore {
    /// Newest first. The only view of the folder the editor ever sees.
    private(set) var recordings: [Recording] = []

    /// The directory being listed. `~/Music/AppTape/` in the app; injectable so a
    /// test can point it at a scratch folder.
    let directory: URL

    /// The one thing that reads a file.
    @ObservationIgnored private let reader: any RecordingReading

    @ObservationIgnored private var source: DispatchSourceFileSystemObject?
    @ObservationIgnored private var watchedFD: Int32 = -1
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var started = false

    /// How long a burst of folder writes is collected before it is listed.
    @ObservationIgnored private let refreshDebounce: Duration
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?

    /// Where cached envelopes live, or nil to leave the cache alone entirely.
    @ObservationIgnored private let cacheDirectory: URL?

    /// The production wiring: the real folder and the real reader.
    convenience init() {
        self.init(
            directory: LibraryLocation.directory, reader: RecordingReader(),
            cacheDirectory: EnvelopeCache.directory)
    }

    /// For a test: a scratch folder, or a reader with no disk behind it at all.
    init(
        directory: URL, reader: any RecordingReading,
        refreshDebounce: Duration = .milliseconds(200), cacheDirectory: URL? = nil
    ) {
        self.directory = directory
        self.reader = reader
        self.refreshDebounce = refreshDebounce
        self.cacheDirectory = cacheDirectory
    }

    /// Sets the watch and the activation observer up once, and lists the folder every time: an
    /// editor opened after a capture must not still read the master at its creation length.
    func start() {
        if !started {
            started = true
            beginWatching()
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshSoon() }
            }
        }
        refresh()
    }

    /// Re-list the folder and reconcile, preserving surviving `Recording` objects.
    func refresh() {
        let urls = reader.audioFiles(in: directory)
        // Newest first, by the one notion of a Recording's date there is.
        recordings = Self.reconcile(existing: recordings, urls: urls, reader: reader)
            .sorted { ($0.recordedAt ?? .distantPast) > ($1.recordedAt ?? .distantPast) }
        purgeUnclaimedEnvelopes()
        if source == nil { beginWatching() }
    }

    /// Re-list after the debounce window. During a capture the folder watch fires on every
    /// write, and activating the app fires again on top of it.
    func refreshSoon() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.refreshDebounce)
            guard !Task.isCancelled else { return }
            self.refresh()
        }
    }

    /// The cache holds pictures of files that are still here; the rest are dropped in the
    /// background, because nothing is waiting on them.
    private func purgeUnclaimedEnvelopes() {
        guard let cacheDirectory else { return }
        let claimed = Set(recordings.compactMap(\.cacheKey))
        Task.detached(priority: .background) {
            EnvelopeCache.purge(keeping: claimed, in: cacheDirectory)
        }
    }

    /// Move a Recording's file to the Trash and re-list.
    func trash(_ recording: Recording) {
        try? FileManager.default.trashItem(at: recording.url, resultingItemURL: nil)
        refresh()
    }

    /// Rename a Recording from inside the app. already made Finder a legitimate second UI and a
    /// rename something the store follows silently; this is that same file rename, initiated here.
    @discardableResult
    func rename(_ recording: Recording, to proposed: String) -> LibraryLocation.RenameOutcome {
        let outcome = LibraryLocation.rename(
            recording.url.lastPathComponent,
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

    /// Reconcile a fresh set of `urls` against the `Recording` objects already held.
    static func reconcile(
        existing: [Recording], urls: [URL],
        reader: any RecordingReading
    ) -> [Recording] {
        let byURL = Dictionary(existing.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        var byIdentity: [FileIdentity: Recording] = [:]
        for recording in existing {
            if let identity = recording.fileIdentity { byIdentity[identity] = recording }
        }
        var claimed = Set<ObjectIdentifier>()

        return urls.compactMap { url -> Recording? in
            if let recording = byURL[url],
                recording.stillDescribes(byteCount: reader.byteCount(of: url))
            {
                claimed.insert(ObjectIdentifier(recording))
                return recording
            }
            // Same file at a new path: follow the rename rather than drop-and-re-add.
            if let identity = reader.identity(of: url), let recording = byIdentity[identity],
                !claimed.contains(ObjectIdentifier(recording)),
                recording.stillDescribes(byteCount: reader.byteCount(of: url))
            {
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
        guard fd >= 0 else { return }  // folder not there yet; a later refresh retries
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
            self.refreshSoon()
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

    isolated deinit {
        pendingRefresh?.cancel()
        source?.cancel()
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    }
}
