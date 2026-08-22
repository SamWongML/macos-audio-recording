//
//  AppTapeApp.swift
//  AppTape
//

import SwiftUI

@main
struct AppTapeApp: App {
    /// Identifies the single editor window so the menu bar can open it.
    static let editorWindowID = "editor"

    var body: some Scene {
        MenuBarExtra("AppTape", systemImage: "waveform") {
            MenuBarView()
        }

        // One editor window, not a WindowGroup: a Recording is edited in place.
        // Suppressed at launch so the app starts as a menu bar item only.
        Window("AppTape", id: Self.editorWindowID) {
            EditorView()
        }
        .defaultLaunchBehavior(.suppressed)
    }
}
