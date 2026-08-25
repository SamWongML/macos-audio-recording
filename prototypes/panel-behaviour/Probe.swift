//  PROTOTYPE — issue #22, the hand-rolled panel's behaviour.
//
//  ADR-0004 left MenuBarExtra for a raw NSStatusItem and listed the cost: the app now
//  hand-rolls the popover, its dismissal, and NSApp.activate. macOS 27 shipped
//  NSStatusItemExpandedInterfaceDelegate, which the header says exists for exactly this
//  ("status items which do not use an NSMenu but instead position other windows") and
//  claims buys back "keyboard navigation and menu tracking behaviors".
//
//  Two items sit in the bar so the two designs can be compared click for click:
//
//    S — expandedInterfaceDelegate, popover .applicationDefined, we never call activate.
//    T — target/action only, popover .transient, NSApp.activate on every open.
//        (T is exactly what prototype/menu-bar-surface's variant K does today.)
//
//  Everything either one does is logged to ~/Library/Logs/AppTapePanelProbe.log.

import AppKit
import SwiftUI

// MARK: - Log

enum Log {
    nonisolated(unsafe) static var url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs", directoryHint: .isDirectory)
        return dir.appending(path: "AppTapePanelProbe.log")
    }()

    private nonisolated(unsafe) static var start = Date()

    static func reset() {
        start = Date()
        try? "".write(to: url, atomically: true, encoding: .utf8)
        line("--- probe start ---")
    }

    static func line(_ text: String) {
        let t = String(format: "%7.3f", Date().timeIntervalSince(start))
        let row = "[\(t)] \(text)\n"
        FileHandle.standardError.write(Data(row.utf8))
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(Data(row.utf8))
            try? h.close()
        }
    }
}

/// Whatever event AppKit is currently dispatching, named. The header does not say whether
/// a session begins on left-click, right-click, or both, so every callback records it.
func currentEventDescription() -> String {
    guard let e = NSApp.currentEvent else { return "event=none" }
    let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
    return "event=\(e.type.rawValue)(\(name(e.type))) mods=\(mods.rawValue) clicks=\(e.type == .leftMouseUp || e.type == .rightMouseUp ? String(e.clickCount) : "-")"
}

private func name(_ t: NSEvent.EventType) -> String {
    switch t {
    case .leftMouseDown: "leftMouseDown"
    case .leftMouseUp: "leftMouseUp"
    case .rightMouseDown: "rightMouseDown"
    case .rightMouseUp: "rightMouseUp"
    case .otherMouseDown: "otherMouseDown"
    case .keyDown: "keyDown"
    case .keyUp: "keyUp"
    case .flagsChanged: "flagsChanged"
    case .systemDefined: "systemDefined"
    case .appKitDefined: "appKitDefined"
    case .applicationDefined: "applicationDefined"
    default: "type\(t.rawValue)"
    }
}

/// Who is key, who is active, and what has focus — sampled after every open, because the
/// whole reason variant K calls `NSApp.activate` is that without it "the panel's controls
/// come up inactive".
func focusDescription() -> String {
    let key = NSApp.keyWindow.map { "\(type(of: $0)) title=\"\($0.title)\"" } ?? "none"
    let main = NSApp.mainWindow.map { "\(type(of: $0))" } ?? "none"
    let responder = NSApp.keyWindow?.firstResponder.map { "\(type(of: $0))" } ?? "none"
    return "active=\(NSApp.isActive) key=\(key) main=\(main) firstResponder=\(responder)"
}

// MARK: - Shared panel state

@Observable
@MainActor
final class Panel {
    static let shared = Panel()
    /// Which item opened the panel that is on screen, for the SwiftUI content to name.
    var openedBy = "—"
    var typed = ""
    /// Mirrors NSApp.isActive on a timer so the panel can be watched without the log.
    var appActive = false
}

// MARK: - The panel content

struct PanelBody: View {
    @Bindable var panel = Panel.shared
    @FocusState private var focused: Int?
    var onHideItems: () -> Void
    var onCancelSession: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("opened by \(panel.openedBy)")
                .font(.headline)
            Text(panel.appActive ? "NSApp.isActive = true" : "NSApp.isActive = false")
                .foregroundStyle(panel.appActive ? .green : .red)
                .font(.callout.monospaced())

            Divider()

