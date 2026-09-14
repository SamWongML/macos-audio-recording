import SwiftUI

@main
struct AppTapeApp: App {
    /// Owns the hand-rolled `NSStatusItem` transport and the activation-policy
    /// flip — the pieces SwiftUI cannot express.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Identifies the single editor window so the menu bar can open it.
    static let editorWindowID = "editor"

    private let model = EditorModel.shared
    private let capture = RecordingController.shared.run

    var body: some Scene {
        // One editor window, not a WindowGroup: a Recording is edited in place.
        Window("AppTape", id: Self.editorWindowID) {
            EditorView(model: model, capture: capture)
                // A floor under the three columns.
                .frame(minWidth: 960, minHeight: 604)
        }
        // The trailing column sets this height, not the waveform.
        .defaultSize(width: 1200, height: 680)
        .defaultLaunchBehavior(.suppressed)
        .commands {
            // Trim the standard menu set to what applies: keep the app's About/Quit, the window's
            // Close ⌘W, the standard Edit items,
            CommandGroup(replacing: .newItem) {}
            // Emptying the whole `.saveItem` group also removes the default "Close", collapsing the
            // File menu entirely, so it is put back
            CommandGroup(replacing: .saveItem) {
                LibraryRowCommands(model: model)
                Divider()
                Button("Close") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("w", modifiers: .command)
            }
            CommandGroup(replacing: .printItem) {}
            // No View menu: the spec's set is About/Quit, Close ⌘W, Edit, Window, Help.
            CommandGroup(replacing: .toolbar) {}
        }
    }
}

/// The File-menu half of the Library's row actions.
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
