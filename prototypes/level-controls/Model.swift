//  PROTOTYPE — throwaway. State for the level-controls question (#25). Shared across the two
//  Level-section treatments so switching keeps the same Recording, Trim, and measurement.

import SwiftUI

// MARK: - The two designs under judgement

/// The ↔ axis of this prototype: how the Level section presents the correction and the Gain.
/// Both obey ADR-0013 (two separate figures, correction as dB never LUFS, the short-fall
/// captions). They differ only in whether the presentation is **stock components** or a
/// **custom-drawn meter** — which is the "official components first, and does this need
/// custom drawing?" test the ticket asks for.
enum Treatment: String, CaseIterable, Identifiable {
    case official   // Toggle + LabeledContent + Slider. No custom drawing at all.
    case meter      // A drawn scale: the target, the measured loudness, the correction, Gain.
    var id: Self { self }
    var title: String {
        switch self {
        case .official: "A · Stock components"
        case .meter:    "B · Custom meter"
        }
    }
    var claim: String {
        switch self {
        case .official:
            "Toggle, a read-out row, a Gain slider — all first-party. If this reads clearly, #25 needs no custom drawing and the level meter is scope you don't take on."
        case .meter:
            "A drawn scale shows where the Recording sits, where −16 is, and how far Gain pushes past it. Buys a picture; costs the one custom control #4 didn't already sign up for."
        }
    }
}

// MARK: - Export settings (the sticky, app-wide half)

/// Minimal stand-in for #9. Here only so the Level section can be seen sitting between the
/// Quality Preset and the size estimate, and so the estimate can be shown **not** moving with
/// Loudness or Gain (#9: the estimate is bytes of codec × duration, nothing to do with level).
enum QualityPreset: String, CaseIterable, Identifiable {
    case master, high, standard, compact
    var id: Self { self }
    var title: String {
        switch self { case .master: "Master quality"; case .high: "High"
                      case .standard: "Standard"; case .compact: "Compact" }
    }
    var subtitle: String {
        switch self { case .master: "24-bit ALAC"; case .high: "AAC 256 kbps"
                      case .standard: "AAC 128 kbps"; case .compact: "HE-AAC 64 kbps" }
    }
    var kbps: Double? {
        switch self { case .master: nil; case .high: 256; case .standard: 128; case .compact: 64 }
    }
    func estimateText(seconds: Double, sampleRate: Double) -> String {
        let bytes: Double = kbps.map { $0 * 1000 / 8 * seconds * 1.02 }
            ?? seconds * sampleRate * 2 * 4 * 0.46
        let mb = bytes / 1_000_000
        if mb >= 100 { return "≈ \(Int(mb.rounded())) MB" }
        if mb >= 10 { return String(format: "≈ %.1f MB", mb) }
        if mb >= 1 { return String(format: "≈ %.2f MB", mb) }
        return String(format: "≈ %.0f KB", bytes / 1000)
    }
}

/// The app-wide, sticky preferences (ADR-0013: normalization and preset are app-wide; **Gain
/// is per-Recording** and lives on `Recording.gain`, so it is deliberately not here).
@MainActor @Observable
final class ExportSettings {
    var preset: QualityPreset = .high
    /// Sticky, app-wide, off on first use (ADR-0013).
    var normalizeLoudness = false
    var treatment: Treatment = .official
    var lastMessage: String?
}

// MARK: - The measurement coordinator

/// Where the BS.1770 pass is triggered and cached. ADR-0013's closing note in one object:
/// build the analyzer once per Recording (async, the only slow part), then re-measure the
/// trimmed range synchronously and cheaply as a handle moves.
enum MeasureState: Equatable {
    case off                       // normalization is off — the resting state
    case measuring                 // first pass over this Recording is running
    case ready(Correction)         // a live figure for the current Trim
}

@MainActor @Observable
final class LoudnessCoordinator {
    private(set) var state: MeasureState = .off
    private var analyzers: [URL: LoudnessAnalyzer] = [:]
    /// Guards against a stale async build landing after the selection moved on.
    private var building: URL?

    /// Recompute for the current selection/trim/normalize, and set the audition gain so what
    /// you hear is what you'd Export. Cheap unless the analyzer must still be built.
    func refresh(_ editor: Editor) {
        guard let recording = editor.selection else { state = .off; return }
        let manualGain = recording.gain

        guard editor.settings.normalizeLoudness else {
            state = .off
            editor.player.setAuditionGain(db: manualGain)          // Gain still auditions
            return
        }

        if let analyzer = analyzers[recording.url] {
            let correction = analyzer.correction(range: recording.trim.range)
            state = .ready(correction)
            editor.player.setAuditionGain(db: correction.gainDB + manualGain)
            return
        }

        // First time for this Recording: the one slow step. Show "Measuring…", audition the
        // manual Gain alone until it lands.
        state = .measuring
        editor.player.setAuditionGain(db: manualGain)
        guard building != recording.url else { return }
        building = recording.url
        let url = recording.url
        Task.detached(priority: .userInitiated) {
            let analyzer = LoudnessAnalyzer.build(url: url)
            await MainActor.run {
                self.building = nil
                guard let analyzer else { self.state = .ready(Correction(gainDB: 0, outcome: .undefined,
                                                        integratedLUFS: nil, truePeakDBTP: nil)); return }
                self.analyzers[url] = analyzer
                // Only apply if this Recording is still the one on screen.
                if editor.selection?.url == url { self.refresh(editor) }
            }
        }
    }

    /// The audition gain the graph is currently applying, for the meter/read-out to echo.
    var appliedGainDB: Double? {
        if case .ready(let c) = state, c.outcome != .undefined { return c.gainDB }
        return nil
    }
}

// MARK: - Editor

@MainActor @Observable
final class Editor {
    var recordings: [Recording] = []
    var selection: Recording?
    /// Fixed to `.whole` here — trim precision is #7's question, not #25's. Kept only because
    /// the reused `TrimTimeline` takes it.
    var precision: Precision = .whole

    let player = Player()
    let settings = ExportSettings()
    let timeline = TimelineState()
    let loudness = LoudnessCoordinator()

    func loadLibrary() {
        recordings = Library.load()
        for recording in recordings { EnvelopeLoader.load(recording) }
        if selection == nil || !recordings.contains(where: { $0.url == selection?.url }) {
            select(recordings.first)
        }
    }

    func select(_ recording: Recording?) {
        selection = recording
        guard let recording else { return }
        player.load(recording)
        timeline.reset(duration: recording.duration)
        EnvelopeLoader.load(recording)
        loudness.refresh(self)
    }

    func recording(for url: URL) -> Recording? { recordings.first { $0.url == url } }
}