            // Four focusable rows: does an arrow key move between them without the app
            // having been activated? This is what "participate in keyboard navigation"
            // would have to mean for issue #21 to get anything out of it.
            ForEach(0..<4, id: \.self) { i in
                Button {
                    Log.line("panel: row \(i) clicked — \(focusDescription())")
                } label: {
                    HStack {
                        Image(systemName: focused == i ? "record.circle.fill" : "circle")
                        Text("Row \(i)")
                        Spacer()
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .focusable()
                .focused($focused, equals: i)
            }
            .onChange(of: focused) { _, new in
                Log.line("panel: SwiftUI focus moved to row \(new.map(String.init) ?? "none")")
            }

            Divider()

            // A text field is the sharpest test of key focus: it cannot take a keystroke
            // unless the popover's window is key.
            TextField("type here", text: $panel.typed)
                .textFieldStyle(.roundedBorder)
                .onChange(of: panel.typed) { _, new in
                    Log.line("panel: text field received \"\(new)\" — \(focusDescription())")
                }

            HStack {
                Button("Hide items") { onHideItems() }
                Button("Cancel session") { onCancelSession() }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 260)
        // Whether SwiftUI is even offered the key press, separately from whether AppKit
        // acts on it: run 1 showed Escape reaching the popover window and closing a
        // .transient popover, but never ending an expanded-interface session.
        .onKeyPress(.escape) {
            Log.line("panel: SwiftUI saw Escape")
            return .ignored
        }
    }
}

// MARK: - Controller

@MainActor
final class Controller: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var sessionItem: NSStatusItem!   // S
    private var actionItem: NSStatusItem!    // T
    private var toggleItem: NSStatusItem!    // D — flips S's delegate on and off

    /// One popover each. Run 1 shared a single popover between S and T, which made every
    /// "the session ended" reading ambiguous — clicking T closed S's panel by hand before
    /// AppKit's own tracking could be credited with it.
    private var sessionPopover: NSPopover?
    private var actionPopover: NSPopover?
    /// Set while S's popover is up, so it can be cancelled when the popover closes.
    private var liveSession: NSStatusItemExpandedInterfaceSession?

    func applicationDidFinishLaunching(_ note: Notification) {
        Log.reset()
        Log.line("launch: isActive=\(NSApp.isActive) activationPolicy=\(NSApp.activationPolicy().rawValue)")

        sessionItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        sessionItem.autosaveName = "AppTapePanelProbe.S"
        sessionItem.button?.title = "S"
        sessionItem.expandedInterfaceDelegate = self
        // Deliberately ALSO wired the ADR-0004 way. The header says the delegate "should be
        // used instead of manually toggling your interface by target/action handling", but
        // not that target/action stops firing — and ADR-0004's one-click stop is a
        // target/action on a left-click. Whether the two coexist is the decision.
        sessionItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        sessionItem.button?.target = self
        sessionItem.button?.action = #selector(sessionItemClicked)

        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        toggleItem.autosaveName = "AppTapePanelProbe.D"
        toggleItem.button?.title = "D:on"
        toggleItem.button?.target = self
        toggleItem.button?.action = #selector(toggleDelegate)

        actionItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        actionItem.autosaveName = "AppTapePanelProbe.T"
        actionItem.button?.title = "T"
        actionItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        actionItem.button?.target = self
        actionItem.button?.action = #selector(actionItemClicked)

        // Run 1 logged geometry before the items were placed and read [0,0 29x0]; the
        // placed frame only exists a beat later.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.logGeometry("placed")
        }

