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
/// frame as a claim to be checked. The glyph is a static placeholder here; the
/// live recording transport is designed in issue #8.
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

    /// Installs the status item. Idempotent.
    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let glyph = NSImage(systemSymbolName: "waveform", accessibilityDescription: "AppTape")
            glyph?.isTemplate = true
            button.image = glyph
            button.target = self
            button.action = #selector(statusItemClicked)
            // Both edges so either click opens the panel (ADR-0004); a plain
            // action fires on left-mouse-up only.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    @objc private func statusItemClicked() {
        togglePanel()
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
