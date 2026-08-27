//
//  PanelView.swift
//  AppTape
//

import SwiftUI

/// Placeholder contents for the hand-rolled panel. The real transport surface —
/// a list of applications where the row itself is the record control — is
/// designed in issue #8.
struct PanelView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var scratch = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AppTape")
                .font(.headline)
            Text("The transport surface lands here.")
                .font(.callout)
                .foregroundStyle(.secondary)

            // A live control proves the panel came up active: a text field can
            // only take keystrokes if `NSApp.activate()` made the popover key.
            TextField("Scratch", text: $scratch)
                .textFieldStyle(.roundedBorder)

            // The route out to the editor. Opening the suppressed `Window` is
            // what flips the app to `.regular` (ADR-0017). `openWindow` resolves
            // here because this is a SwiftUI view, even though the popover hosts
            // it through an `NSHostingController`.
            Button("Open Editor") {
                openWindow(id: AppTapeApp.editorWindowID)
            }

            Button("Quit AppTape") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 260)
        // An unrelated key handler, exactly the kind a future control adds. It
        // silently takes the popover's free Escape away (ADR-0011) — which is
        // why Escape is owned by the app's own monitor, and why this is here: to
        // keep that guarantee honest as the panel grows real controls.
        .onKeyPress(.space) { .ignored }
    }
}

#Preview {
    PanelView()
}