        // Escape, and any other key, from wherever it lands.
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { e in
            Log.line("local keyDown: keyCode=\(e.keyCode) chars=\"\(e.charactersIgnoringModifiers ?? "")\" — \(focusDescription())")
            return e
        }
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { e in
            Log.line("global keyDown: keyCode=\(e.keyCode) chars=\"\(e.charactersIgnoringModifiers ?? "")\"")
        }

        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { Panel.shared.appActive = NSApp.isActive }
        }

        // ⌘Q, since an LSUIElement app has no menu bar of its own.
        let menu = NSMenu()
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        let main = NSMenu()
        let holder = NSMenuItem()
        holder.submenu = menu
        main.addItem(holder)
        NSApp.mainMenu = main
    }

    // MARK: Geometry

    /// Where the items actually are. ADR-0004 assumes `item.button` is on screen; with a
    /// full menu bar or a notch it may not be, and the popover has nothing to anchor to.
    private func logGeometry(_ label: String) {
        for (name, item) in [("S", sessionItem), ("T", actionItem), ("D", toggleItem)] {
            guard let item else { continue }
            let b = item.button
            let w = b?.window
            let frame = w.map { "\(Int($0.frame.minX)),\(Int($0.frame.minY)) \(Int($0.frame.width))x\(Int($0.frame.height))" } ?? "no window"
            let onScreen = w.map { win in
                NSScreen.screens.contains { $0.frame.intersects(win.frame) }
            } ?? false
            Log.line("geometry \(label): \(name) visible=\(item.isVisible) button=\(b == nil ? "nil" : "yes") window=[\(frame)] intersectsAScreen=\(onScreen)")
        }
        for (i, s) in NSScreen.screens.enumerated() {
            let inset = s.safeAreaInsets
            Log.line("geometry \(label): screen \(i) frame=\(Int(s.frame.width))x\(Int(s.frame.height)) visible=\(Int(s.visibleFrame.height)) safeAreaTop=\(inset.top) auxTop=\(s.auxiliaryTopLeftArea?.width.description ?? "nil")/\(s.auxiliaryTopRightArea?.width.description ?? "nil")")
        }
        Log.line("geometry \(label): statusBar thickness=\(NSStatusBar.system.thickness)")
    }

    // MARK: Clicks

    @objc private func toggleDelegate() {
        let wasSet = sessionItem.expandedInterfaceDelegate != nil
        sessionItem.expandedInterfaceDelegate = wasSet ? nil : self
        toggleItem.button?.title = wasSet ? "D:off" : "D:on"
        Log.line("D: S.expandedInterfaceDelegate now \(wasSet ? "nil" : "set") — \(currentEventDescription())")
    }

    /// With the delegate set, run 1 never saw this fire on a left-click — only on a
    /// right-click. With the delegate nil it should behave exactly like T.
    @objc private func sessionItemClicked() {
        Log.line("S: target/action FIRED — \(currentEventDescription()) session=\(sessionItem.expandedInterfaceSession == nil ? "nil" : "live") delegate=\(sessionItem.expandedInterfaceDelegate == nil ? "nil" : "set")")
        guard sessionItem.expandedInterfaceDelegate == nil, let button = sessionItem.button else { return }
        if let sessionPopover, sessionPopover.isShown {
            sessionPopover.performClose(nil)
            return
        }
        let p = sessionPopover ?? makePopover(for: .session)
        sessionPopover = p
        show(p, from: button, openedBy: "S (delegate off, target/action, .transient)", behavior: .transient, activate: true)
    }

    @objc private func actionItemClicked() {
        Log.line("T: target/action fired — \(currentEventDescription())")
        guard let button = actionItem.button else { return }
        if let actionPopover, actionPopover.isShown {
            Log.line("T: closing (was shown)")
            actionPopover.performClose(nil)
            return
        }
        let p = actionPopover ?? makePopover(for: .action)
        actionPopover = p
        show(p, from: button, openedBy: "T (target/action, .transient, activates)", behavior: .transient, activate: true)
    }

    // MARK: Popover

    enum Which { case session, action }

    private func show(_ popover: NSPopover, from button: NSStatusBarButton, openedBy: String, behavior: NSPopover.Behavior, activate: Bool) {
        popover.behavior = behavior
        Panel.shared.openedBy = openedBy
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        Log.line("popover shown behavior=\(behavior.rawValue) activate=\(activate) — \(focusDescription())")
        if activate {
            NSApp.activate()
            Log.line("popover after NSApp.activate() — \(focusDescription())")
        }
        // Sampled again a beat later: activation and key-window assignment are not
        // synchronous, so the interesting reading is the settled one.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            Log.line("popover settled — \(focusDescription()) popoverWindow=\(popover.contentViewController?.view.window.map { "\(type(of: $0)) key=\($0.isKeyWindow) canBecomeKey=\($0.canBecomeKey) level=\($0.level.rawValue)" } ?? "none")")
        }
    }

    private func makePopover(for which: Which) -> NSPopover {
        let p = NSPopover()
        p.delegate = self
        p.contentViewController = NSHostingController(rootView: PanelBody(
            onHideItems: { [weak self] in self?.hideItems() },
            onCancelSession: { [weak self] in
                Log.line("panel: Cancel session pressed, session=\(self?.liveSession == nil ? "nil" : "live")")
                self?.liveSession?.cancel()
            }
        ))
        return p
    }

    private func hideItems() {
        Log.line("hiding S and T for 8s")
        sessionItem.isVisible = false
        actionItem.isVisible = false
        logGeometry("while hidden")
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self else { return }
            sessionItem.isVisible = true
            actionItem.isVisible = true
            Log.line("items restored")
            logGeometry("after restore")
        }
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            let who = (notification.object as AnyObject) === (sessionPopover as AnyObject) ? "S" : "T"
            Log.line("popoverDidClose[\(who)] reason=\(notification.userInfo?[NSPopover.closeReasonUserInfoKey] ?? "none") — \(focusDescription())")
            if let liveSession {
                Log.line("popoverDidClose: cancelling live session")
                liveSession.cancel()
                self.liveSession = nil
            }
        }
    }

    nonisolated func popoverDidShow(_ notification: Notification) {
        MainActor.assumeIsolated { Log.line("popoverDidShow — \(focusDescription())") }
    }
}

// MARK: - Expanded interface session

extension Controller: @preconcurrency NSStatusItemExpandedInterfaceDelegate {
    func statusItem(_ statusItem: NSStatusItem, didBegin session: NSStatusItemExpandedInterfaceSession) {
        Log.line("S: didBeginExpandedInterfaceSession — \(currentEventDescription())")
        liveSession = session
        guard let button = statusItem.button else {
            Log.line("S: session began but button is nil — nothing to anchor to")
            return
        }
        let p = sessionPopover ?? makePopover(for: .session)
        sessionPopover = p
        show(p, from: button, openedBy: "S (expanded session, .applicationDefined, no activate)",
             behavior: .applicationDefined, activate: false)
    }

    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        Log.line("S: statusItemDidEndExpandedInterfaceSession animated=\(animated) — \(currentEventDescription())")
        liveSession = nil
        if let sessionPopover, sessionPopover.isShown {
            sessionPopover.performClose(nil)
        }
    }
}

// MARK: - main

@main
enum Probe {
    static func main() {
        let app = NSApplication.shared
        let controller = Controller()
        app.delegate = controller
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
