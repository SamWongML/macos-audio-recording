//  PROTOTYPE — throwaway. The Level section itself: the normalization toggle, the applied-
//  correction read-out, and the manual Gain, in the two treatments Model.Treatment names.
//
//  What is inherited and NOT re-decided here (ADR-0013 / #7): the section lives in the
//  permanent trailing inspector between Quality Preset and the size estimate; the target is
//  −16 LUFS / −3 dBTP; the correction is a dB figure, never LUFS, with a caption only when it
//  falls short; Loudness and Gain are two separate figures; the toggle is app-wide and off by
//  default. What #25 settles is how all that *reads and feels* — and whether it needs custom
//  drawing, which is the whole reason treatment B exists to be compared against A.

import SwiftUI

// MARK: - The inspector (the #7 frame; Level is the part that is #25's)

struct ExportInspector: View {
    var editor: Editor
    var recording: Recording

    var body: some View {
        Form {
            Section("Quality Preset") {
                Picker("Quality", selection: Bindable(editor.settings).preset) {
                    ForEach(QualityPreset.allCases) { Text("\($0.title) — \($0.subtitle)").tag($0) }
                }
                .labelsHidden()
            }

            Section("Level") {
                LevelControls(editor: editor, recording: recording)
            }

            Section {
                LabeledContent("Estimated size") {
                    // #9: never moved by Loudness or Gain. Shown here so that stays visible.
                    Text(recording.estimateText(editor.settings.preset)).monospacedDigit()
                }
                LabeledContent("Length") {
                    Text(Format.time(recording.trimmedDuration)).monospacedDigit()
                }
                Button("Export…") {
                    editor.settings.lastMessage = exportSummary
                    Diag.note(exportSummary)
                }
                .buttonStyle(.glassProminent)
                .frame(maxWidth: .infinity)
                .keyboardShortcut("e")
            }
        }
        .formStyle(.grouped)
        // The two triggers that re-measure: turning normalization on, and moving a Trim
        // handle. Selection and Gain refresh at their own sources.
        .onChange(of: editor.settings.normalizeLoudness) { editor.loudness.refresh(editor) }
        .onChange(of: recording.trim) { editor.loudness.refresh(editor) }
    }

    /// A one-line record of exactly what the Export would apply — the honest summary of the
    /// three level facts (preset, correction, Gain) at the moment you press Export.
    private var exportSummary: String {
        var parts = ["\(editor.settings.preset.title)"]
        if editor.settings.normalizeLoudness, case .ready(let c) = editor.loudness.state {
            parts.append(c.outcome == .undefined ? "no loudness correction (range too quiet)"
                                                  : "loudness \(c.figure)")
        } else {
            parts.append("loudness off")
        }
        if abs(recording.gain) > 0.05 { parts.append(String(format: "gain %+.1f dB", recording.gain)) }
        return "PROTOTYPE — would export “\(recording.name)” as " + parts.joined(separator: ", ")
    }
}

// MARK: - Level controls: the two treatments

extension Recording {
    func estimateText(_ preset: QualityPreset) -> String {
        preset.estimateText(seconds: trimmedDuration, sampleRate: sampleRate)
    }
}

struct LevelControls: View {
    var editor: Editor
    var recording: Recording

    var body: some View {
        switch editor.settings.treatment {
        case .official: OfficialLevel(editor: editor, recording: recording)
        case .meter:    MeterLevel(editor: editor, recording: recording)
        }
    }
}

// MARK: Treatment A — stock components only

struct OfficialLevel: View {
    var editor: Editor
    var recording: Recording

    var body: some View {
        Toggle("Normalize loudness", isOn: Bindable(editor.settings).normalizeLoudness)

        if editor.settings.normalizeLoudness {
            correctionReadout
        }

        GainRow(recording: recording, editor: editor)
    }

