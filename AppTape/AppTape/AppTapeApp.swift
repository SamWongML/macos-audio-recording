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
                // **960 is a layout number, not a crash guard — the number is unchanged and its
                // reason is not** (issue #85, ADR-0027). It used to be a guard: below ~920 pt the
                // editor did not merely lose its sidebar, it *aborted*, because
                // `NavigationSplitView` and a permanently presented `.inspector` re-triggered each
                // other's layout until AppKit threw `NSGenericException` ("more Update Constraints
                // in Window passes than there are views in the window").
                //
                // **That loop is gone.** `.inspector` is gone with it (ADR-0024), and the editor
                // was re-measured against this code down to **400 pt wide in 10 pt steps with no
                // abort at any size** — so nothing here is protecting against a crash any more.
                //
                // What 960 now buys is the width the three columns actually need with the
                // transport's readouts reserved at their widest (ADR-0027): the sidebar at the
                // 268 pt it resolves to rather than its 232 minimum, this window's 276 pt trailing
                // column, and the transport's ~405 pt. Measured, with the longest Recording in the
                // Library selected: **940 overflows** — the sidebar's names and the trailing
                // column are both clipped by the window's edges — and **960 is clean**.
                // The **height** floor was always a layout number. The 460/480 bracket behind it
                // was measured when an over-constrained `NavigationSplitView` + permanent
                // `.inspector` answered a squeeze by *aborting*; re-measured against this code,
                // **960 × 460 no longer aborts** and the detail pane still resolves ruler, lane,
                // brief and transport at that height (issue #85). So the number is comfort rather
                // than a boundary.
                //
                // **The width floor binds and the height floor does not.** Re-measured against
                // this code (issue #97): asked for 900 the window resolves to 960, so `minWidth`
                // is the number in force; asked for 500 it resolves to **552**, because the
                // content's own minimum is higher and always wins.
                //
                // **So the declared number is 604, not 500** (#114). It used to be 500 with a
                // note calling it "honest about never being the number you hit" — which is the
                // one thing a declared minimum must not be. A constant nothing can reach is not a
                // backstop, it is a second, wrong answer to "how short can this window get",
                // sitting in the file a reader checks first.
                //
                // **604, not the 552 this ticket first wrote.** The number moved *inside* this
                // change: `safeAreaBar` reserves height for the scroll edge effect it carries, so
                // the column's own minimum grew 52 pt the moment the dock stopped being a plain
                // inset. `spacing: 0` was tried and reclaims none of it — the space is the
                // effect's, not the bar's padding. Re-measured the same two ways as the 552:
                // saved-frame launch and live interactive resize on a fresh install with no
                // defaults, both clamping to exactly **960 × 604**, with 605 holding. Writing 552
                // here would have re-created, in the same commit, the stale-declared-minimum bug
                // this line exists to kill.
                //
                // **The floor was deliberately *not* raised to 672** to stop the trailing column
                // scrolling (#114). That was the live alternative: ADR-0030 measured 645 as where
                // the column stops drawing a scroller and 670 with the longest Correction
                // caption, so a floor just above that would make the column's overflow
                // unreachable and let the Export dock stay bare by construction. It was rejected
                // because it forbids a state the app now handles — and because a treatment that
                // renders at no size any machine can produce is a treatment nobody will ever see
                // fail. That is exactly how the dock got here: ADR-0025's bare dock was correct
                // at every size anyone shot.
                .frame(minWidth: 960, minHeight: 604)
        }
        // **The trailing column sets this height, not the waveform** (ADR-0030). The lane reaches
        // its 340 pt cap at 620 pt of window, so height above that is air below the brief; the
        // Export column needs 645 before it stops drawing an overlay scroller, and 670 to survive
        // the longest Correction caption. The old 1120 × 640 was the one size in the band that was
        // wrong twice — past the cap and still scrolling, on all 39 Recordings in the Library.
        // The extra 80 pt of width is not slack: the lane draws one envelope column per point.
        .defaultSize(width: 1200, height: 680)
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
