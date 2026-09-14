import SwiftUI

extension View {
    /// Reports the editor window's existence to the activation-policy controller
    /// so the app is `.regular` for exactly as long as the window is open
    ///, and cancels a running Export when it closes.
    /// Attach to the editor's content.
    func editorActivationPolicy(cancelling exportCoordinator: ExportCoordinator) -> some View {
        background(EditorWindowLifecycle(exportCoordinator: exportCoordinator))
    }
}

/// Bridges the SwiftUI editor window to the AppKit activation-policy flip. It
/// keys off the *existence* of the host `NSWindow` — shown means the editor is
/// open, `willClose` means it is gone — not on focus, so the policy stays
/// `.regular` while the editor is merely backgrounded.
private struct EditorWindowLifecycle: NSViewRepresentable {
    var exportCoordinator: ExportCoordinator

    func makeNSView(context: Context) -> NSView {
        let view = LifecycleView()
        view.exportCoordinator = exportCoordinator
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? LifecycleView)?.exportCoordinator = exportCoordinator
    }

    final class LifecycleView: NSView {
        /// Accepted from the modifier. `ActivationPolicyController` below stays a `.shared` read on
        /// purpose: it is the app's own activation state, nothing renders it, and there is no second
        /// one for a preview or a test to want.
        var exportCoordinator: ExportCoordinator?
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

        /// The spec's menu set has no View menu, but AppKit auto-inserts
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
            // Closing the editor navigates away from any running Export, which cancels it
            // unwarned. The destination is untouched, so this costs only redoable work.
            exportCoordinator?.cancel()
            ActivationPolicyController.shared.editorDidClose()
        }
    }
}
