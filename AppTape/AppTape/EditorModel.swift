//
//  EditorModel.swift
//  AppTape
//

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

    private(set) var selection: Recording?

    /// Bumped when the **open** Recording vanishes from disk, so the view can close the window
    /// rather than hold a stale one (ADR-0006). A plain signal, not the selection itself, because
    /// "selection went nil" also happens on an empty Library and must not close anything.
    private(set) var vanishedTick = 0

    @ObservationIgnored private var pendingSelectionURL: URL?
    @ObservationIgnored private var didInitialSelect = false
    @ObservationIgnored private var tracking = false

    private init() {}

    /// Called every time the editor opens (from the status item's stop, ADR-0016). Starts the
    /// store, remembers the Recording just made so it is selected once it appears, and begins
    /// reconciling the selection against the folder.
    func activate(selecting url: URL? = nil) {
        if let url { pendingSelectionURL = url }
        store.start()
        if !tracking { tracking = true; trackStore() }
        reconcileSelection()
    }

    func select(_ recording: Recording?) {
        selection = recording
        guard let recording else { return }
        didInitialSelect = true
        player.load(recording)
        EnvelopeLoader.load(recording)
    }

    func recording(for url: URL) -> Recording? {
        store.recordings.first { $0.url == url }
    }

    /// Keeps the selection honest as the folder changes underneath it:
    /// - a Recording just captured (a pending URL) is selected once it lists;
    /// - the **open** Recording vanishing closes the editor;
    /// - on the first open with nothing pending, the newest Recording is selected.
    private func reconcileSelection() {
        if let url = pendingSelectionURL, let recording = recording(for: url) {
            pendingSelectionURL = nil
            select(recording)
            return
        }
        if let selection {
            if !store.recordings.contains(where: { $0.url == selection.url }) {
                self.selection = nil
                player.stop()
                vanishedTick += 1
            }
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
