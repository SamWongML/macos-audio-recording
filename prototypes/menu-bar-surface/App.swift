//  PROTOTYPE — throwaway. Menu bar host for the four menu-bar-surface variants (issue #8).
//
//  Four answers to "what happens when you click the menu bar item", on the real surface:
//    I  no modes — recording is a row state          ← / → switch variants
//    J  recording takes over the panel
//    K  the menu bar item is the transport (NSStatusItem, not MenuBarExtra)
//    L  two decks — Record and Library
//
//  The menu bar *icon* is a separable sub-question, so it cycles independently with
//  ↑ / ↓ across four treatments. Four panels × four icons.

import AppKit
import Combine
import SwiftUI

extension String {
    func appendToFile(_ path: String) throws {
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile(); handle.write(data(using: .utf8)!); handle.closeFile()
        } else {
            try write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Shell state, shared by the SwiftUI panel and K's AppKit popover

enum Variant: String, CaseIterable, Identifiable {
    case i, j, k, l
    var id: String { rawValue }
    var key: String { rawValue.uppercased() }
    var title: String {
        switch self {
        case .i: VariantI.title
        case .j: VariantJ.title
        case .k: VariantK.title
        case .l: VariantL.title
        }
    }
    /// K hand-rolls its own status item, so the SwiftUI scene has to get out of the way.
    var usesStatusItem: Bool { self == .k }
    var next: Variant { Self.allCases[(Self.allCases.firstIndex(of: self)! + 1) % Self.allCases.count] }
    var previous: Variant { Self.allCases[(Self.allCases.firstIndex(of: self)! + Self.allCases.count - 1) % Self.allCases.count] }
}

/// How the menu bar item itself conveys that a Recording is running. Deliberately
/// independent of the panel variant: the ticket asks both questions, and locking one to
/// the other would make it impossible to answer either.
enum IconTreatment: String, CaseIterable, Identifiable {
    /// The glyph changes shape. Reads at a glance, but abandons the app's own mark.
    case glyphSwap
    /// The glyph stays; only the colour changes. Keeps the app recognisable, and relies
    /// entirely on colour — which is the accessibility risk worth looking at.
    case tintOnly
    /// Shape *and* elapsed time, so the menu bar answers "how long" without a click. Costs
    /// menu bar width, permanently, on a bar that is already contested.
    case glyphAndTime
    /// No glyph at all while recording — just the clock. Widest, and the app disappears
    /// from the bar as an identity for the duration.
    case timeOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glyphSwap: "glyph swap"
        case .tintOnly: "tint only"
        case .glyphAndTime: "glyph + time"
        case .timeOnly: "time only"
        }
    }

    var idleSymbol: String { "waveform" }

    func symbolName(recording: Bool) -> String? {
        guard recording else { return idleSymbol }
        switch self {
        case .glyphSwap, .glyphAndTime: return "record.circle.fill"
        case .tintOnly: return idleSymbol
        case .timeOnly: return nil
        }
    }

    var tintsRed: Bool { true }
    var showsTime: Bool { self == .glyphAndTime || self == .timeOnly }

    var next: IconTreatment { Self.allCases[(Self.allCases.firstIndex(of: self)! + 1) % Self.allCases.count] }
    var previous: IconTreatment { Self.allCases[(Self.allCases.firstIndex(of: self)! + Self.allCases.count - 1) % Self.allCases.count] }
}

/// Launch overrides, as `key:value` arguments — `open ... --args variant:k icon:timeOnly`.
/// Arguments rather than environment variables because the app has to be launched through
/// LaunchServices (TCC attribution follows the responsible process, per the source-picker
/// prototype), and `open` passes arguments but not environment.
enum Launch {
    static func value(_ key: String) -> String? {
        CommandLine.arguments.first { $0.hasPrefix(key + ":") }?
            .dropFirst(key.count + 1)
            .description
    }
}

/// Singleton rather than `@State`, because K's popover is hosted by AppKit and has no
/// path to the scene's state.
@Observable
@MainActor
final class Shell {
    static let shared = Shell()
    /// `didSet` rather than an `onChange` in the panel: switching *to* K tears the panel
    /// down, so a modifier living inside it cannot be relied on to see the change.
    var variant: Variant = Launch.value("variant").flatMap(Variant.init(rawValue:)) ?? .i {
        didSet {
            guard variant != oldValue else { return }
            if variant.usesStatusItem { StatusItemTransport.shared.install() }
            else { StatusItemTransport.shared.remove() }
        }
    }
    var iconTreatment: IconTreatment = Launch.value("icon").flatMap(IconTreatment.init(rawValue:)) ?? .glyphSwap
    var showsEvidence = false
}

