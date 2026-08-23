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

    /// Relaunch into `variant`, carrying the current icon treatment.
    ///
    /// Scaffolding, and the honest way to do it: `MenuBarExtra`'s `isInserted` is only
    /// read when the scene is built, so which of the two menu bar implementations owns the
    /// bar is a launch-time decision. Pretending otherwise is what broke.
    ///
    /// The relaunch is handed to a detached `sh`, and this instance quits **first**. Going
    /// the other way round — `NSWorkspace.openApplication` with
    /// `createsNewApplicationInstance`, then terminate — was tried and left the new
    /// instance with **no menu bar item at all** (`x=0`, never placed): two instances of
    /// the same `LSUIElement` bundle overlap, and the one still holding the slot wins.
    @MainActor
    static func relaunch(into variant: Variant) {
        let passthrough = CommandLine.arguments.dropFirst().filter {
            !$0.hasPrefix("variant:") && !$0.hasPrefix("icon:") && !$0.hasPrefix("switchto:")
        }
        let arguments = passthrough + [
            "variant:\(variant.rawValue)",
            "icon:\(Shell.shared.iconTreatment.rawValue)",
        ]
        let quoted = ([Bundle.main.bundleURL.path] + arguments)
            .map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let command = "sleep 1; open -a \(quoted[0]) --args \(quoted.dropFirst().joined(separator: " "))"

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", command]
        try? task.run()
        NSApp.terminate(nil)
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
            // Only crossing the K boundary needs anything; I ↔ J ↔ L is an instant swap
            // of the panel's contents.
            if variant.usesStatusItem != oldValue.usesStatusItem { Launch.relaunch(into: variant) }
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
            if Shell.shared.variant.usesStatusItem {
                StatusItemTransport.shared.install()
                // Nothing else in K is on screen, and the switcher lives in its popover —
                // so open it, or a relaunch into K looks like the app failed to start.
                let reveal = Timer(timeInterval: 0.4, repeats: false) { _ in
                    MainActor.assumeIsolated { StatusItemTransport.shared.showPopover() }
                }
                RunLoop.main.add(reveal, forMode: .common)
            }
            Self.startProbeIfAsked()
        }
    }

    /// `probe` drives a Recording with no human and no audio, purely so the *menu bar* can
    /// be measured while the panel is closed. Three things this prototype needed to know
    /// and could not learn by looking:
    ///
    /// 1. does a `MenuBarExtra` label rebuild at 1 Hz when nothing is on screen, or does
    ///    it go stale the way the source-picker `Canvas` did,
    /// 2. does `withObservationTracking` keep K's `NSStatusButton` title live, and
    /// 3. is there ever more than one item in the bar (`switchto:`, below).
    ///
    /// `./run.sh` then `open -a build/…app --args diag probe [variant:k] [icon:timeOnly]
    /// [switchto:l]`; read `/tmp/ticks.log` and `/tmp/switch.log`.
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

        // How many status items this process actually owns, and whether any of them
        // actually reached the bar. `MenuBarExtra` puts an `NSStatusBarWindow` in
        // `NSApp.windows`, and an item that was never placed sits at x=0.
        let census = Timer(timeInterval: 6.0, repeats: false) { _ in
            MainActor.assumeIsolated { Self.log("CENSUS " + Self.census()) }
        }
        RunLoop.main.add(census, forMode: .common)

        // `switchto:<variant>` drives the *switching* path, which the launch-into-a-variant
        // probes never touch — and which is where the reported stuck button lived. It is
        // dropped on relaunch, so the next instance just censuses.
        guard let target = Launch.value("switchto").flatMap(Variant.init(rawValue:)) else { return }
        let step = Timer(timeInterval: 4.0, repeats: false) { _ in
            MainActor.assumeIsolated {
                Self.log("SWITCH -> \(target.key)")
                Shell.shared.variant = target
            }
        }
        RunLoop.main.add(step, forMode: .common)
    }

    @MainActor
    private static func census() -> String {
        let bars = NSApp.windows.filter { $0.className.contains("StatusBar") }
        let placed = bars.filter { $0.frame.minX > 0 }
        let detail = bars.map { "x=\(Int($0.frame.minX))w=\(Int($0.frame.width))" }.joined(separator: " ")
        return "variant=\(Shell.shared.variant.key) inBar=\(placed.count) ownItem=\(StatusItemTransport.shared.buttonFrameDescription) all[\(detail)]"
    }

    private static func log(_ line: String) {
        FileHandle.standardError.write((line + "\n").data(using: .utf8)!)
        try? (line + "\n").appendToFile("/tmp/switch.log")
    }

    var body: some Scene {
        // Evaluated **once**, at launch — and that is now the whole contract.
        //
        // An `App`'s scene body does not re-evaluate when an `@Observable` it reads
        // changes. Measured, not assumed: reading `variant` inside the `isInserted`
        // getter, reading it directly in the body, and holding `Shell` in `@State` all
        // behaved identically — the scene was built once and `isInserted` never read
        // again. That was the stuck menu bar button: switching to K installed K's item
        // while the SwiftUI item stayed put, two items landing on the same coordinate
        // with clicks going to whichever was on top.
        //
        // So crossing the K boundary relaunches instead (see `Launch.relaunch`), which
        // keeps this a launch-time decision — the only kind `MenuBarExtra` honours.
        let usesStatusItem = shell.variant.usesStatusItem
        MenuBarExtra(isInserted: .constant(!usesStatusItem)) {
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
