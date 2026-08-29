//
//  MenuBarController.swift
//  AppTape
//

import AppKit
import SwiftUI

/// The hand-rolled menu-bar transport: a single `NSStatusItem` whose click
/// toggles a `.transient` `NSPopover` hosting the SwiftUI panel.
///
/// This replaces SwiftUI's `MenuBarExtra`, which cannot intercept its own click
/// (ADR-0004), and so must hand-roll each thing `MenuBarExtra` did for free
/// (ADR-0011): the popover and its lifecycle, `.transient` dismissal, an
/// app-owned Escape, `NSApp.activate()`, and anchoring that treats the button's
/// frame as a claim to be checked. Intercepting the click is what buys the
/// one-click stop: while a Recording runs the item itself becomes red `● MM:SS`
/// and a left-click stops it, with the panel a right-click away (issue #8).
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    /// Consumes Escape while the panel is open. A plain `.transient` popover
    /// closes on Escape for free — until a SwiftUI `.onKeyPress` anywhere in the
    /// panel takes that away, even one returning `.ignored` (ADR-0011). So
    /// Escape is the app's, owned here and never left to AppKit.
    private var escapeMonitor: Any?

    /// A borderless, invisible host for the fallback anchor when the status
    /// button's frame is unusable. Kept alive only while such a popover is open.
    private var fallbackAnchorWindow: NSWindow?

    /// Whether the observation re-arm loop that keeps the recording clock live is
    /// running. `withObservationTracking` fires once, so it re-arms itself.
    private var observingRecorder = false

    /// Last-seen blocking-message state, so the panel is auto-raised only on the transition into
    /// one — the user pressed record and it was refused (a denial, or too little disk), so the fix
    /// must find them rather than wait behind a closed popover (ADR-0008/0009).
    private var lastBlocked = false

    /// The red recording dot, rendered once. It never changes, so it is not rebuilt
    /// on every tick (only the time title is).
    private lazy var recordingDot: NSImage = Self.makeRecordingDot()
    /// The amber variant, the whole item at 3 hours of Runway (ADR-0009): dot and clock both amber,
    /// no `⚠` — red and amber on one item would read as a rendering bug, so colour is the sole signal.
    /// A conscious accessibility trade, since the 30-minute tier is text and reaches everyone.
    private lazy var amberDot: NSImage = Self.makeDot(color: .systemOrange)
    private lazy var idleGlyph: NSImage = Self.makeIdleGlyph()

    private var recorder: RecordingController { .shared }

    /// Installs the status item. Idempotent.
    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            // Both edges so either click reaches us (ADR-0004): a left-click while
            // recording is Stop, and a plain action fires on left-mouse-up only.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        refreshStatusItem()
        startObservingRecorder()
    }

    @objc private func statusItemClicked() {
        let isRightClick = NSApp.currentEvent.map {
            $0.type == .rightMouseUp || $0.modifierFlags.contains(.control)
        } ?? false
        // The one-click stop: a left-click while recording finalizes and opens the
        // editor (issue #8, ADR-0016). The panel is reached with a right-click while
        // recording, and with either click at rest.
        if recorder.isRecording && !isRightClick {
            recorder.stop()
            return
        }
        togglePanel()
    }

    // MARK: - Status item rendering

    /// Draws the item for the current state: red `● MM:SS` while recording — a
    /// pre-rendered non-template dot plus a monospaced attributed title, because a
    /// status-bar button ignores `contentTintColor` and repaints template images in the
    /// bar's own colour, so the red must arrive baked in (issue #8). At rest, a plain
    /// template waveform the menu bar tints for light/dark itself. The title sits at
    /// `00:00` until the first sound, since it reads master duration (ADR-0016).
    private func refreshStatusItem() {
        guard let button = statusItem?.button else { return }
        if recorder.isRecording {
            // Amber at 3 hours of Runway (ADR-0009): the whole item goes amber, dot and clock
            // together, and reverts silently when the Runway recovers past the hysteresis band.
            let amber = recorder.runwayTier == .amber
            button.image = amber ? amberDot : recordingDot
            button.attributedTitle = NSAttributedString(
                string: " " + recorder.elapsedText,
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                    .foregroundColor: amber ? NSColor.systemOrange : NSColor.systemRed,
                ])
            // Colour is the sole signal at the amber tier (ADR-0009): the tooltip stays constant, so
            // hovering does not become a second, text channel the ADR deliberately withholds.
            button.toolTip = "Recording — click to stop, right-click for the panel"
        } else {
            button.image = idleGlyph
            button.attributedTitle = NSAttributedString(string: "")
            button.toolTip = "AppTape"
        }
    }

    /// `@Observable` reaches AppKit through `withObservationTracking`, whose callback
    /// fires exactly once — so it re-arms after every change (the pattern issue #8
    /// settled). Reading `elapsed` keeps the clock ticking while the panel is closed.
    private func startObservingRecorder() {
        guard !observingRecorder else { return }
        observingRecorder = true
        trackRecorder()
    }

    private func trackRecorder() {
        withObservationTracking {
            _ = recorder.isRecording
            _ = recorder.elapsed
            _ = recorder.permissionRecovery
            _ = recorder.runwayTier
            _ = recorder.startRefusal
        } onChange: { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard self.statusItem != nil else { return }
                self.refreshStatusItem()
                self.raisePanelOnBlockingMessage()
                self.trackRecorder()
            }
        }
    }

    /// Raise the panel the moment a record press is blocked — a denial (ADR-0008) or a refusal below
    /// the floor (ADR-0009) — so its one blocking-message surface reaches the user who just pressed
    /// record. Only on the transition into a blocked state, and only if the panel is not already up,
    /// so it is not re-shown on every tick while the message stands.
    private func raisePanelOnBlockingMessage() {
        let blocked = recorder.permissionRecovery || recorder.startRefusal != nil
        defer { lastBlocked = blocked }
        guard blocked, !lastBlocked else { return }
        if popover?.isShown != true { showPanel() }
    }

    private static func makeRecordingDot() -> NSImage { makeDot(color: .systemRed) }

    /// A filled dot baked in `color`, non-template so the menu bar cannot repaint it in its own
    /// colour (a status-bar button ignores `contentTintColor`, ADR-0004) — the red recording dot and
    /// the amber Runway variant differ only by this colour.
    private static func makeDot(color: NSColor) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        guard let base = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Recording")?
            .withSymbolConfiguration(config) else { return NSImage(size: NSSize(width: 10, height: 10)) }
        let dot = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        dot.isTemplate = false   // template would repaint it in the bar's colour, losing the tint
        return dot
    }

    private static func makeIdleGlyph() -> NSImage {
        let glyph = NSImage(systemSymbolName: "waveform", accessibilityDescription: "AppTape")
        glyph?.isTemplate = true
        return glyph ?? NSImage(size: NSSize(width: 16, height: 16))
    }

    // MARK: - Panel

    private func togglePanel() {
        if let popover, popover.isShown {
            // Second click on the item dismisses (ADR-0011).
            popover.performClose(nil)
            return
        }
        showPanel()
    }

    private func showPanel() {
        let popover = self.popover ?? makePopover()
        self.popover = popover

        let anchor = PanelAnchoring.anchor(
            buttonWindowFrame: statusItem?.button?.window?.frame,
            screens: NSScreen.screens.map(\.frame),
            mainScreen: NSScreen.main?.frame,
            statusBarThickness: NSStatusBar.system.thickness
        )

        switch anchor {
        case .statusButton:
            if let button = statusItem?.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
            }
        case .screenFallback(let rect):
            let host = makeFallbackAnchorWindow(at: rect)
            fallbackAnchorWindow = host
            if let anchorView = host.contentView {
                popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxY)
            }
        }

        // An `LSUIElement` app is not frontmost, so without this the panel's
        // controls come up inactive. `NSApp.activate()`, not the deprecated
        // `activateIgnoringOtherApps:` (ADR-0011); the theft is temporary —
        // every close hands the front back.
        NSApp.activate()
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        // `.transient`, not `.semitransient`: a semi-transient popover closes on
        // interaction with the window containing its positioning view — the menu
        // bar — so it would effectively never close (ADR-0011).
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PanelView())
        return popover
    }

    // MARK: - Escape

    private var popoverWindow: NSWindow? {
        popover?.contentViewController?.view.window
    }

    private func installEscapeMonitor() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, event.keyCode == 53 else { return event }  // 53 == Escape
            // Only the panel's own Escape is ours. If the editor window (which
            // can coexist with the panel, ADR-0017) holds the key, let Escape
            // through to it rather than dismissing a background popover.
            guard self.popoverWindow?.isKeyWindow == true else { return event }
            self.popover?.performClose(nil)
            return nil  // consumed, so it never reaches the panel's own key handling
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        escapeMonitor = nil
    }

    // MARK: - Fallback anchor

    private func makeFallbackAnchorWindow(at rect: CGRect) -> NSWindow {
        let window = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .statusBar
        window.backgroundColor = .clear
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.contentView = NSView(frame: CGRect(origin: .zero, size: rect.size))
        window.setFrame(rect, display: false)
        window.orderFrontRegardless()
        return window
    }

    private func teardownFallbackAnchor() {
        fallbackAnchorWindow?.orderOut(nil)
        fallbackAnchorWindow = nil
    }

    // MARK: - NSPopoverDelegate

    func popoverDidShow(_ notification: Notification) {
        installEscapeMonitor()
    }

    func popoverDidClose(_ notification: Notification) {
        removeEscapeMonitor()
        teardownFallbackAnchor()
    }
}
