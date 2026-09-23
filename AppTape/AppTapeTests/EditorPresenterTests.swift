import Foundation
import Testing

@testable import AppTape

@MainActor
struct EditorPresenterTests {
    @Test func openingBeforeTheWindowActionIsReadyIsRemembered() {
        let rig = Rig()
        rig.presenter.open()
        rig.presenter.bind { rig.system.open() }
        #expect(rig.system.windowCount == 1)
        #expect(rig.system.active)
    }

    @Test func returningRevealsTheSameWindowAndClosingAllowsItToReopen() {
        let rig = Rig()
        let window = FakeWindow()
        rig.presenter.bind { rig.system.open() }
        rig.presenter.attach(window)
        window.hidden = true
        window.minimized = true

        rig.presenter.open()
        rig.presenter.open()

        #expect(!window.hidden)
        #expect(!window.minimized)
        #expect(rig.system.active)
        #expect(rig.system.windowCount == 0)
        #expect(rig.model.model.selection == nil)

        rig.presenter.detach(window)
        rig.presenter.open()
        #expect(rig.system.windowCount == 1)
    }

    final class FakeWindow: EditorWindow {
        var hidden = false
        var minimized = false
        func reveal() {
            hidden = false
            minimized = false
        }
    }

    final class Rig {
        let model = EditorModelTests.Rig()
        let system = FakeSystem()
        let presenter: EditorPresenter

        init() {
            presenter = EditorPresenter(
                model: model.model,
                activateApplication: { [system] in
                    system.active = true
                })
        }
    }

    final class FakeSystem {
        var active = false
        var windowCount = 0
        func open() { windowCount += 1 }
    }
}
