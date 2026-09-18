import AppKit

@MainActor
protocol EditorWindow: AnyObject {
    func reveal()
}

extension NSWindow: EditorWindow {
    func reveal() {
        if isMiniaturized { deminiaturize(nil) }
        makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class EditorPresenter {
    static let shared = EditorPresenter(
        model: .shared,
        activateApplication: {
            NSApp.unhideWithoutActivation()
            NSApp.activate()
        })

    private let model: EditorModel
    private let activateApplication: () -> Void
    private var openWindow: (() -> Void)?
    private var openingPending = false
    private weak var window: (any EditorWindow)?

    init(model: EditorModel, activateApplication: @escaping () -> Void) {
        self.model = model
        self.activateApplication = activateApplication
    }

    func bind(_ action: @escaping () -> Void) {
        openWindow = action
        if openingPending { open() }
    }

    func attach(_ window: any EditorWindow) {
        self.window = window
        model.activate()
        if openingPending { open() }
    }

    func detach(_ window: any EditorWindow) {
        if self.window === window { self.window = nil }
    }

    func open(selecting url: URL? = nil) {
        model.activate(selecting: url)
        if let window {
            openingPending = false
            activateApplication()
            window.reveal()
            return
        }
        guard let openWindow else {
            openingPending = true
            return
        }
        openingPending = false
        activateApplication()
        openWindow()
    }
}
