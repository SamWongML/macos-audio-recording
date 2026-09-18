import SwiftUI

extension View {
    func editorWindow(presenter: EditorPresenter, cancelling coordinator: ExportCoordinator) -> some View {
        modifier(EditorWindowModifier(presenter: presenter, exportCoordinator: coordinator))
    }
}

private struct EditorWindowModifier: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    var presenter: EditorPresenter
    var exportCoordinator: ExportCoordinator

    func body(content: Content) -> some View {
        content
            .background(EditorWindowLifecycle(presenter: presenter, exportCoordinator: exportCoordinator))
            .onAppear { presenter.bind { openWindow(id: AppTapeApp.editorWindowID) } }
    }
}

private struct EditorWindowLifecycle: NSViewRepresentable {
    var presenter: EditorPresenter
    var exportCoordinator: ExportCoordinator

    func makeNSView(context: Context) -> LifecycleView {
        LifecycleView(presenter: presenter, exportCoordinator: exportCoordinator)
    }

    func updateNSView(_ nsView: LifecycleView, context: Context) {}

    final class LifecycleView: NSView {
        let presenter: EditorPresenter
        let exportCoordinator: ExportCoordinator
        private weak var trackedWindow: NSWindow?

        init(presenter: EditorPresenter, exportCoordinator: ExportCoordinator) {
            self.presenter = presenter
            self.exportCoordinator = exportCoordinator
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window !== trackedWindow else { return }
            NotificationCenter.default.removeObserver(self)
            trackedWindow = window
            let center = NotificationCenter.default
            center.addObserver(
                self, selector: #selector(windowDidBecomeKey),
                name: NSWindow.didBecomeKeyNotification, object: window)
            center.addObserver(
                self, selector: #selector(windowWillClose),
                name: NSWindow.willCloseNotification, object: window)
            trimViewMenu()
            presenter.attach(window)
        }

        private func trimViewMenu() {
            DispatchQueue.main.async {
                guard let mainMenu = NSApp.mainMenu,
                    let view = mainMenu.items.first(where: { $0.title == "View" })
                else { return }
                mainMenu.removeItem(view)
            }
        }

        @objc private func windowDidBecomeKey(_ notification: Notification) {
            trimViewMenu()
            if let window = notification.object as? NSWindow { presenter.attach(window) }
        }

        @objc private func windowWillClose(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            exportCoordinator.cancel()
            presenter.detach(window)
        }
    }
}
