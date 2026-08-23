//  PROTOTYPE — throwaway. Shared state, so switching variants keeps the same Recording,
//  the same Trim and the same playhead — the point is to compare layouts, not to reset.

import SwiftUI

enum Variant: String, CaseIterable, Identifiable {
    case m, n, o, p, q
    var id: Self { self }

    var letter: String { rawValue.uppercased() }
    var title: String {
        switch self {
        case .m: "Document"
        case .n: "Library split"
        case .o: "Inspector"
        case .p: "Tape deck"
        case .q: "Inspector + sidebar"
        }
    }
    var claim: String {
        switch self {
        case .m: "The Library is a folder, so the app does not ship a second Finder. One window per Recording."
        case .n: "One window forever. The Library is a sidebar and selecting a row swaps the Recording."
        case .o: "Export is a panel that is about to grow, so give it a permanent home now."
        case .p: "You find the edit by ear. The playhead sets Trim; the waveform only confirms it."
        case .q: "O's inspector with N's sidebar. One window, three columns, and only one pane control."
        }
    }
    /// What "play" means here — deliberately not the same across variants.
    var playScope: PlayScope {
        switch self {
        case .m, .n: .whole
        case .o, .q: .trimLooping
        case .p: .fromPlayhead
        }
    }
    var usesDocumentWindows: Bool { self == .m }
}

@MainActor @Observable
final class Editor {
    var recordings: [Recording] = []
    var selection: Recording?
    var variant: Variant = .m
    var precision: Precision = .whole
    /// Only meaningful in Q. The three answers from `docs/research/sidebar-and-inspector.md`.
    var paneControls: PaneControls = .permanentInspector

    /// Both pane visibilities live here and not in the view, so the View menu can drive them.
    /// The HIG's Sidebars page is explicit that the sidebar must not start hidden: "Avoid
    /// hiding the sidebar by default to ensure that it remains discoverable."
    var sidebarVisibility: NavigationSplitViewVisibility = .all
    var showsInspector = true

    let player = Player()
    let settings = ExportSettings()
    let timeline = TimelineState()

    func loadLibrary() {
        recordings = Library.load()
        // Cheap enough to do for everything at once: 20 minutes of Float32 master reduces
        // in ~155 ms, so there is no reason to build these lazily or cache them on disk.
        for recording in recordings { EnvelopeLoader.load(recording) }
        if selection == nil || !recordings.contains(where: { $0.url == selection?.url }) {
            select(recordings.first)
        }
    }

    func select(_ recording: Recording?) {
        selection = recording
        guard let recording else { return }
        player.load(recording)
        timeline.reset(duration: recording.duration)
        EnvelopeLoader.load(recording)
    }

    func recording(for url: URL) -> Recording? {
        recordings.first { $0.url == url }
    }
}
