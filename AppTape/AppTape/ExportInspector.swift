//
//  ExportInspector.swift
//  AppTape
//

import AppKit
import SwiftUI

/// The trailing Export inspector, **permanently visible** so the window has exactly one pane
/// control (issue #7). It shows the Trim's length, the four Quality Presets with their non-editable
/// parameters, the live `≈ MB` size estimate, and the Export control — which *is* the running
/// progress bar while an Export runs, in place, so a two-second job never seizes a sheet (ADR-0012).
struct ExportInspector: View {
    var recording: Recording

    @State private var preference = ExportPreference.shared
    @State private var coordinator = ExportCoordinator.shared
    @State private var recorder = RecordingController.shared
    @State private var editor = EditorModel.shared

    private var format: SourceFormat { recording.sourceFormat }

    /// **One height for all four Export phases**, so the dock cannot move as an Export runs.
    ///
    /// This is the half of the Export control #78 owned: its *position* was settled by issue #76,
    /// but idle, running, succeeded and failed each laid out to their own intrinsic height, so the
    /// pane's bottom content jumped twice during a two-second job — once when progress appeared and
    /// again when it resolved. Sized to the tallest phase (a two-line failure), which every other
    /// phase then centres inside rather than resizing the dock to fit.
    private static let exportControlHeight: Double = 34

    /// The sticky Quality Preset can't always encode an adopted file (ADR-0015). When it can't, the
    /// user's pick is a **display-over for this file only** — held here, never written to the
    /// app-wide sticky preference — and reset when the selection changes. Nil means "use the sticky".
    @State private var perFilePreset: QualityPreset?

    /// The preset actually shown selected and exported: the per-file display-over if one was chosen,
    /// otherwise the sticky preference.
    private var effectivePreset: QualityPreset { perFilePreset ?? preference.preset }

    /// Whether the effective preset can encode this file faithfully. Unavailable blocks Export and
    /// shows a plain reason in place of the subtitle (ADR-0015).
    private var effectiveEncodability: QualityPreset.Encodability { effectivePreset.encodability(for: format) }

    /// Choosing a rung. Picking one the sticky preset can encode updates the app-wide preference
    /// (issue #9); picking one it can't — an adopted file the sticky doesn't fit — is a per-file
    /// display-over that leaves the sticky untouched (ADR-0015). A rung the codec can't encode is
    /// never accepted here.
    ///
    /// A method rather than the `Binding` a `Picker` needed: the rungs are buttons now, and each one
    /// knows which preset it is, so there is nothing for a binding's getter to resolve.
    private func pick(_ newValue: QualityPreset) {
        switch QualityPreset.PresetPick.resolve(picking: newValue, sticky: preference.preset,
                                                format: format) {
        case .setSticky(let preset): preference.preset = preset; perFilePreset = nil
        case .displayOver(let preset): perFilePreset = preset
        case .ignore: break
        }
    }

    /// Re-measure whenever the Recording, its Trim, or the toggle changes (ADR-0013). The model
    /// dedupes an unchanged key, so binding this to observed state is cheap.
    private var correctionKey: String {
        "\(recording.url.path)|\(recording.trim.lowerBound)|\(recording.trim.upperBound)|\(preference.normalizeLoudness)"
    }

    /// The one dB scalar playback applies (Play == Export, ADR-0013): the correction when normalizing
    /// and resolved, plus this Recording's manual Gain. Zero correction while off or still measuring.
    private var playbackGainDB: Double {
        (preference.normalizeLoudness ? editor.correction.correctionDB : 0) + recording.gain
    }

    /// Soft detent at 0 (issue #55): a Gain within ±0.5 dB of centre snaps to exactly 0, so the
    /// slider has a home the user can feel and land on.
    private var gainBinding: Binding<Double> {
        Binding(get: { recording.gain },
                set: { recording.gain = abs($0) < 0.5 ? 0 : $0 })
    }

