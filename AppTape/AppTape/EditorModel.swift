import AppKit
import Foundation
import Observation

/// The editor's coordinator: it owns the Library/Recording store, the current selection, playback,
/// and the two Export objects the trailing column renders, and it is the single object the editor
/// window is handed.
@MainActor
@Observable
final class EditorModel {
    static let shared = EditorModel()

    let store: LibraryStore
    let player: AudioPlayer
    /// The Loudness correction preview for the selected Recording's Trim. Owned here, not
    /// in the inspector view, so a resolved measurement outlives a redraw and drives playback too.
    let correction: LoudnessCorrectionModel
    /// The running Export.
    let coordinator: ExportCoordinator
    /// The sticky Quality Preset and the Loudness switch. Here for the same
    /// reason `correction` is: the dock renders it, and a redraw must not be able to lose it.
    let preference: ExportPreference

    private(set) var selection: Recording?

    private(set) var selectionUnavailable = false

    /// The Recording whose name is being edited inline in the sidebar, or nil.
    var renamingURL: URL?

    @ObservationIgnored private var pendingSelectionURL: URL?
    @ObservationIgnored private var didInitialSelect = false
    @ObservationIgnored private var tracking = false

    /// The production wiring: the real Library folder behind the store, and the app-wide Export
    /// objects.
    convenience init() {
        self.init(
            store: LibraryStore(), player: AudioPlayer(), correction: LoudnessCorrectionModel(),
            coordinator: .shared, preference: .shared)
    }

    /// For a test or a preview: a store with a reader that opens no files, and Export objects nothing
    /// else is watching.
    init(
        store: LibraryStore, player: AudioPlayer, correction: LoudnessCorrectionModel,
        coordinator: ExportCoordinator, preference: ExportPreference
    ) {
        self.store = store
        self.player = player
        self.correction = correction
        self.coordinator = coordinator
        self.preference = preference
    }

    /// Called every time the editor opens (from the status item's stop).
    func activate(selecting url: URL? = nil) {
        if let url { pendingSelectionURL = url }
        store.start()
        if !tracking { tracking = true; trackStore() }
        reconcileSelection()
    }

    func select(_ recording: Recording?) {
        // Selecting a different Recording navigates away from any running Export, which cancels it
        // unwarned.
        if selection?.url != recording?.url { coordinator.cancel() }
        if recording == nil {
            if let selection, self.recording(for: selection.url) == nil {
                selectionUnavailable = true
            }
            player.stop()
        }
        selection = recording
        guard let recording else { return }
        selectionUnavailable = false
        didInitialSelect = true
        player.load(recording)
        EnvelopeLoader.load(recording)
    }

    func recording(for url: URL) -> Recording? {
        store.recordings.first { $0.url == url }
    }

    /// Trash a Recording — the escape hatch for a can't-open adopted file.
    func trash(_ recording: Recording) {
        store.trash(recording)
        reconcileSelection()
    }

    func beginRename(_ recording: Recording) { renamingURL = recording.url }

    func endRename() { renamingURL = nil }

    /// Rename a Recording, returning what the Library made of the name so the row can tell a
    /// blocker.
    @discardableResult
    func rename(_ recording: Recording, to proposed: String) -> LibraryLocation.RenameOutcome {
        store.rename(recording, to: proposed)
    }

    /// Show the Recording's file in Finder. The Library is an ordinary folder, so this
    /// is not an escape hatch — it is the second UI the app already expects the user to use.
    func reveal(_ recording: Recording) {
        NSWorkspace.shared.activateFileViewerSelecting([recording.url])
    }

    /// Keeps the selection honest as the folder changes underneath it:
    /// - a Recording just captured (a pending URL) is selected once it lists;
    /// - the open Recording being re-adopted rebinds the selection to the fresh object;
    /// - the open Recording vanishing clears selection;
    /// - on the first open with nothing pending, the newest Recording is selected.
    private func reconcileSelection() {
        if let url = pendingSelectionURL, let recording = recording(for: url) {
            pendingSelectionURL = nil
            select(recording)
            return
        }
        if let selection {
            guard let current = recording(for: selection.url) else {
                select(nil)
                return
            }
            // Same file, freshly read: the store re-adopted it because its length had changed, so
            // the object the editor is rendering is now the stale one.
            if current !== selection { select(current) }
            return
        }
        if !didInitialSelect, pendingSelectionURL == nil, let first = store.recordings.first {
            select(first)
        }
    }

    /// `@Observable` fires `withObservationTracking` exactly once, so it re-arms after every
    /// change — the pattern the menu bar already uses to bridge observation to non-view code.
    private func trackStore() {
        withObservationTracking {
            _ = store.recordings
        } onChange: { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.reconcileSelection()
                self.trackStore()
            }
        }
    }
}
