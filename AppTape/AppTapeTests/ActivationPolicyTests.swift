import AppKit
import Testing

@testable import AppTape

@MainActor
struct ActivationPolicyTests {
    @Test func openingPromotesAndFocusChangesKeepTheEditorRegular() {
        let rig = Rig()
        rig.open()
        rig.system.isActive = false
        rig.controller.applicationStateDidChange()
        rig.system.drain()

        #expect(rig.system.actions == [.policy(.regular)])
    }

    @Test func closeFinishesBeforeHidingAndDemotionWaitsForTheMenuBar() {
        let rig = Rig()
        rig.open()
        rig.close()
        #expect(rig.system.actions == [.policy(.regular)])

        rig.system.drain()
        #expect(rig.system.actions == [.policy(.regular), .hide])

        rig.system.isActive = false
        rig.controller.applicationStateDidChange()
        rig.system.drain()
        #expect(rig.system.policy == .regular)

        rig.system.owner = .anotherApp
        rig.controller.applicationStateDidChange()
        rig.system.drain()
        #expect(rig.system.actions == [.policy(.regular), .hide, .policy(.accessory)])
    }

    @Test func menuOwnershipChangingFirstStillWaitsForDeactivation() {
        let rig = Rig()
        rig.open()
        rig.close()
        rig.system.drain()

        rig.system.owner = .anotherApp
        rig.controller.applicationStateDidChange()
        rig.system.drain()
        #expect(rig.system.policy == .regular)

        rig.system.isActive = false
        rig.controller.applicationStateDidChange()
        rig.system.drain()
        #expect(rig.system.policy == .accessory)
    }

    @Test func closingAnInactiveEditorDoesNotHideOrActivateAnotherApp() {
        let rig = Rig()
        rig.open()
        rig.system.isActive = false
        rig.system.owner = .anotherApp
        rig.close()
        rig.system.drain()

        #expect(rig.system.actions == [.policy(.regular), .policy(.accessory)])
    }

    @Test func anUnknownMenuOwnerIsNotEvidenceOfAHandoff() {
        let rig = Rig()
        rig.open()
        rig.close()
        rig.system.drain()
        rig.system.isActive = false
        rig.system.owner = .unknown
        rig.controller.applicationStateDidChange()
        rig.system.drain()
        #expect(rig.system.policy == .regular)

        rig.system.owner = .anotherApp
        rig.controller.applicationStateDidChange()
        rig.system.drain()
        #expect(rig.system.policy == .accessory)
    }

    @Test func reopeningBeforeTheQueuedCloseDoesNotHideTheEditor() {
        let rig = Rig()
        rig.open()
        rig.close()
        rig.open()
        rig.system.drain()

        #expect(rig.system.actions == [.policy(.regular)])
    }

    @Test func reopeningDuringHandoffCancelsDemotion() {
        let rig = Rig()
        rig.open()
        rig.close()
        rig.system.drain()
        rig.system.isActive = false
        rig.system.owner = .anotherApp
        rig.controller.applicationStateDidChange()
        rig.open()
        rig.system.drain()

        #expect(rig.system.actions == [.policy(.regular), .hide])
    }

    @Test func requestingAnEditorCancelsTheCloseBeforeSwiftUICreatesItsWindow() {
        let rig = Rig()
        rig.open()
        rig.close()
        rig.controller.editorWillOpen()
        rig.system.drain()

        #expect(rig.system.actions == [.policy(.regular)])
        rig.open()
        rig.close()
        rig.system.drain()
        #expect(rig.system.actions == [.policy(.regular), .hide])
    }

    @Test func anOpenStatusPanelDelaysTheHandoffUntilItCloses() {
        let rig = Rig()
        rig.open()
        rig.close()
        rig.controller.panelVisibilityDidChange(isVisible: true)
        rig.system.drain()
        #expect(rig.system.actions == [.policy(.regular)])

        rig.controller.panelVisibilityDidChange(isVisible: false)
        rig.system.drain()
        #expect(rig.system.actions == [.policy(.regular), .hide])
        rig.system.isActive = false
        rig.system.owner = .anotherApp
        rig.controller.applicationStateDidChange()
        rig.system.drain()
        #expect(rig.system.policy == .accessory)
    }