// MARK: - The editor route

/// A stub. **Issue #7 designs the editor** — all this proves is that the route out of the
/// menu bar exists and where it lands you, which is the part issue #8 owns.
///
/// A plain `NSWindow` rather than a SwiftUI `Window` scene because two of the four call
/// sites (K's status-item click, L's strip) are AppKit or non-View contexts with no
/// `openWindow` in the environment.
@MainActor
final class EditorPresenter {
    static let shared = EditorPresenter()
    private var window: NSWindow?

    func open() {
        let window = self.window ?? make()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func make() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 300),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = "AppTape Editor"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = NSHostingController(rootView: EditorStub())
        return window
    }
}

private struct EditorStub: View {
    private var session: Session { .shared }

    var body: some View {
        VStack(spacing: 14) {
            if let recording = session.editing {
                Image(systemName: "waveform")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text(recording.sourceName).font(.title2)
                Text("\(recording.duration.clockText) · recorded \(recording.endedAt.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(.secondary)
            } else {
                Text("No Recording").font(.title2).foregroundStyle(.secondary)
            }
            Text("Editor stub — issue #7 designs this window.\nOnly the route here is issue #8's question.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

// MARK: - App

@main
struct MenuBarSurfacePrototypeApp: App {
    @State private var model = SourceModel()
    private var shell: Shell { .shared }

    /// Fast enough that a video starting in Chrome shows up while the panel is open.
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    init() {
        Diag.start()
        MainActor.assumeIsolated {
            // K's status item is installed by `Shell.variant`'s `didSet`, which has not
            // fired yet for the initial value — so seed it here.
            if Shell.shared.variant.usesStatusItem { StatusItemTransport.shared.install() }
            Self.startProbeIfAsked()
        }
    }

    /// `PROBE=1` drives a Recording with no human and no audio, purely so the *menu bar*
    /// can be measured while the panel is closed. Two things this prototype needs to know
    /// and cannot learn by looking:
    ///
    /// 1. does a `MenuBarExtra` label rebuild at 1 Hz when nothing is on screen, or does
    ///    it go stale the way the source-picker `Canvas` did, and
    /// 2. does `withObservationTracking` keep K's `NSStatusButton` title live.
    ///
    /// Run with `DIAG=1 PROBE=1` and read `/tmp/ticks.log`.
    @MainActor
    private static func startProbeIfAsked() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["PROBE"] == "1" || CommandLine.arguments.contains("probe") else { return }
        let fake = Source(bundleID: "com.example.Probe", name: "Probe", icon: nil,
                          isPlaying: true, processes: [])
        let timer = Timer(timeInterval: 3.0, repeats: false) { _ in
            MainActor.assumeIsolated {
                Session.shared.start(fake)
                FileHandle.standardError.write("PROBE started a Recording\n".data(using: .utf8)!)
            }
        }
        RunLoop.main.add(timer, forMode: .common)

        // How many status items this process actually owns. `MenuBarExtra` puts an
        // `NSStatusBarWindow` in `NSApp.windows`, so counting them is the only in-process
        // way to check that `isInserted: false` really removes the SwiftUI item rather
        // than merely hiding it — which decides whether variant K shows one item or two.
        let census = Timer(timeInterval: 6.0, repeats: false) { _ in
            MainActor.assumeIsolated {
                let bars = NSApp.windows.filter { $0.className.contains("StatusBar") }
                let detail = bars.map { window in
                    "\(window.className)(visible=\(window.isVisible) x=\(Int(window.frame.minX)) w=\(Int(window.frame.width)))"
                }.joined(separator: " ")
                let line = "PROBE variant=\(Shell.shared.variant.key) ownStatusItem=\(StatusItemTransport.shared.buttonFrameDescription)"
                    + " statusBarWindows=\(bars.count) \(detail)\n"
                FileHandle.standardError.write(line.data(using: .utf8)!)
                try? line.appendToFile("/tmp/census.log")
            }
        }
        RunLoop.main.add(census, forMode: .common)
    }

    var body: some Scene {
        // `isInserted` is the only lever `MenuBarExtra` gives over its own presence, and
        // it is what lets K take the menu bar over without a second item appearing.
        MenuBarExtra(isInserted: Binding(get: { !shell.variant.usesStatusItem },
                                         set: { _ in })) {
            VStack(spacing: 0) {
                switch shell.variant {
                case .i: VariantI(model: model)
                case .j: VariantJ(model: model)
                // K's panel lives in its own NSPopover; this branch only shows while the
                // scene is being torn out, and explains itself if it is ever seen.
                case .k: Text("Variant K runs on an NSStatusItem — look for the item to the left.")
                        .padding(24).frame(width: 320)
                case .l: VariantL(model: model)
                }

                if shell.showsEvidence { evidence }
                SwitcherBar()
            }
            .background {
                // Reduce Transparency is a system-wide setting, not a per-app style
                // choice: when it is on, vibrancy must give way to an opaque background.
                PanelBackground()
            }
            .onAppear { model.refresh() }
            .onReceive(tick) { _ in model.refresh() }
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }

    private var evidence: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            Text("\(model.processes.count) HAL clients · \(model.processes.filter(\.isRunningOutput).count) playing")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.processes.sorted { $0.isRunningOutput && !$1.isRunningOutput }) { process in
                        HStack(spacing: 5) {
                            Text(process.isRunningOutput ? "▶" : "·")
                                .foregroundStyle(process.isRunningOutput ? Color.accentColor : Color.secondary.opacity(0.5))
                            Text(process.bundleID.isEmpty ? "(no bundle ID)" : process.bundleID)
                            Spacer(minLength: 4)
                            Text(process.appName ?? "no NSRunningApplication")
                                .foregroundStyle(process.appName == nil ? Color.red.opacity(0.8) : .secondary)
                        }
                        .font(.system(size: 9, design: .monospaced))
                        .lineLimit(1)
                    }
                }
                .padding(.horizontal, 10)
            }
            .frame(height: 130)
        }
    }
}

