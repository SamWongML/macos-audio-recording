import AppKit
import OSLog

/// Returns to accessory mode only after the editor closes and the menu bar belongs to another app.
@MainActor
final class ActivationPolicyController {
    enum MenuBarOwner {
        case thisApp, anotherApp, unknown
    }

    struct Environment {
        var policy: () -> NSApplication.ActivationPolicy
        var isActive: () -> Bool
        var menuBarOwner: () -> MenuBarOwner
        var setPolicy: (NSApplication.ActivationPolicy) -> Bool
        var hide: () -> Void
        var enqueue: (@escaping @MainActor @Sendable () -> Void) -> Void

        static var live: Self {
            Self(
                policy: { NSApp.activationPolicy() },
                isActive: { NSApp.isActive },
                menuBarOwner: {
                    guard let owner = NSWorkspace.shared.menuBarOwningApplication else { return .unknown }
                    return owner.processIdentifier == ProcessInfo.processInfo.processIdentifier
                        ? .thisApp : .anotherApp
                },
                setPolicy: { NSApp.setActivationPolicy($0) },
                hide: { NSApp.hide(nil) },
                enqueue: { DispatchQueue.main.async(execute: $0) }
            )
        }
    }

    static let shared = ActivationPolicyController(environment: .live)
    private static let logger = Logger(subsystem: "com.samwongml.AppTape", category: "ActivationPolicy")

    private let environment: Environment
    private var editors: Set<ObjectIdentifier> = []
    private var returnToAccessoryPending = false
    private var hideRequested = false
    private var reconciliationEnqueued = false
    private var isPanelVisible = false

    init(environment: Environment) {
        self.environment = environment
    }

    func editorWillOpen() {
        returnToAccessoryPending = false
        hideRequested = false
    }

    func editorDidOpen(_ editor: ObjectIdentifier) {
        editors.insert(editor)
        editorWillOpen()
        apply(.regular)
    }

    func editorDidClose(_ editor: ObjectIdentifier) {
        guard editors.remove(editor) != nil, editors.isEmpty else { return }
        returnToAccessoryPending = true
        scheduleReconciliation()
    }

    func applicationStateDidChange() {
        guard returnToAccessoryPending else { return }
        scheduleReconciliation()
    }

    func panelVisibilityDidChange(isVisible: Bool) {
        isPanelVisible = isVisible
        applicationStateDidChange()
    }

    private func scheduleReconciliation() {
        guard !reconciliationEnqueued else { return }
        reconciliationEnqueued = true
        environment.enqueue { [weak self] in
            guard let self else { return }
            self.reconciliationEnqueued = false
            self.reconcile()
        }
    }

    private func reconcile() {
        guard returnToAccessoryPending, editors.isEmpty, !isPanelVisible else { return }
        if environment.policy() == .accessory {
            returnToAccessoryPending = false
            return
        }

        // Being inactive does not imply that another application already owns the menu bar.
        if environment.isActive() || environment.menuBarOwner() == .thisApp {
            guard !hideRequested else { return }
            hideRequested = true
            environment.hide()
            return
        }
        guard environment.menuBarOwner() == .anotherApp else { return }
        if apply(.accessory) {
            returnToAccessoryPending = false
        }
    }

    @discardableResult
    private func apply(_ policy: NSApplication.ActivationPolicy) -> Bool {
        guard environment.policy() != policy else { return true }
        guard environment.setPolicy(policy) else {
            Self.logger.error("AppKit refused activation policy \(policy.rawValue)")
            return false
        }
        return true
    }
}
