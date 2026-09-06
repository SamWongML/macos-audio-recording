//
//  AppTapeApp.swift
//  AppTape
//

import SwiftUI

@main
struct AppTapeApp: App {
    /// Owns the hand-rolled `NSStatusItem` transport and the activation-policy
    /// flip — the pieces SwiftUI cannot express (ADR-0004, ADR-0017).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Identifies the single editor window so the menu bar can open it.
    static let editorWindowID = "editor"

    var body: some Scene {
        // One editor window, not a WindowGroup: a Recording is edited in place.
        // Suppressed at launch so the app starts as a menu bar item only, and
        // its existence — via `.editorActivationPolicy()` — is what flips the
        // app to `.regular` (ADR-0017).
        Window("AppTape", id: Self.editorWindowID) {
            EditorView()
                // A floor under the three columns. Without one the window clamped to 418 × 400 —
                // below the sidebar's own 232 pt minimum plus the inspector's 248 — and SwiftUI
                // resolved the shortfall by **collapsing the Library entirely**, with no indication
                // and no way back except resizing. The detail pane was squeezed to ~180 pt, where
                // the transport's clock, `Trim …` and `Reset` silently disappeared rather than
                // truncating (issue #73, finding 26).
                //
                // 960 is wider than that reasoning alone wants — 232 + 280 + 276 would do — and
                // the extra is a **guard, not a layout choice**. Below ~920 pt the editor did not
                // merely lose its sidebar, it *aborted*: `NavigationSplitView` and a permanently
                // presented `.inspector` re-triggered each other's layout until AppKit threw
                // `NSGenericException` ("more Update Constraints in Window passes than there are
                // views in the window"). Measured on `main` too, so it was never new here.
                //
                // **`.inspector` is gone** — the trailing pane is an ordinary column now
                // (ADR-0024) — and issue #85 already measured 800 pt as fine without the
                // modifier. So this guard has probably outlived its cause. It is still 960
                // because that measurement was taken against older code and has not been
                // re-taken against this one, and a crash guard is not lowered on inference.
                // Issue #85 owns the re-measurement and the number.
                // The **height** floor is a layout number, unlike the width above it: the detail
                // pane's content — ruler, a lane with a floor under it, the five-row brief and
                // the docked transport — stops fitting somewhere between 460 and 480 pt of
                // window. Measured at 960 × 460 aborting and 960 × 480 not, back when an
                // over-constrained `NavigationSplitView` + permanent `.inspector` answered a
                // squeeze by *aborting* rather than clipping (issue #85's loop). Without the
                // modifier the failure below the floor should be ordinary clipping, but the
                // fitting height itself is unchanged, so the number stands as a layout floor
                // whatever it now guards against.
                //
                // In the ordinary case the content's own minimum resolves higher, so this is the
                // backstop for the shortest pane there is, not the number you will usually see.
                // The 552 that used to be quoted here was a Recording with a Seam line and four
                // brief rows, and that shape no longer exists — the brief is always five rows
                // (ADR-0023), so the content minimum is now the same for every Recording and
                // has not been re-measured (issue #77).
                .frame(minWidth: 960, minHeight: 500)
        }
        .defaultSize(width: 1120, height: 640)   // three columns want room: sidebar + waveform + inspector
        .defaultLaunchBehavior(.suppressed)
        .commands {
            // Trim the standard menu set to what applies (ADR-0017): keep the
            // app's About/Quit, the window's Close ⌘W, the standard Edit items,
            // Window and Help; drop New/Open, Save and Print, which this app has
            // no use for. SidebarCommands/InspectorCommands are deliberately not
            // added (issue #7 found they left the app with zero windows).
            CommandGroup(replacing: .newItem) { }
            // Emptying the whole `.saveItem` group also removes the default
            // "Close", collapsing the File menu entirely, so it is put back
            // explicitly. `performClose` targets the focused editor — the only
            // window shown while the menu bar exists. File also carries the
            // Library's three row actions (ADR-0020): a context menu alone is
            // undiscoverable and unreachable from the keyboard.
            CommandGroup(replacing: .saveItem) {
                LibraryRowCommands()
                Divider()
                Button("Close") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("w", modifiers: .command)
            }
            CommandGroup(replacing: .printItem) { }
            // No View menu: the spec's set is About/Quit, Close ⌘W, Edit, Window,
            // Help. The item that actually creates the View menu is AppKit's
            // "Enter Full Screen", which this replacement cannot reach — that one
            // is stripped from the main menu imperatively (EditorWindowLifecycle's
            // trimViewMenu). Kept as defense so a later editor toolbar (issue #7)
            // cannot reintroduce a View menu through toolbar commands.
            CommandGroup(replacing: .toolbar) { }
        }
    }
}

/// The File-menu half of the Library's row actions (ADR-0020). The context menu is where they are
/// found; these are how they are reached from the keyboard. Finder's own set is the model: Rename
/// carries no key equivalent, because Return does it in the list; Move to Trash is ⌘⌫; and ⇧⌘R is
/// the "Reveal in Finder" that Music, Photos and the rest already taught.
private struct LibraryRowCommands: View {
    /// Non-nil only while the Library sidebar has focus — the gate on the destructive item.
    @FocusedValue(\.librarySidebarRecording) private var focusedRecording: URL?

    private var model: EditorModel { .shared }

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
