import SwiftUI

extension View {
    /// Tracks the editor's activation policy and cancels a running Export when it closes.
    func editorActivationPolicy(cancelling exportCoordinator: ExportCoordinator) -> some View {
        background(EditorWindowLifecycle(exportCoordinator: exportCoordinator))
    }
}

/// Bridges the SwiftUI editor window to the AppKit activation-policy handoff.
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
        /// Accepted from the modifier.
        var exportCoordinator: ExportCoordinator?
        private weak var trackedWindow: NSWindow?

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
            ActivationPolicyController.shared.editorDidOpen(ObjectIdentifier(window))
        }

        /// The spec's menu set has no View menu, but AppKit auto-inserts "Enter Full Screen" into
        /// one whenever the editor is `.regular` — and it is decoupled from the window: the
        /// editor is already `.fullScreenNone`, so neither `collectionBehavior` nor a replaced
        /// `.toolbar` CommandGroup removes it.
        private func trimViewMenu() {
            DispatchQueue.main.async {
                guard let mainMenu = NSApp.mainMenu,
                    let view = mainMenu.items.first(where: { $0.title == "View" })
                else { return }
                mainMenu.removeItem(view)
            }
        }

        @objc private func windowDidBecomeKey(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            trimViewMenu()
            ActivationPolicyController.shared.editorDidOpen(ObjectIdentifier(window))
        }

        @objc private func windowWillClose(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            // Closing the editor navigates away from any running Export, which cancels it unwarned.
            exportCoordinator?.cancel()
            ActivationPolicyController.shared.editorDidClose(ObjectIdentifier(window))
        }
    }
}