    var body: some View {
        Form {
            // **No `Selection` section.** It stated the Trim's length and range forty points from a
            // transport that already states them, in a different colour — the window disagreeing
            // with itself, and the last of the two-colour Trim readouts #77 started closing. What
            // the inspector says is what Export will *produce*; what is currently selected is the
            // detail pane's job (ADR-0025). The trimmed duration has not gone quiet — it is the
            // input to every size estimate below, and each rung prints its own.
            Section("Quality") {
                // All four rungs and all four estimates on screen at once, so the choice is
                // *compared* rather than revealed one at a time by a menu. This is also the only
                // shape in which ADR-0019's "the selected rung gains a leading checkmark, always"
                // means anything: inside a `Picker` the checkmark lives in a menu nobody sees.
                ForEach(QualityPreset.allCases) { preset in
                    rung(preset)
                }
                sourceFormatLine
            }

            // Loudness and Gain sit below the rungs (issue #55): they never move an estimate
            // (ADR-0012), so they read after the thing they do not affect.
            Section("Level") {
                loudnessAndGainControls
            }
        }
        .formStyle(.grouped)
        // The trailing column now paints its own `.controlBackgroundColor` to separate itself from
        // the detail pane (research report 0006), so the `Form` must not paint the window background
        // it assumes it is sitting on back over it.
        .scrollContentBackground(.hidden)
        // The Export control is **pinned to the pane's bottom edge**, not scrolled with the Form.
        // Inside the Form its position depended on how many rows happened to be above it — a
        // non-zero Gain, the Normalize correction row, an unencodable preset's reason block each
        // pushed it ~37 pt lower — and the running and succeeded phases are taller still. At the
        // declared default window size only the idle `Export…` button fit: `Exporting… 9%`,
        // `Cancel`, `Reveal in Finder` and `Done` were all bisected by the window's bottom edge, so
        // a user who exported at the default size could not see progress, cancel, or reveal the
        // file they had just made (issue #73, findings 3 and 22). Pinning it also stops the Form
        // needing to scroll for the ordinary case, which takes the overlay scroller — and its 8 pt
        // overlap of the group's trailing edge — with it (finding 4). Its *treatment* across the
        // four phases is [#78](https://github.com/SamWongML/macos-audio-recording/issues/78)'s;
        // this is only about the primary action being on screen at all.
        .safeAreaInset(edge: .bottom) {
            exportControl
                .frame(height: Self.exportControlHeight)
                .padding(.horizontal, Metrics.lg)
                .padding(.vertical, Metrics.md)
                .frame(maxWidth: .infinity)
                // No fill and no rule. The `.bar` here was separating the dock from a `Form` that
                // painted the window background; now that the column carries its own, a darkening
                // bar over it is the decorative chrome ADR-0019 spends its budget avoiding. The
                // dock separates by air and by alignment (ADR-0025).
        }
        // Through the token set's helper, not `.animation` directly, so Reduce Motion degrades
        // to a fade rather than an instant cut (ADR-0019).
        .motion(value: recording.trimmedDuration)
        .motion(value: coordinator.phase)
        .motion(value: preference.normalizeLoudness)
        .motion(value: editor.correction.state)
        // A new selection drops any per-file display-over, so the sticky preset shows through again
        // on the next Recording (ADR-0015).
        .onChange(of: recording.url) { perFilePreset = nil }
        .onChange(of: correctionKey, initial: true) {
            editor.correction.update(recording: recording, normalize: preference.normalizeLoudness)
        }
        .onChange(of: playbackGainDB, initial: true) {
            editor.player.setGlobalGainDB(playbackGainDB)
        }
    }