struct PanelBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else {
            Rectangle().fill(.ultraThickMaterial)
        }
    }
}

// MARK: - The menu bar label (variants I, J, L)

/// Whether an arbitrary `HStack` renders in a `MenuBarExtra` label — and whether it
/// re-renders at 1 Hz while the panel is *closed* — is one of the things this prototype
/// is here to find out. `Diag.hit` counts the rebuilds.
private struct MenuBarLabel: View {
    private var session: Session { .shared }
    private var shell: Shell { .shared }

    var body: some View {
        let recording = session.isRecording
        let treatment = shell.iconTreatment
        let _ = Diag.hit("menuBarLabel")

        HStack(spacing: 3) {
            if let symbol = treatment.symbolName(recording: recording) {
                Image(systemName: symbol)
                    .foregroundStyle(recording && treatment.tintsRed ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
            }
            if treatment.showsTime && recording {
                Text(session.elapsedText)
                    .monospacedDigit()
                    .foregroundStyle(recording && treatment.tintsRed ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
            }
        }
    }
}

// MARK: - Scaffolding

/// Deliberately ugly: this bar is scaffolding, not part of any design being judged.
struct SwitcherBar: View {
    private var shell: Shell { .shared }

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                Button { shell.variant = shell.variant.previous } label: { Image(systemName: "chevron.left") }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Text("\(shell.variant.key) — \(shell.variant.title)")
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                Button { shell.variant = shell.variant.next } label: { Image(systemName: "chevron.right") }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button { shell.showsEvidence.toggle() } label: { Image(systemName: "tablecells") }
                    .help("Show the raw Core Audio process table")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "xmark") }
                    .keyboardShortcut("q")
            }
            HStack(spacing: 8) {
                Button { shell.iconTreatment = shell.iconTreatment.previous } label: { Image(systemName: "chevron.up") }
                    .keyboardShortcut(.upArrow, modifiers: [])
                Text("menu bar icon — \(shell.iconTreatment.title)")
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                Button { shell.iconTreatment = shell.iconTreatment.next } label: { Image(systemName: "chevron.down") }
                    .keyboardShortcut(.downArrow, modifiers: [])
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(8)
        .background(.black.opacity(0.85))
        .foregroundStyle(.white)
    }
}
