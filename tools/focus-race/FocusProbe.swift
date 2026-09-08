//
//  FocusProbe.swift
//  AppTape
//
//  THROWAWAY instrumentation for issue #113. Never merged — drop it into
//  `AppTape/AppTape/`, call `_ = FocusProbe.install` first thing in
//  `AppDelegate.applicationDidFinishLaunching`, and hang `.focusProbe()` off the
//  editor's body next to `.editorActivationPolicy()`. Set `APPTAPE_PROBE_LOG` to a
//  writable path or it does nothing at all.
//
//  What it is for: the editor opened with no first responder at 1200 × 680 and with
//  one at 1201 × 680, and neither the fill nor `AXFocusedUIElement` says *who*
//  decided. Swizzling `makeFirstResponder` and printing the stack is what named
//  `-[NSWindow _setUpFirstResponder]` → `_selectFirstKeyView`, called once from
//  `_doOrderWindow:`, and `outline=absent` in the same line is what showed the list
//  was not there to be chosen.
//

import AppKit
import ObjectiveC
import SwiftUI

enum FocusProbe {
    static let path = ProcessInfo.processInfo.environment["APPTAPE_PROBE_LOG"]
    nonisolated(unsafe) static let t0 = Date()

    static func log(_ s: String) {
        guard let path else { return }
        let line = String(format: "%7.3f  %@\n", Date().timeIntervalSince(t0), s)
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile(); fh.write(line.data(using: .utf8)!); try? fh.close()
        } else {
            try? line.write(toFile: path, atomically: false, encoding: .utf8)
        }
    }

    static func describe(_ r: NSResponder?) -> String {
        guard let r else { return "nil" }
        if let v = r as? NSView { return "\(type(of: v))" }
        return "\(type(of: r))"
    }

    /// Walk a view tree looking for SwiftUI's sidebar list.
    static func findOutline(_ v: NSView?) -> NSView? {
        guard let v else { return nil }
        if String(describing: type(of: v)).contains("OutlineListView") { return v }
        for sub in v.subviews { if let hit = findOutline(sub) { return hit } }
        return nil
    }

    static let install: Void = {
        guard path != nil else { return }
        let cls: AnyClass = NSWindow.self
        for (orig, swiz) in [(#selector(NSWindow.makeFirstResponder(_:)), #selector(NSWindow.probe_makeFirstResponder(_:))),
                             (#selector(NSWindow.makeKeyAndOrderFront(_:)), #selector(NSWindow.probe_makeKeyAndOrderFront(_:))),
                             (#selector(NSWindow.becomeKey), #selector(NSWindow.probe_becomeKey)),
                             (#selector(NSWindow.setFrame(_:display:)), #selector(NSWindow.probe_setFrame(_:display:)))] {
            if let m = class_getInstanceMethod(cls, orig), let s = class_getInstanceMethod(cls, swiz) {
                method_exchangeImplementations(m, s)
            }
        }
        log("swizzles installed")
    }()
}

extension NSWindow {
    private var probe_isEditor: Bool { frameAutosaveName == "editor" || title == "AppTape" || identifier?.rawValue == "editor" }

    private func probe_note(_ tag: String) {
        guard probe_isEditor || FocusProbe.findOutline(contentView) != nil else { return }
        FocusProbe.log("\(tag) [\(type(of: self))] frame=\(NSStringFromRect(frame)) key=\(isKeyWindow) "
            + "first=\(FocusProbe.describe(firstResponder)) initial=\(FocusProbe.describe(initialFirstResponder)) "
            + "outline=\(FocusProbe.findOutline(contentView).map { "\(type(of: $0))" } ?? "absent")")
    }

    @objc fileprivate func probe_makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let ok = probe_makeFirstResponder(responder)   // swizzled: calls the original
        if probe_isEditor || FocusProbe.findOutline(contentView) != nil {
            FocusProbe.log("makeFirstResponder(\(FocusProbe.describe(responder))) -> \(ok) "
                + "now=\(FocusProbe.describe(firstResponder)) key=\(isKeyWindow) "
                + "outline=\(FocusProbe.findOutline(contentView) != nil)\n"
                + Thread.callStackSymbols.dropFirst().prefix(9).map { "            " + $0 }.joined(separator: "\n"))
        }
        return ok
    }

    @objc fileprivate func probe_makeKeyAndOrderFront(_ sender: Any?) {
        probe_note("makeKeyAndOrderFront BEFORE")
        probe_makeKeyAndOrderFront(sender)
        probe_note("makeKeyAndOrderFront AFTER")
    }

    @objc fileprivate func probe_becomeKey() {
        probe_note("becomeKey BEFORE")
        probe_becomeKey()
        probe_note("becomeKey AFTER")
    }

    @objc fileprivate func probe_setFrame(_ r: NSRect, display: Bool) {
        probe_note("setFrame(\(NSStringFromRect(r))) BEFORE")
        probe_setFrame(r, display: display)
    }
}

extension View {
    func focusProbe() -> some View { background(FocusProbeView()) }
}

private struct FocusProbeView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ProbeView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class ProbeView: NSView {
        private var started = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let w = window, !started else { return }
            started = true
            FocusProbe.log("probe attached: frame=\(NSStringFromRect(w.frame)) key=\(w.isKeyWindow) "
                + "first=\(FocusProbe.describe(w.firstResponder)) initial=\(FocusProbe.describe(w.initialFirstResponder)) "
                + "outline=\(FocusProbe.findOutline(w.contentView) != nil)")
            for i in [1, 3, 5, 10, 20, 40] {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.1) { [weak self] in
                    guard let w = self?.window else { return }
                    FocusProbe.log(String(format: "poll+%.1fs: first=%@ initial=%@ outline=%@", Double(i) * 0.1,
                                          FocusProbe.describe(w.firstResponder),
                                          FocusProbe.describe(w.initialFirstResponder),
                                          FocusProbe.findOutline(w.contentView) != nil ? "present" : "absent"))
                }
            }
        }
    }
}