    @Test func duplicateReportsDoNotStrandTheDockIcon() {
        let rig = Rig()
        rig.open()
        rig.open()
        rig.system.isActive = false
        rig.system.owner = .anotherApp
        rig.close()
        rig.close()
        rig.system.drain()

        #expect(rig.system.actions == [.policy(.regular), .policy(.accessory)])
    }

    @Test func anotherEditorKeepsTheAppRegular() {
        let rig = Rig()
        let second = NSObject()
        rig.open()
        rig.controller.editorDidOpen(ObjectIdentifier(second))
        rig.close()
        rig.system.drain()
        #expect(rig.system.actions == [.policy(.regular)])

        rig.system.isActive = false
        rig.system.owner = .anotherApp
        rig.controller.editorDidClose(ObjectIdentifier(second))
        rig.system.drain()
        #expect(rig.system.policy == .accessory)
    }

    @Test func notificationsCoalesceAndNeverRepeatTheHide() {
        let rig = Rig()
        rig.open()
        rig.close()
        rig.controller.applicationStateDidChange()
        rig.controller.applicationStateDidChange()
        #expect(rig.system.queued.count == 1)
        rig.system.drain()
        rig.controller.applicationStateDidChange()
        rig.system.drain()

        #expect(rig.system.actions == [.policy(.regular), .hide])
        #expect(rig.system.queued.isEmpty)
    }

    @Test func refusedDemotionCanRetryOnTheNextLifecycleEvent() {
        let rig = Rig()
        rig.open()
        rig.system.isActive = false
        rig.system.owner = .anotherApp
        rig.system.acceptsPolicy = false
        rig.close()
        rig.system.drain()
        #expect(rig.system.policy == .regular)
        #expect(rig.system.queued.isEmpty)

        rig.system.acceptsPolicy = true
        rig.controller.applicationStateDidChange()
        rig.system.drain()
        #expect(rig.system.policy == .accessory)
    }

    @Test func repeatedOpenCloseCyclesReturnToAccessory() {
        let rig = Rig()
        for _ in 0..<3 {
            rig.open()
            rig.system.isActive = true
            rig.system.owner = .thisApp
            rig.close()
            rig.system.drain()
            rig.system.isActive = false
            rig.system.owner = .anotherApp
            rig.controller.applicationStateDidChange()
            rig.system.drain()
            #expect(rig.system.policy == .accessory)
        }
        #expect(rig.system.actions.filter { $0 == .hide }.count == 3)
    }

    private struct Rig {
        let editor = NSObject()
        let system: System
        let controller: ActivationPolicyController

        init() {
            let system = System()
            self.system = system
            controller = ActivationPolicyController(environment: system.environment)
        }

        func open() { controller.editorDidOpen(ObjectIdentifier(editor)) }
        func close() { controller.editorDidClose(ObjectIdentifier(editor)) }
    }

    private final class System {
        enum Action: Equatable {
            case policy(NSApplication.ActivationPolicy)
            case hide
        }

        var policy: NSApplication.ActivationPolicy = .accessory
        var isActive = true
        var owner: ActivationPolicyController.MenuBarOwner = .thisApp
        var acceptsPolicy = true
        var actions: [Action] = []
        var queued: [@MainActor @Sendable () -> Void] = []

        var environment: ActivationPolicyController.Environment {
            .init(
                policy: { self.policy },
                isActive: { self.isActive },
                menuBarOwner: { self.owner },
                setPolicy: {
                    self.actions.append(.policy($0))
                    guard self.acceptsPolicy else { return false }
                    self.policy = $0
                    return true
                },
                hide: { self.actions.append(.hide) },
                enqueue: { self.queued.append($0) }
            )
        }

        func drain() {
            let work = queued
            queued.removeAll()
            for action in work { action() }
        }
    }
}
