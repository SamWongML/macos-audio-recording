//
//  EditorModel.swift
//  AppTape
//

import AppKit
import Foundation
import Observation

/// The editor's coordinator: it owns the Library/Recording store, the current selection, and
/// playback, and it is the single object the editor window renders. A singleton, like the other
/// shell pieces (`RecordingController`, `EditorPresenter`), because the editor `Window` is opened
/// from AppKit and reused across open/close cycles (ADR-0017), so its state cannot live in a view
/// that SwiftUI may not recreate.
@MainActor
@Observable
final class EditorModel {
    static let shared = EditorModel()

    let store = LibraryStore()
    let player = AudioPlayer()
    /// The Loudness correction preview for the selected Recording's Trim (ADR-0013). Owned here, not
    /// in the inspector view, so a resolved measurement outlives a redraw and drives playback too.
    let correction = LoudnessCorrectionModel()

    private(set) var selection: Recording?

    /// Bumped when the **open** Recording vanishes from disk, so the view can close the window
    /// rather than hold a stale one (ADR-0006). A plain signal, not the selection itself, because
    /// "selection went nil" also happens on an empty Library and must not close anything.
    private(set) var vanishedTick = 0

    /// The Recording whose name is being edited inline in the sidebar, or nil. Editor-wide rather
    /// than row-local state for two reasons: only one row may be editing at a time, and the File
    /// menu's Rename has to be able to open the field on a row it does not own (ADR-0020).
    var renamingURL: URL?

    @ObservationIgnored private var pendingSelectionURL: URL?
    @ObservationIgnored private var didInitialSelect = false
    @ObservationIgnored private var tracking = false

    private init() {}

    /// Called every time the editor opens (from the status item's stop, ADR-0016). Starts the
    /// store, remembers the Recording just made so it is selected once it appears, and begins
    /// reconciling the selection against the folder.
    ///
    /// The re-list is unconditional, and that matters on the path this is most often called from:
    /// the editor opening on a Recording that capture has *just* finalized. `start()` re-lists only
    /// on its first call, and the folder watch fires on directory writes — neither of which the
    /// last few seconds of a growing master produce. Without a re-list here the editor would open on
    /// the length the master had when its file was created, which is zero (ADR-0021).
    func activate(selecting url: URL? = nil) {
        if let url { pendingSelectionURL = url }
        store.start()
        store.refresh()
        if !tracking { tracking = true; trackStore() }
        reconcileSelection()
    }

    func select(_ recording: Recording?) {
        // Selecting a different Recording navigates away from any running Export, which cancels it
        // unwarned (ADR-0012). Guarded on a real change so a folder refresh re-selecting the same
        // Recording does not clear a just-finished success telling.
        if selection?.url != recording?.url { ExportCoordinator.shared.cancel() }
        selection = recording
        guard let recording else { return }
        didInitialSelect = true
        player.load(recording)
        EnvelopeLoader.load(recording)
    }

    func recording(for url: URL) -> Recording? {
        store.recordings.first { $0.url == url }
    }

    /// Trash a Recording — the escape hatch for a can't-open adopted file (ADR-0015). When it is the
    /// open Recording, the selection is moved to a neighbour **before** the file leaves the folder, so
    /// the editor stays open on the next Recording rather than closing itself on the vanish (which is
    /// reserved for a file disappearing from under us, ADR-0006).
    func trash(_ recording: Recording) {
        if selection?.url == recording.url {
            select(store.recordings.first { $0.url != recording.url })
        }
        store.trash(recording)
    }

    func beginRename(_ recording: Recording) { renamingURL = recording.url }

    func endRename() { renamingURL = nil }

    /// Rename a Recording, returning what the Library made of the name so the row can tell a
    /// refusal (ADR-0020). The open Recording survives its own rename — same object, same
    /// envelope, same Trim — so nothing here has to touch the selection or the player.
    @discardableResult
    func rename(_ recording: Recording, to proposed: String) -> LibraryLocation.RenameOutcome {
        store.rename(recording, to: proposed)
    }

    /// Show the Recording's file in Finder. The Library is an ordinary folder (ADR-0006), so this
    /// is not an escape hatch — it is the second UI the app already expects the user to use.
    func reveal(_ recording: Recording) {
        NSWorkspace.shared.activateFileViewerSelecting([recording.url])
    }

    /// Keeps the selection honest as the folder changes underneath it:
    /// - a Recording just captured (a pending URL) is selected once it lists;
    /// - the **open** Recording being re-adopted rebinds the selection to the fresh object;
    /// - the **open** Recording vanishing closes the editor;
    /// - on the first open with nothing pending, the newest Recording is selected.
    private func reconcileSelection() {
        if let url = pendingSelectionURL, let recording = recording(for: url) {
            pendingSelectionURL = nil
            select(recording)
            return
        }
        if let selection {
            guard let current = recording(for: selection.url) else {
                ExportCoordinator.shared.cancel()   // the open Recording vanished — navigate away
                self.selection = nil
                player.stop()
                vanishedTick += 1
                return
            }
            // Same file, freshly read: the store re-adopted it because its length had changed
            // (ADR-0021), so the object the editor is rendering is now the stale one. Rebind, which
            // also reloads the player and rebuilds the envelope against the audio that is now there.
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
