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

    /// Whether this Recording's audio is still arriving, so nothing may be claimed about its
    /// length (ADR-0021, ADR-0031). The lane, the transport and the sidebar row ask the same.
    private var isStillArriving: Bool { recorder.isStillArriving(recording) }

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
    /// `isStillArriving` is part of the key, not just a guard on the readout: the measurement is
    /// *skipped* while the audio arrives (ADR-0031 — the Trim bounds it would measure are undefined),
    /// so Stop has to be a key change or the figure would never arrive at all.
    private var correctionKey: String {
        "\(recording.url.path)|\(recording.trim.lowerBound)|\(recording.trim.upperBound)|\(preference.normalizeLoudness)|\(isStillArriving)"
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
        //
        // **`safeAreaBar`, not `safeAreaInset`, and that one word is the whole fix for #114**
        // (ADR-0036). The two lay out identically; only `safeAreaBar` *extends the scroll edge
        // effect* of the scroll view it insets. Under `safeAreaInset` the column's content drew
        // straight through the dock at the 960 × 552 floor — the Gain slider's track and thumb
        // below the `Export…` button, the failed phase's sentence over the slider's thumb — and
        // the comment below was written in a release where the modifier that fixes it did not
        // exist yet.
        .safeAreaBar(edge: .bottom) {
            exportControl
                // Idle ⇄ running ⇄ succeeded is the state change the user most needs to notice and
                // least directly causes — the encode finishing is the app's news, not theirs. The
                // four phases already share one declared height (ADR-0025), so this cross-fades
                // content inside a fixed frame rather than resizing the dock.
                .motion(Metrics.motionState, value: coordinator.phase)
                .frame(height: Self.exportControlHeight)
                .padding(.horizontal, Metrics.lg)
                .padding(.vertical, Metrics.md)
                .frame(maxWidth: .infinity)
                // **No fill of ours, and the bar brings one of its own** (#120, ADR-0038,
                // amending ADR-0025's "no fill and no rule" for this one control). The `Material.bar` that
                // used to be written here is gone and stays gone. What replaced it is
                // `safeAreaBar`'s own background: **27 → 35 in Dark, 242 → 250 in Light, with a
                // 0.5 pt hairline at 43 and 218**, over the bottom 58.5 pt of the column —
                // measured at 960 × 900, where the column has 200 pt of slack, draws no scroller,
                // and has nothing passing beneath it at all. `safeAreaInset` at that same size
                // paints neither.
                //
                // **That band is what does the work**, so it is kept rather than fought. A/B on
                // identical pixels at 960 × 460: under `safeAreaInset` the `Normalize loudness`
                // row draws over the `Export…` button at full strength (issue #114); under
                // `safeAreaBar` it keeps **13% of its contrast** — which is what Apple Music's
                // sidebar dock does to the playlist row travelling under it, measured at 14%.
                //
                // **Nothing is set here on purpose, and there is nothing to set.**
                // `.scrollEdgeEffectStyle` with `.automatic`, `.soft` or `nil`, and
                // `.scrollEdgeEffectHidden(true, for: .bottom)`, are all pixel-identical to
                // writing nothing. `.hard` is the only value that changes anything: it *erases*
                // content passing beneath instead of dimming it. ADR-0036 read the band above as
                // `.hard`'s and `.automatic` as conditional; both styles paint it, to within
                // 4/255, wherever nothing is passing under the dock.
        }
        // **No `.motion` here.** Four of them used to sit on this `Form`, and that is why the
        // trailing column travelled in from the top-left of the detail pane and took seconds to
        // arrive (issue #88). `.animation(_:value:)` animates its subtree's own resolved geometry,
        // and this column's x-position is not stated anywhere — it is whatever the detail pane's
        // `maxWidth: .infinity` leaves over — so an animation scope here means "animate where this
        // pane is", and two of the four values changed while the window was still laying out. Each
        // now sits on the smallest view that contains its change: the size estimate, the correction
        // readout, the Export control (ADR-0028).
        //
        // `preference.normalizeLoudness` is deliberately not among them. What it changes is the
        // *presence* of the Correction row, and an insertion can only be animated from the parent —
        // here the `Section`, whose height is derived exactly as this column's position was. The
        // toggle is already its own feedback; the row does not need to slide as well.
        // A new selection drops any per-file display-over, so the sticky preset shows through again
        // on the next Recording (ADR-0015).
        .onChange(of: recording.url) { perFilePreset = nil }
        .onChange(of: correctionKey, initial: true) {
            // Nothing to measure from a Trim whose end has not happened yet (ADR-0031).
            guard !isStillArriving else { return }
            editor.correction.update(recording: recording, normalize: preference.normalizeLoudness)
        }
        .onChange(of: playbackGainDB, initial: true) {
            editor.player.setGlobalGainDB(playbackGainDB)
        }
    }

    /// One Quality Preset rung: checkmark, name, codec, and its **own** size estimate — and, on a
    /// rung that cannot encode, the plain reason why, *below* the control rather than inside it.
    ///
    /// A rung the source's format can't encode faithfully is disabled and dimmed, and states its
    /// plain reason in place of its codec — so every unusable rung says why, not just the effective
    /// one (ADR-0015). With all four reasons on screen, the disabled Export button below reads as
    /// "pick a rung that fits" without a separate sentence saying so.
    ///
    /// **The reason is not part of the control, so it is not inside it** (ADR-0041). It used to be
    /// the second `Text` of the button's label, in `Color.orange`, on a row carrying both
    /// `.disabled(true)` and an explicit `.opacity(0.5)` — and it measured **1.58 : 1 in Dark and
    /// 1.22 : 1 in Light**, the worst figures this app has recorded, for the one sentence on the row
    /// that has to be read. Three multiplications stacked: an alarm colour that is unreadable as
    /// words in Light (ADR-0037), the explicit halving, and — the one that is invisible in the
    /// source — **`.disabled()`'s own dimming of its subtree's text**. Exempting the sentence from
    /// the explicit `.opacity` alone recovers only 4.03 / 3.01, because the system's half is still
    /// applied. Lifting it clear of the `Button` recovers **11.71 / 13.02**, which is where
    /// ADR-0037 put the dock's sentences.
    private func rung(_ preset: QualityPreset) -> some View {
        let encodability = preset.encodability(for: format)
        let isSelected = preset == effectivePreset
        return VStack(alignment: .leading, spacing: 1) {
        Button {
            pick(preset)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.sm) {
                // Always drawn, never conditional: the accessible path and the default path are the
                // same path, which is the only version that stays correct (ADR-0019).
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: Self.checkmarkSlotWidth)

                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.displayName)
                        .foregroundStyle(.primary)
                    // The **codec and bitrate only**, not the whole `subtitle(for:)`. The rate and
                    // channel count in that string come from the *source*, so all four rungs would
                    // print the same "· 48 kHz stereo" — four copies of one fact, and the thing that
                    // wrapped every rung onto two lines in a 276 pt pane. Stated once beneath the
                    // rungs instead. Issue #9's "codec, bitrate, rate and channels, visible and
                    // never editable" still holds; it is simply said once rather than four times.
                    // Only on a rung that *can* encode: the unencodable rung's second line is its
                    // reason, and that is drawn below, outside this button.
                    if encodability.isAvailable {
                        Text(preset.codecLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: Metrics.xs)

                // **No estimate while the audio is still arriving** (ADR-0031). The figure is
                // reckoned from `trimmedDuration`, which for a growing master is the last folder
                // listing's reading — and the folder is not re-listed while a file is appended to,
                // so every rung read `≈ 630 KB` beside a `Master` row already past 60 MB. The
                // dock below already says the Recording is still capturing and refuses the export
                // (ADR-0012); a confident size for an export that cannot happen is the inspector
                // disagreeing with itself two rows down.
                //
                // **And no estimate on a rung that cannot encode at all**, which is the same rule
                // reaching a second cause (ADR-0041). `≈ 457 KB` beside `AAC can't encode above
                // 48 kHz` is the inspector disagreeing with itself on one row rather than two, and
                // the figure is also what reserved the width that truncated the reason: every one
                // of the three reasons `ZZ Probe 96k` renders was cut short at `1200 × 680`, not
                // only at the 276 pt floor. Dropping it is what lets the sentence finish.
                if encodability.isAvailable {
                Text(isStillArriving ? "—"
                                     : ExportSizeEstimate.text(preset: preset, format: format,
                                                               duration: recording.trimmedDuration))
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
                    // The estimate re-reckons as the Trim moves: a figure that ticks, which is
                    // what `.numericText()` is for. `.interpolate` used to be applied here from
                    // the `Form` and did nothing at all — it interpolates symbol and shape states,
                    // never digits (ADR-0028).
                    .textTransition(.numericText())
                    .motion(Metrics.motionState, value: recording.trimmedDuration)
                }
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
                             isStillArriving ? "size not yet known"
                                             : ExportSizeEstimate.text(preset: preset, format: format,
                                                                       duration: recording.trimmedDuration)]
                                .joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            // The refusal, at full strength, outside everything that dims. Indented to the name's
            // own left edge — 12 pt of checkmark slot plus the `HStack`'s spacing — so it still
            // reads as this rung's second line and not as a note about the section.
            //
            // **No ⚠, deliberately.** ADR-0037's split hands the alarm to a mark and the meaning to
            // the words; here there is no mark to hand it to, and adding one costs width in a 276 pt
            // pane where this sentence was already truncating — measured: the glyph pushed `this
            // file is 96 kHz.` off the end. What separates a refusal from a codec label instead is
            // that the name above it is dimmed and the sentence is not, and that the rung states no
            // size. ADR-0037 asks for a *test* before a fourth mark, not a habit; this fails it.
            //
            // `.accessibilityHidden` because the button above already carries this string in its
            // `accessibilityValue`: the rung speaks once (ADR-0025), and a VoiceOver user should not
            // hear the reason twice for moving through one row.
            if let reason = encodability.reason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .padding(.leading, Self.checkmarkSlotWidth + Metrics.sm)
                    .accessibilityHidden(true)
            }
        }
    }

    /// The leading slot every rung reserves for its checkmark, shared by the mark and by the
    /// indent that keeps an unencodable rung's reason aligned under the preset's name.
    private static let checkmarkSlotWidth: CGFloat = 12

    /// The rate and channel count Export carries through untouched, said **once**: they are the
    /// source's, identical on every rung, and issue #9 asks for them to be visible, not repeated.
    ///
    /// **`.tertiary` is gone** (#114). It measured **2.27 : 1 in Dark and 1.86 : 1 in Light** —
    /// the twin of the loupe caption #104 deleted two hundred lines up this same file, and the
    /// last `.tertiary` left on text a user is meant to read. Unlike the loupe's this sits on an
    /// **opaque** scrim, so it was never a vibrancy blend (ADR-0032's first consequence); it was
    /// simply too faint. The size stays `.caption2`: 11 pt is the floor ADR-0019's type scale
    /// allows, and a bigger footnote would compete with the rungs it annotates.
    private var sourceFormatLine: some View {
        Text(effectivePreset.subtitle(for: format)
            .replacingOccurrences(of: "\(effectivePreset.codecLabel) · ", with: "")
            + " · carried through unchanged")
            .font(.caption2)
            .foregroundStyle(Color.primary.opacity(0.7))
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
        // Matches the rungs' `size not yet known` while the audio arrives: what the dash means,
        // spoken (ADR-0031).
        guard !isStillArriving else { return "not yet known" }
        return switch editor.correction.state {
        case .off, .measuring: "Measuring"
        case .measured(let correction):
            [correction.figureText, correction.caption].compactMap { $0 }.joined(separator: ", ")
        }
    }

    /// The correction figure, as dB and **never LUFS** (ADR-0013): `Measuring…` until the BS.1770
    /// pass resolves, then the number, with the one land-short caption beneath it when it fell short.
    @ViewBuilder
    private var correctionReadout: some View {
        correctionReadoutContent
            // `Measuring…` resolving into a figure is the one thing in this pane that arrives on
            // its own clock — a BS.1770 pass landing seconds later — so it is exactly ADR-0028's
            // "a state change they must notice and did not cause". Scoped to the readout, which is
            // the smallest view containing the change.
            .motion(Metrics.motionState, value: editor.correction.state)
    }

    @ViewBuilder
    private var correctionReadoutContent: some View {
        // **No verdict while the audio is still arriving** (ADR-0031), the same em dash the rungs'
        // size estimates draw for the same reason. Ungated, this row re-measured on a `correctionKey`
        // built from `recording.trim` — bounds that are undefined until Stop — landed on `.undefined`
        // and printed `No correction · range too quiet to measure` over audio that measured
        // −14.5 LUFS integrated with a −3.1 dBFS peak (issue #103, finding 5). That is worse than the
        // five stale surfaces #98 found: those went out of date, this one made a claim about the
        // audio the engine had no basis for.
        //
        // A dash rather than no row, because `No correction` was long enough that `LabeledContent`
        // dropped the value under its label, so the card was three rows tall during capture and two
        // after — and a row that vanishes at Stop moves the card just as much as one that reflows.
        if isStillArriving {
            Text(verbatim: "—").foregroundStyle(.secondary)
        } else {
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

    /// Blocked while the effective preset can't encode this file, until a working rung is chosen
    /// (ADR-0015), while the Trim holds nothing, and while an Export of this Recording runs.
    private var isBlocked: Bool {
        recording.trimmedDuration <= 0 || coordinator.isExporting
            || !effectiveEncodability.isAvailable
    }

    /// PROTOTYPE (#125). The shipped shape is `a`; the others are the measured ladder.
    @ViewBuilder
    private var exportButton: some View {
        switch ExportButtonVariant.current {
        case .a: baseButton(prominent: true)
        case .b: baseButton(prominent: !isBlocked)
        case .c: liftedLabelButton
        case .d:
            if isBlocked { blockedSentence(.secondary) } else { baseButton(prominent: true) }
        case .e:
            if isBlocked { blockedSentence(.primary) } else { baseButton(prominent: true) }
        }
    }

    // The width is asked for on the **label**, not on the `Button`. `.frame(maxWidth: .infinity)`
    // on a `Button` widens the layout slot and leaves the control hugging its title inside it,
    // which is why the old `Export…` centred itself and the code's intent and the render
    // disagreed (issue #73, finding 37). Widening the label widens the button.
    private var rawButton: some View {
        Button {
            coordinator.export(recording: recording, preset: effectivePreset)
        } label: {
            Text("Export…").frame(maxWidth: .infinity)
        }
        .disabled(isBlocked)
    }

    @ViewBuilder
    private func baseButton(prominent: Bool) -> some View {
        if prominent { rawButton.buttonStyle(.borderedProminent) }
        else { rawButton.buttonStyle(.bordered) }
    }

    /// `c` — the label drawn *outside* the disabled Button, so `.disabled()`'s text dimming never
    /// reaches it. The Button keeps its prominent fill and its own (empty) label.
    private var liftedLabelButton: some View {
        Button {
            coordinator.export(recording: recording, preset: effectivePreset)
        } label: {
            Text(" ").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isBlocked)
        .overlay { if isBlocked { Text("Export…").foregroundStyle(.white) } }
    }

    /// `d` — no control at all while blocked, in the idiom `exportControl` already uses for a
    /// Recording that is still capturing.
    private func blockedSentence(_ style: HierarchicalShapeStyle) -> some View {
        Label(ProcessInfo.processInfo.environment["APPTAPE_XTEXT"] ?? "Nothing to export yet.",
              systemImage: "square.and.arrow.up")
            .font(.callout)
            .foregroundStyle(style)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            // Split for the same reason as the failed phase below (ADR-0037): one
            // `.foregroundStyle(.green)` used to colour the checkmark *and* the word, and the word
            // measured **2.13 : 1 in Light**. The check keeps the colour, `Exported` takes ink.
            Label {
                Text("Exported")
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
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
    /// a retry. The retry steps down from prominent to plain — a failure the user has just read
    /// is not the moment for the loudest control in the pane, and the prominent button here made
    /// the failed phase taller than every other.
    ///
    /// **`Retry…`, not `Try Again…`, and the four characters are the fix.** This phase is the one
    /// whose text *is* the payload: the message names both figures, and at 276 pt the wider button
    /// left it about 22 characters a line, so `Not enough space to export (needs about 5.41 MB,
    /// 2.96 MB free).` rendered as `Not enough space to / export (needs about…` and lost both
    /// numbers — the whole point of the sentence (issue #103, finding 2). Shortening the sentence
    /// alone was measured and still lost the *free* figure. So the verb gives up its width to the
    /// numbers, which is the same trade #78 made one phase up, where `Reveal in Finder` became
    /// `Reveal` so the succeeded phase would fit the shared height. The ellipsis stays: retrying
    /// re-presents the save panel.
    private func failedControl(_ message: String) -> some View {
        HStack(spacing: Metrics.sm) {
            // **The warning's colour belongs to its mark, not to its sentence** (ADR-0037). One
            // `.foregroundStyle(.orange)` used to cover the glyph *and* the message, which put the
            // payload of this phase at **2.33 : 1 in Light** on the column's own scrim — and that
            // figure is measured at 1200 × 680 with nothing scrolled under the dock, so it was
            // never the scroll that made it unreadable. #104 verified this phase at that size and
            // checked that both figures fit the line; nobody measured whether they could be read.
            // The ⚠ keeps the alarm, the sentence takes ink.
            Label {
                Text(message)
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
                .font(.caption)
                .lineLimit(2)
            Spacer(minLength: Metrics.xs)
            Button("Retry…") {
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
