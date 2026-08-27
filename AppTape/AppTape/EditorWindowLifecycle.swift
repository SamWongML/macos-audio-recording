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
/// keys off the *existence* of the host `NSWindow` — shown means the editor is
/// open, `willClose` means it is gone — not on focus, so the policy stays
/// `.regular` while the editor is merely backgrounded.
///
/// A SwiftUI `Window` reuses the same `NSWindow` across open/close cycles:
/// closing it fires `willClose` but reopening it neither recreates the view nor
/// re-runs `viewDidMoveToWindow`. So open cannot be detected by view attachment
/// alone — the first open would flip to `.regular`, but every reopen would leave
/// the app stranded in `.accessory` with a visible-but-orphaned window. Instead
/// the observers are wired once per window and kept: `didBecomeKey` marks open
/// (openWindow makes the window key, on the first show and every reopen), guarded
/// by `isOpen` so re-focusing an already-open editor is a no-op and the policy
/// never flickers; `willClose` marks closed. Minimizing fires neither, so a
/// minimized editor correctly stays `.regular` — it still exists.
private struct EditorWindowLifecycle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { LifecycleView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class LifecycleView: NSView {
        private weak var trackedWindow: NSWindow?
        private var isOpen = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            if window !== trackedWindow {
                trackedWindow = window
                let center = NotificationCenter.default
                center.addObserver(
                    self, selector: #selector(windowDidBecomeKey),
                    name: NSWindow.didBecomeKeyNotification, object: window
                )
                center.addObserver(
                    self, selector: #selector(windowWillClose),
                    name: NSWindow.willCloseNotification, object: window
                )
            }
            trimViewMenu()
            markOpen()
        }

        /// The spec's menu set (ADR-0017) has no View menu, but AppKit auto-inserts
        /// "Enter Full Screen" into one whenever the editor is `.regular` — and it
        /// is decoupled from the window: the editor is already `.fullScreenNone`, so
        /// neither `collectionBehavior` nor a replaced `.toolbar` CommandGroup
        /// removes it. Strip the whole (single-item) View menu imperatively instead,
        /// deferred past SwiftUI's menu build and re-run whenever the editor becomes
        /// key so a menu rebuild cannot bring it back.
        private func trimViewMenu() {
            DispatchQueue.main.async {
                guard let mainMenu = NSApp.mainMenu,
                      let view = mainMenu.items.first(where: { $0.title == "View" })
                else { return }
                mainMenu.removeItem(view)
            }
        }

        private func markOpen() {
            guard !isOpen else { return }
            isOpen = true
            ActivationPolicyController.shared.editorDidOpen()
        }

        @objc private func windowDidBecomeKey() {
            trimViewMenu()
            markOpen()
        }

        @objc private func windowWillClose() {
            guard isOpen else { return }
            isOpen = false
            ActivationPolicyController.shared.editorDidClose()
        }
    }
}
