//  PROTOTYPE — throwaway. Variant K: the menu bar item *is* the transport, which means
//  leaving MenuBarExtra for a raw NSStatusItem. The cost of that is the point.

import AppKit
import Combine
import SwiftUI

/// Variant K — **during a Recording, the panel is a detour.**
///
/// The ticket's shaping constraint is that start and stop stay one click. I and J both
/// spend two: one to open the panel, one to hit the control. K spends one — the status
/// item itself carries `● 01:23`, and clicking it stops. The panel is only for choosing a
/// Source, and while recording you reach it with a right-click.
///
/// **This variant cannot be built with `MenuBarExtra`.** Grepped the macOS 27 SwiftUI
/// interface: `MenuBarExtra` exposes exactly two initialiser shapes, `init(content:label:)`
/// and `init(isInserted:content:label:)`. There is no action closure, no `isPresented`
/// binding, and no way to intercept the click — the panel *always* opens. So K drops to
/// `NSStatusItem` and hosts the panel in an `NSPopover` itself, which is the price being
/// judged here: hand-rolled popover lifecycle, hand-rolled activation, and the SwiftUI
/// scene reduced to `isInserted: false`.
enum VariantK {
    static let title = "Menu bar is the transport (NSStatusItem)"
}

@MainActor
final class StatusItemTransport {
    static let shared = StatusItemTransport()

    private var item: NSStatusItem?
    private var popover: NSPopover?
    private var observing = false

    var isInstalled: Bool { item != nil }

    /// Where K's own item actually sits in the bar. Used only by the probe, to tell K's
    /// item apart from the `MenuBarExtra` one in `NSApp.windows`.
    var buttonFrameDescription: String {
        guard let window = item?.button?.window else { return "none" }
        return "x=\(Int(window.frame.minX)) w=\(Int(window.frame.width))"
    }

    func install() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Both edges, so a right-click can be told apart from a left-click. A plain
        // `action` only fires on left-mouse-up.
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.target = self
        item.button?.action = #selector(clicked)
        self.item = item
        refresh()
        startObserving()
    }

    func remove() {
        popover?.performClose(nil)
        popover = nil
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
        // Must be reset, or a later `install()` short-circuits `startObserving()` and the
        // button title stays frozen at whatever second it was removed on. The tracking
        // chain has already broken by then: `track()`'s callback bails on `item == nil`
        // without re-arming, and nothing else ever re-arms it.
        observing = false
    }

    // MARK: - The click

    @objc private func clicked() {
        let isRightClick = NSApp.currentEvent.map {
            $0.type == .rightMouseUp || $0.modifierFlags.contains(.control)
        } ?? false

        // The whole variant, in four lines: a left-click while recording is Stop, and
        // nothing opens.
        if Session.shared.isRecording && !isRightClick {
            Session.shared.stop()
            EditorPresenter.shared.open()
            return
        }
        togglePopover()
    }

    private func togglePopover() {
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        showPopover()
    }

    func showPopover() {
        guard let button = item?.button else { return }
        let popover = self.popover ?? makePopover()
        self.popover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        // Without this the popover's controls come up inactive, because an LSUIElement
        // app is not frontmost. MenuBarExtra does this for you.
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverRoot())
        return popover
    }

    // MARK: - Keeping the title live

    /// `@Observable` reaches AppKit through `withObservationTracking`, but the callback
    /// fires **once** — so it has to re-arm itself after every change.
    private func startObserving() {
        guard !observing else { return }
        observing = true
        track()
    }

    private func track() {
        withObservationTracking {
            _ = Session.shared.isRecording
            _ = Session.shared.elapsedText
            _ = Shell.shared.iconTreatment
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.item != nil else { return }
                self.refresh()
                self.track()
            }
        }
    }

    private func refresh() {
        guard let button = item?.button else { return }
        let treatment = Shell.shared.iconTreatment
        let recording = Session.shared.isRecording
        Diag.hit("statusItemRefresh")

        if let name = treatment.symbolName(recording: recording) {
            let image = NSImage(systemSymbolName: name, accessibilityDescription: recording ? "Recording" : "AppTape")
            // Template so the menu bar tints it for light/dark and for the highlighted
            // state — except while recording, where `.contentTintColor` has to win.
            image?.isTemplate = !(recording && treatment.tintsRed)
            button.image = image
        } else {
            button.image = nil
        }
        button.contentTintColor = (recording && treatment.tintsRed) ? .systemRed : nil
        button.title = treatment.showsTime && recording ? " " + Session.shared.elapsedText : ""
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.toolTip = recording
            ? "Recording \(Session.shared.recording?.name ?? "") — click to stop, right-click for the panel"
            : "AppTape"
    }
}

/// K's panel. Same list as I's, minus the header lock line, plus the switcher — because
/// with `MenuBarExtra` gone this popover is the only way back to the other variants.
private struct PopoverRoot: View {
    @State private var model = SourceModel()
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            VariantI(model: model)
            SwitcherBar()
        }
        .onAppear { model.refresh() }
        .onReceive(tick) { _ in model.refresh() }
    }
}
