//
//  MenuBarView.swift
//  AppTape
//

import SwiftUI

/// Placeholder contents for the menu bar item. The real surface is designed in
/// "Design the menu bar surface" (issue #8).
struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Editor") {
            openWindow(id: AppTapeApp.editorWindowID)
        }

        Divider()

        Button("Quit AppTape") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
