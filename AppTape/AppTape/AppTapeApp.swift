import SwiftUI

@main
struct AppTapeApp: App {
    /// Owns the hand-rolled `NSStatusItem` transport and the activation-policy
    /// flip — the pieces SwiftUI cannot express.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Identifies the single editor window so the menu bar can open it.
    static let editorWindowID = "editor"

    /// **The two app singletons the SwiftUI side names, named once**. Everything below is
    /// handed them; nothing under here reaches for `.shared` again. `AppDelegate` is the other place,
    /// for the two surfaces AppKit owns — the status item and the panel.
    private let model = EditorModel.shared
    private let capture = RecordingController.shared.run

    var body: some Scene {
        // One editor window, not a WindowGroup: a Recording is edited in place.
        // Suppressed at launch so the app starts as a menu bar item only, and
        Window("AppTape", id: Self.editorWindowID) {
            EditorView(model: model, capture: capture)
                // A floor under the three columns. Without one the window clamped to 418 × 400 —
                // below the sidebar's own 232 pt minimum plus the inspector's 248 — and SwiftUI
                .frame(minWidth: 960, minHeight: 604)
        }
        // **The trailing column sets this height, not the waveform**. The lane reaches
        // its 340 pt cap at 620 pt of window, so height above that is air below the brief; the
        .defaultSize(width: 1200, height: 680)
        .defaultLaunchBehavior(.suppressed)
        .commands {
            // Trim the standard menu set to what applies: keep the
            // app's About/Quit, the window's Close ⌘W, the standard Edit items,
            CommandGroup(replacing: .newItem) { }
            // Emptying the whole `.saveItem` group also removes the default
            // "Close", collapsing the File menu entirely, so it is put back
            CommandGroup(replacing: .saveItem) {
                LibraryRowCommands(model: model)
                Divider()
                Button("Close") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("w", modifiers: .command)
            }
            CommandGroup(replacing: .printItem) { }
            // No View menu: the spec's set is About/Quit, Close ⌘W, Edit, Window,
            // Help. The item that actually creates the View menu is AppKit's
            CommandGroup(replacing: .toolbar) { }
        }
    }
}

/// The File-menu half of the Library's row actions. The context menu is where they are
/// found; these are how they are reached from the keyboard. Finder's own set is the model: Rename
/// carries no key equivalent, because Return does it in the list; Move to Trash is ⌘⌫; and ⇧⌘R is
/// the "Reveal in Finder" that Music, Photos and the rest already taught.
private struct LibraryRowCommands: View {
    /// Non-nil only while the Library sidebar has focus — the gate on the destructive item.
    @FocusedValue(\.librarySidebarRecording) private var focusedRecording: URL?

    /// Handed down from the scene, like the editor's own views.
    var model: EditorModel

    var body: some View {
        Button("Rename") {
            if let recording = model.selection { model.beginRename(recording) }
        }
        .disabled(model.selection == nil || model.renamingURL != nil)

        Button("Reveal in Finder") {
            if let recording = model.selection { model.reveal(recording) }
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .disabled(model.selection == nil)

        // Gated on sidebar focus, unlike the two above: ⌘⌫ out of a search field the user is
        // typing into would move a file to the Trash they never pointed at.
        Button("Move to Trash", role: .destructive) {
            if let recording = model.selection { model.trash(recording) }
        }
        .keyboardShortcut(.delete, modifiers: .command)
        .disabled(focusedRecording == nil)
    }
}