    /// One Quality Preset rung: checkmark, name, codec, and its **own** size estimate.
    ///
    /// A rung the source's format can't encode faithfully is disabled and dimmed, and states its
    /// plain reason where its codec would be — so every unusable rung says why, not just the
    /// effective one (ADR-0015). With all four reasons on screen, the disabled Export button below
    /// reads as "pick a rung that fits" without a separate sentence saying so.
    private func rung(_ preset: QualityPreset) -> some View {
        let encodability = preset.encodability(for: format)
        let isSelected = preset == effectivePreset
        return Button {
            pick(preset)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.sm) {
                // Always drawn, never conditional: the accessible path and the default path are the
                // same path, which is the only version that stays correct (ADR-0019).
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 12)

                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.displayName)
                        .foregroundStyle(.primary)
                    // The **codec and bitrate only**, not the whole `subtitle(for:)`. The rate and
                    // channel count in that string come from the *source*, so all four rungs would
                    // print the same "· 48 kHz stereo" — four copies of one fact, and the thing that
                    // wrapped every rung onto two lines in a 276 pt pane. Stated once beneath the
                    // rungs instead. Issue #9's "codec, bitrate, rate and channels, visible and
                    // never editable" still holds; it is simply said once rather than four times.
                    Text(encodability.reason ?? preset.codecLabel)
                        .font(.caption)
                        .foregroundStyle(encodability.isAvailable ? AnyShapeStyle(.secondary)
                                                                  : AnyShapeStyle(Color.orange))
                        .lineLimit(2)
                }

                Spacer(minLength: Metrics.xs)

                Text(ExportSizeEstimate.text(preset: preset, format: format,
                                             duration: recording.trimmedDuration))
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!encodability.isAvailable)
        .opacity(encodability.isAvailable ? 1 : 0.5)
        .help(encodability.reason ?? "")
        // Not `readAloud`: this is a button, and collapsing it to a label/value pair the way an
        // inspector *row* wants would cost the button trait. The rung keeps its trait, states the
        // preset as its label, folds codec and estimate into one value so they read as one sentence
        // rather than three loose texts, and carries `.isSelected` — which is the checkmark's
        // meaning, spoken.
        .accessibilityLabel(preset.displayName)
        .accessibilityValue([encodability.reason ?? preset.codecLabel,
                             ExportSizeEstimate.text(preset: preset, format: format,
                                                     duration: recording.trimmedDuration)]
                                .joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// The rate and channel count Export carries through untouched, said **once**: they are the
    /// source's, identical on every rung, and issue #9 asks for them to be visible, not repeated.
    private var sourceFormatLine: some View {
        Text(effectivePreset.subtitle(for: format)
            .replacingOccurrences(of: "\(effectivePreset.codecLabel) · ", with: "")
            + " · carried through unchanged")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    // MARK: - Loudness & Gain (normalize toggle, correction read-out, Gain slider)

    @ViewBuilder
    private var loudnessAndGainControls: some View {
        Toggle("Normalize loudness", isOn: $preference.normalizeLoudness)

        if preference.normalizeLoudness {
            LabeledContent("Correction") { correctionReadout }
                .readAloud("Correction", correctionSpokenValue)
        }

        LabeledContent("Gain") {
            Text(LoudnessCorrection.signedDecibels(recording.gain)).monospacedDigit()
        }
        .readAloud("Gain", LoudnessCorrection.signedDecibels(recording.gain))
        // The slider's own label is hidden, not removed: the `LabeledContent` row directly above
        // already names this control, and printing both made the inspector read
        // "Gain … 0.0 dB / Gain −12 ▬ +12" (issue #73, finding 12). `.labelsHidden()` keeps the
        // label for VoiceOver, which still needs to be told what the slider adjusts.
        Slider(value: gainBinding, in: -12...12) {
            Text("Gain")
        } minimumValueLabel: {
            Text("−12").font(.caption2).foregroundStyle(.secondary)
        } maximumValueLabel: {
            Text("+12").font(.caption2).foregroundStyle(.secondary)
        } onEditingChanged: { editing in
            // Persist once at drag-end, never per frame — like Trim (ADR-0006).
            if !editing { recording.persistGain() }
        }
        .labelsHidden()
        .accessibilityLabel("Gain")
        .accessibilityValue(LoudnessCorrection.signedDecibels(recording.gain))
        if recording.gain != 0 {
            Button("Reset Gain") {
                recording.gain = 0
                recording.persistGain()
            }
            .buttonStyle(.link)
        }
    }

    /// The Correction row in words. The rendered readout is a `VStack` of a figure and an optional
    /// caption, which accessibility would otherwise publish as two loose `AXStaticText`s beside the
    /// label instead of one row that reads as a sentence.
    private var correctionSpokenValue: String {
        switch editor.correction.state {
        case .off, .measuring: "Measuring"
        case .measured(let correction):
            [correction.figureText, correction.caption].compactMap { $0 }.joined(separator: ", ")
        }
    }

    /// The correction figure, as dB and **never LUFS** (ADR-0013): `Measuring…` until the BS.1770
    /// pass resolves, then the number, with the one land-short caption beneath it when it fell short.
    @ViewBuilder
    private var correctionReadout: some View {
        switch editor.correction.state {
        case .off, .measuring:
            Text("Measuring…").foregroundStyle(.secondary)
        case .measured(let correction):
            VStack(alignment: .trailing, spacing: 2) {
                Text(correction.figureText)
                    .monospacedDigit()
                    .foregroundStyle(correction.landing == .undefined ? AnyShapeStyle(.secondary)
                                                                        : AnyShapeStyle(.primary))
                if let caption = correction.caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    // MARK: - The Export control (button ⇄ progress ⇄ result)

    @ViewBuilder
    private var exportControl: some View {
        if recorder.isCapturing(recording) {
            // Its `.caf` is still growing and its Trim end is undefined until Stop (ADR-0012).
            Label("This Recording is still capturing.", systemImage: "record.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if coordinator.subjectURL == recording.url {
            switch coordinator.phase {
            case .idle: exportButton
            case .running(let fraction): runningControl(fraction)
            case .succeeded(let url): succeededControl(url)
            case .failed(let message): failedControl(message)
            }
        } else {
            exportButton
        }
    }

    private var exportButton: some View {
        // The width is asked for on the **label**, not on the `Button`. `.frame(maxWidth: .infinity)`
        // on a `Button` widens the layout slot and leaves the control hugging its title inside it,
        // which is why the old `Export…` centred itself and the code's intent and the render
        // disagreed (issue #73, finding 37). Widening the label widens the button.
        Button {
            coordinator.export(recording: recording, preset: effectivePreset)
        } label: {
            Text("Export…").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        // Blocked while the effective preset can't encode this file, until a working rung is chosen
        // (ADR-0015).
        .disabled(recording.trimmedDuration <= 0 || coordinator.isExporting
                  || !effectiveEncodability.isAvailable)
    }

    private func runningControl(_ fraction: Double) -> some View {
        VStack(spacing: Metrics.xs) {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
            HStack {
                Text("Exporting… \(Int((fraction * 100).rounded()))%")
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { coordinator.cancel() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }

    /// One row rather than a stack: `Reveal in Finder` shortens to `Reveal` beside the word
    /// `Exported`, which is unambiguous next to a green check and is what lets the succeeded phase
    /// occupy the same height as the idle button.
    private func succeededControl(_ url: URL) -> some View {
        HStack(spacing: Metrics.sm) {
            Label("Exported", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
                .labelStyle(.titleAndIcon)
            Spacer(minLength: Metrics.xs)
            Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                .buttonStyle(.link).font(.caption)
            Button("Done") { coordinator.cancel() }
                .buttonStyle(.link).font(.caption)
        }
    }

    /// The tallest phase, and so the one that sets `exportControlHeight`: two lines of reason beside
    /// a retry. `Try Again…` steps down from prominent to plain — a failure the user has just read
    /// is not the moment for the loudest control in the pane, and the prominent button here made
    /// the failed phase taller than every other.
    private func failedControl(_ message: String) -> some View {
        HStack(spacing: Metrics.sm) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(2)
            Spacer(minLength: Metrics.xs)
            Button("Try Again…") {
                coordinator.cancel()   // clear the failure, then re-present the save panel
                coordinator.export(recording: recording, preset: effectivePreset)
            }
            .font(.caption)
        }
        .help(message)
    }
}

private extension View {
    /// One accessibility element per inspector row, carrying **both** the label and the number.
    ///
    /// `LabeledContent` around a styled `Text` published the figure twice — outer and inner — and
    /// the outer copy lagged a selection behind, so VoiceOver read the *previous* Recording's
    /// numbers while the pixels were correct (issue #73, finding 13). `.accessibilityElement(children:
    /// .combine)` collapses the pair but drops the value with it: measured in the running app, the
    /// row was left with an `AXDescription` of `Length` and **no `AXValueDescription` at all**, which
    /// trades a stale number for no number. Stating both explicitly is the only form that survives.
    func readAloud(_ label: LocalizedStringKey, _ value: String) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value)
    }
}
