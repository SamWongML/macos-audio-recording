import AppKit
import SwiftUI

/// The hand-rolled menu-bar transport: a single `NSStatusItem` whose click
/// toggles a `.transient` `NSPopover` hosting the SwiftUI panel.
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    /// Consumes Escape while the panel is open.
    private var escapeMonitor: Any?

    /// A borderless, invisible host for the fallback anchor when the status
    /// button's frame is unusable. Kept alive only while such a popover is open.
    private var fallbackAnchorWindow: NSWindow?

    /// Whether the observation re-arm loop that keeps the recording clock live is
    /// running. `withObservationTracking` fires once, so it re-arms itself.
    private var observingRecorder = false

    /// Last-seen blocking-message state, so the panel is auto-raised only on the transition into
    /// one — the user pressed record and it was refused (a denial, or too little disk), so the
    /// fix must find them rather than wait behind a closed popover (/0009).
    private var lastBlocked = false

    /// The red recording dot, rendered once. It never changes, so it is not rebuilt
    /// on every tick (only the time title is).
    private lazy var recordingDot: NSImage = Self.makeRecordingDot()
    /// The amber variant, the whole item at 3 hours of Runway: dot and clock both amber, no `⚠`
    /// — red and amber on one item would read as a rendering bug, so colour is the sole signal.
    private lazy var amberDot: NSImage = Self.makeDot(color: .systemOrange)
    private lazy var idleGlyph: NSImage = Self.makeIdleGlyph()

    /// The transport this item is the face of, and the panel's too — accepted from `AppDelegate`,
    /// which is where AppKit's half of the app names its singletons.
    private let recorder: RecordingController
    private let presenter: EditorPresenter

    init(recorder: RecordingController, presenter: EditorPresenter) {
        self.recorder = recorder
        self.presenter = presenter
        super.init()
    }

    /// Installs the status item. Idempotent.
    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            // Both edges so either click reaches us: a left-click while recording is Stop, and a
            // plain action fires on left-mouse-up only.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        refreshStatusItem()
        startObservingRecorder()
    }

    @objc private func statusItemClicked() {
        let isRightClick =
            NSApp.currentEvent.map {
                $0.type == .rightMouseUp || $0.modifierFlags.contains(.control)
            } ?? false
        // The one-click stop: a left-click while recording finalizes and opens the editor.
        if recorder.run.isRecording && !isRightClick {
            recorder.stop()
            return
        }
        togglePanel()
    }

    // MARK: - Status item rendering

    /// Draws the item for the current state: red `● MM:SS` while recording — a pre-rendered
    /// non-template dot plus a monospaced attributed title, because a status-bar button ignores
    /// `contentTintColor` and repaints template images in the bar's own colour, so the red must
    /// arrive baked in.
    private func refreshStatusItem() {
        guard let button = statusItem?.button else { return }
        if recorder.run.isRecording {
            // Amber at 3 hours of Runway: the whole item goes amber, dot and clock together, and
            // reverts silently when the Runway recovers past the hysteresis band.
            let amber = recorder.run.runwayTier == .amber
            button.image = amber ? amberDot : recordingDot
            button.attributedTitle = NSAttributedString(
                string: " " + recorder.run.elapsedText,
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                    .foregroundColor: amber ? NSColor.systemOrange : NSColor.systemRed,
                ])
            // Colour is the sole signal at the amber tier: the tooltip stays constant, so hovering
            // does not become a second, text channel the ADR deliberately withholds.
            button.toolTip = "Recording — click to stop, right-click for the panel"
        } else {
            button.image = idleGlyph
            button.attributedTitle = NSAttributedString(string: "")
            button.toolTip = "AppTape"
        }
    }

    /// `@Observable` reaches AppKit through `withObservationTracking`, whose callback fires exactly
    /// once — so it re-arms after every change (the pattern settled).
    private func startObservingRecorder() {
        guard !observingRecorder else { return }
        observingRecorder = true
        trackRecorder()
    }

    private func trackRecorder() {
        withObservationTracking {
            _ = recorder.run.isRecording
            _ = recorder.run.elapsed
            _ = recorder.run.permissionRecovery
            _ = recorder.run.runwayTier
            _ = recorder.run.startBlocker
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

    /// Raise the panel the moment a record press is blocked — a denial or a blocker below the
    /// floor — so its one blocking-message surface reaches the user who just pressed record.
    private func raisePanelOnBlockingMessage() {
        let blocked = recorder.run.permissionRecovery || recorder.run.startBlocker != nil
        defer { lastBlocked = blocked }
        guard blocked, !lastBlocked else { return }
        if popover?.isShown != true { showPanel() }
    }

    private static func makeRecordingDot() -> NSImage { makeDot(color: .systemRed) }

    /// A filled dot baked in `color`, non-template so the menu bar cannot repaint it in its own
    /// colour (a status-bar button ignores `contentTintColor`) — the red recording dot and the
    /// amber Runway variant differ only by this colour.
    private static func makeDot(color: NSColor) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        guard
            let base = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Recording")?
                .withSymbolConfiguration(config)
        else { return NSImage(size: NSSize(width: 10, height: 10)) }
        let dot = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        dot.isTemplate = false  // template would repaint it in the bar's colour, losing the tint
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
            // Second click on the item dismisses.
            popover.performClose(nil)
            return
        }
        showPanel()
    }

    private func showPanel() {
        NSApp.unhideWithoutActivation()
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

        // An `LSUIElement` app is not frontmost, so without this the panel's controls come up
        // inactive.
        NSApp.activate()
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        // `.transient`, not `.semitransient`: a semi-transient popover closes on interaction with
        // the window containing its positioning view — the menu bar — so it would effectively
        // never close.
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: PanelView(recorder: recorder, presenter: presenter))
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
            // Only the panel's own Escape is ours.
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

    func popoverWillShow(_ notification: Notification) {
        ActivationPolicyController.shared.panelVisibilityDidChange(isVisible: true)
    }

    func popoverDidShow(_ notification: Notification) {
        installEscapeMonitor()
    }

    func popoverDidClose(_ notification: Notification) {
        removeEscapeMonitor()
        teardownFallbackAnchor()
        ActivationPolicyController.shared.panelVisibilityDidChange(isVisible: false)
    }
}
