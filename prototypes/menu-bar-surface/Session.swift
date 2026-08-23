//  PROTOTYPE — throwaway. The recording state every variant renders, and the fake
//  Library it lands in. No persistence: the Library is in memory and dies with the app,
//  because *where* a Recording lives is issue #10's decision, not this ticket's.

import SwiftUI

/// A Recording that has already been saved. Stub — duration and Source name only, which
/// is all any of these surfaces needs to show. What a Recording is actually *called*
/// belongs to issue #10.
struct SavedRecording: Identifiable, Hashable {
    let id = UUID()
    var sourceName: String
    var sourceID: String
    var icon: NSImage?
    var duration: TimeInterval
    var endedAt: Date

    static func == (a: SavedRecording, b: SavedRecording) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Shared, and deliberately *not* owned by the panel.
///
/// `MenuBarExtra` does not build its content until the panel is opened, so a session
/// owned by the panel would not exist — let alone tick — while the panel is closed. That
/// is the whole point of the menu bar icon carrying state, so the state has to outlive
/// the panel. Same reason `LevelMonitor` is a singleton.
@Observable
@MainActor
final class Session {
    static let shared = Session()

    private(set) var recording: Source?
    private(set) var startedAt: Date?

    /// Ticked at 1 Hz by a timer the session owns. Stored rather than computed so that
    /// the *menu bar label* has an observable input — a computed `Date()` difference
    /// would never invalidate anything, which is the same trap that froze the waveform
    /// `Canvas` in the source-picker prototype.
    private(set) var elapsed: TimeInterval = 0

    private(set) var library: [SavedRecording] = []

    /// The Recording the editor window is open on. The standing preference on the map is
    /// that stop auto-saves and opens the editor on the Recording just made, so every
    /// variant routes through this — and so does every Library row, for older ones.
    var editing: SavedRecording?

    private var timer: Timer?

    var isRecording: Bool { recording != nil }

    /// `01:23`, or `1:02:03` past the hour. Monospaced digits are the caller's job.
    var elapsedText: String {
        let total = Int(elapsed)
        let (hours, minutes, seconds) = (total / 3600, (total % 3600) / 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    func start(_ source: Source) {
        guard recording == nil else { return }
        recording = source
        startedAt = Date()
        elapsed = 0
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(startedAt)
                Diag.hit("sessionTick")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stop auto-saves — no save panel, per the map's standing preferences — and hands
    /// back the Recording so the variant can open the editor on it.
    @discardableResult
    func stop() -> SavedRecording? {
        guard let source = recording else { return nil }
        timer?.invalidate()
        timer = nil
        let saved = SavedRecording(sourceName: source.name,
                                   sourceID: source.bundleID,
                                   icon: source.icon,
                                   duration: elapsed,
                                   endedAt: Date())
        library.insert(saved, at: 0)
        recording = nil
        startedAt = nil
        elapsed = 0
        editing = saved
        return saved
    }

    /// Scaffolding. Every variant's recording state, and every icon treatment, is only
    /// visible *while a Recording runs* — and starting one needs an app actually playing
    /// audio, which is not always true when someone sits down to judge this. So the
    /// switcher can start one against a Source that does not exist.
    func toggleDemo() {
        if isRecording { stop(); return }
        start(Source(bundleID: "com.example.DemoSource", name: "Demo Source", icon: nil,
                     isPlaying: true, processes: []))
    }

    func toggle(_ source: Source) {
        if recording?.bundleID == source.bundleID { stop() } else if recording == nil { start(source) }
    }

    /// So the Library deck in variant L has something in it on first launch, before the
    /// evaluator has recorded anything. Obviously fake.
    func seedLibrary() {
        guard library.isEmpty else { return }
        library = [
            SavedRecording(sourceName: "Google Chrome", sourceID: "com.google.Chrome", icon: nil,
                           duration: 412, endedAt: Date(timeIntervalSinceNow: -3_600)),
            SavedRecording(sourceName: "Safari", sourceID: "com.apple.Safari", icon: nil,
                           duration: 96, endedAt: Date(timeIntervalSinceNow: -86_400)),
            SavedRecording(sourceName: "Music", sourceID: "com.apple.Music", icon: nil,
                           duration: 1_845, endedAt: Date(timeIntervalSinceNow: -172_800)),
        ]
    }
}

extension TimeInterval {
    /// `6:52` — durations in the Library, where there is no ticking to align.
    var clockText: String {
        let total = Int(self)
        let (hours, minutes, seconds) = (total / 3600, (total % 3600) / 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - The one control every variant shares

/// The elapsed readout. `.monospacedDigit()` is not cosmetic here: without it the panel
/// (and, in variants that put the time in the menu bar, the menu bar itself) reflows on
/// every tick as the glyph widths change.
struct ElapsedText: View {
    var text: String
    var font: Font

    var body: some View {
        Text(text)
            .font(font)
            .monospacedDigit()
            .contentTransition(.numericText())
    }
}
