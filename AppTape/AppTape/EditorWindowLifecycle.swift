//
//  EditorWindowLifecycle.swift
//  AppTape
//

import SwiftUI

extension View {
    /// Reports the editor window's existence to the activation-policy controller
    /// so the app is `.regular` for exactly as long as the window is open
    /// (ADR-0017). Attach to the editor's content.
    func editorActivationPolicy() -> some View {
        background(EditorWindowLifecycle())
    }
}

/// Bridges the SwiftUI editor window to the AppKit activation-policy flip. It
/// keys off the *existence* of the host `NSWindow` — window set means the editor
/// is open, `willClose` means it is gone — not on focus, so the policy stays
/// `.regular` while the editor is merely backgrounded.
private struct EditorWindowLifecycle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { LifecycleView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class LifecycleView: NSView {
        private weak var observedWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window !== observedWindow else { return }
            observedWindow = window
            ActivationPolicyController.shared.editorDidOpen()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowWillClose),
                name: NSWindow.willCloseNotification,
                object: window
            )
        }

        @objc private func windowWillClose() {
            NotificationCenter.default.removeObserver(
                self, name: NSWindow.willCloseNotification, object: observedWindow
            )
            observedWindow = nil
            ActivationPolicyController.shared.editorDidClose()
        }
    }
}