    /// The applied correction, resolving after a brief measure. A full hit is just the number;
    /// a short fall adds one plain caption naming why (ADR-0013).
    @ViewBuilder private var correctionReadout: some View {
        switch editor.loudness.state {
        case .off:
            EmptyView()
        case .measuring:
            LabeledContent("Loudness") {
                Text("Measuring…").foregroundStyle(.secondary)
            }
        case .ready(let c) where c.outcome == .undefined:
            VStack(alignment: .leading, spacing: 2) {
                LabeledContent("Loudness") { Text("No correction").foregroundStyle(.secondary) }
                Text("range too quiet to measure")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .ready(let c):
            VStack(alignment: .leading, spacing: 2) {
                LabeledContent("Loudness") {
                    Text(c.figure).monospacedDigit()
                        .foregroundStyle(c.isShort ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        .contentTransition(.numericText())
                }
                if let caption = c.caption {
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// The manual Gain — a stock slider with a zero detent, a numeric field, and a reset that
/// only appears when it is off zero. Gain is per-Recording (ADR-0013), so this binds to the
/// Recording, and re-auditions on every change.
struct GainRow: View {
    var recording: Recording
    var editor: Editor

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Gain")
                Spacer()
                Text(String(format: "%+.1f dB", recording.gain))
                    .monospacedDigit().foregroundStyle(.secondary)
                if abs(recording.gain) > 0.05 {
                    Button("Reset") { recording.gain = 0; editor.loudness.refresh(editor) }
                        .buttonStyle(.link).font(.caption)
                }
            }
            Slider(value: Binding(
                get: { recording.gain },
                set: { v in
                    // A soft detent at 0 — the resting point Gain returns to.
                    recording.gain = abs(v) < 0.4 ? 0 : v
                    editor.loudness.refresh(editor)
                }), in: -12...12)
        }
    }
}

// MARK: Treatment B — a custom-drawn level meter

struct MeterLevel: View {
    var editor: Editor
    var recording: Recording

    var body: some View {
        Toggle("Normalize loudness", isOn: Bindable(editor.settings).normalizeLoudness)

        LevelMeter(editor: editor, recording: recording)
            .frame(height: 62)
            .padding(.vertical, 2)

        // The numbers still live in text underneath — the picture is a second channel, not the
        // only one. Two figures, per ADR-0013.
        HStack {
            figure("Loudness", loudnessText)
            Spacer()
            figure("Gain", String(format: "%+.1f dB", recording.gain))
            if abs(recording.gain) > 0.05 {
                Button("Reset") { recording.gain = 0; editor.loudness.refresh(editor) }
                    .buttonStyle(.link).font(.caption)
            }
        }
        if let caption = shortCaption {
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func figure(_ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }

    private var loudnessText: String {
        guard editor.settings.normalizeLoudness else { return "off" }
        switch editor.loudness.state {
        case .measuring: return "…"
        case .ready(let c): return c.outcome == .undefined ? "—" : c.figure
        case .off: return "off"
        }
    }
    private var shortCaption: String? {
        guard editor.settings.normalizeLoudness, case .ready(let c) = editor.loudness.state else { return nil }
        return c.caption
    }
}

/// The custom control: a horizontal LUFS scale from −40 to 0. It draws where the Recording
/// sits, where −16 is, how far the correction pushes it, where it lands short, and Gain as a
/// draggable offset on top. This is the "does #25 need custom drawing" question made concrete
/// — if A reads as well, none of this has to be built.
struct LevelMeter: View {
    var editor: Editor
    var recording: Recording

    private let lo = -40.0, hi = 0.0
    private let target = -16.0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x: (Double) -> Double = { (min(max($0, lo), hi) - lo) / (hi - lo) * w }

            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 6)

                // The target, −16.
                marker(at: x(target), label: "−16", strong: true)

                content(x: x, width: w)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(gainDrag(width: w))
        }
    }

    @ViewBuilder private func content(x: (Double) -> Double, width w: Double) -> some View {
        if !editor.settings.normalizeLoudness {
            // Off: just the Gain offset around 0-relative isn't meaningful on a loudness scale,
            // so show a calm "off" state — the meter is a normalization instrument.
            Text("Normalization off").font(.caption).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            switch editor.loudness.state {
            case .measuring, .off:
                Text("Measuring…").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            case .ready(let c) where c.outcome == .undefined:
                Text("range too quiet to measure").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            case .ready(let c):
                let measured = c.integratedLUFS ?? target
                let corrected = measured + c.gainDB
                let net = corrected + recording.gain

                // The correction: a filled bar from where it sits to where it lands.
                let a = x(min(measured, corrected)), b = x(max(measured, corrected))
                Capsule().fill(.tint).frame(width: max(2, b - a), height: 6).offset(x: a)

                // Landing short of the target: the gap is drawn, so "short" is visible.
                if c.isShort {
                    let g0 = x(min(corrected, target)), g1 = x(max(corrected, target))
                    Rectangle()
                        .fill(.tint.opacity(0.18))
                        .frame(width: max(1, g1 - g0), height: 6).offset(x: g0)
                }

                // Where the corrected loudness sits.
                dot(at: x(corrected), style: AnyShapeStyle(.tint))

                // Gain rides on top, as its own offset (ADR-0013). A draggable handle.
                if abs(recording.gain) > 0.05 {
                    let ga = x(min(corrected, net)), gb = x(max(corrected, net))
                    Capsule().fill(.orange).frame(width: max(2, gb - ga), height: 6).offset(x: ga)
                }
                dot(at: x(net), style: AnyShapeStyle(.orange), ring: true)
                    .help("Drag to set Gain")
            }
        }
    }

    private func marker(at x: Double, label: String, strong: Bool) -> some View {
        VStack(spacing: 1) {
            Rectangle().fill(strong ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(width: 1.5, height: 16)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .offset(x: x - 8, y: 10)
    }

    private func dot(at x: Double, style: AnyShapeStyle, ring: Bool = false) -> some View {
        Circle().fill(style)
            .frame(width: ring ? 13 : 10, height: ring ? 13 : 10)
            .overlay { if ring { Circle().strokeBorder(.background, lineWidth: 2) } }
            .offset(x: x - (ring ? 6.5 : 5))
    }

    /// Dragging anywhere sets Gain so the net loudness (corrected + Gain) follows the cursor —
    /// the custom control the stock slider replaces in treatment A.
    private func gainDrag(width w: Double) -> some Gesture {
        DragGesture(minimumDistance: 1).onChanged { value in
            guard editor.settings.normalizeLoudness, case .ready(let c) = editor.loudness.state,
                  c.outcome != .undefined, let measured = c.integratedLUFS else { return }
            let corrected = measured + c.gainDB
            let lufsAtCursor = lo + Double(value.location.x / w) * (hi - lo)
            let g = (lufsAtCursor - corrected).clamped(to: -12...12)
            recording.gain = abs(g) < 0.4 ? 0 : g
            editor.loudness.refresh(editor)
        }
    }
}
