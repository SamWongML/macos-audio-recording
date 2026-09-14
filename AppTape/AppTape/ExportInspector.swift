import AppKit
import SwiftUI

/// The trailing Export inspector, **permanently visible** so the window has exactly one pane
/// control. It shows the Trim's length, the four Quality Presets with their non-editable
/// parameters, the live `≈ MB` size estimate, and the Export control — which *is* the running
/// progress bar while an Export runs, in place, so a two-second job never seizes a sheet.
struct ExportInspector: View {
    var recording: Recording
    /// What capture is doing. The dock asks it two questions: whether this Recording is
    /// the one being written — which is a refusal of its own — and whether its audio is
    /// still arriving, which is what nothing about the Trim's length may be claimed under.
    var capture: any CaptureState

    /// The sticky Quality Preset and the Loudness switch. `@Bindable` because the dock
    /// writes them: the Toggle binds `normalizeLoudness` and picking a rung assigns `preset`.
    @Bindable var preference: ExportPreference
    /// The running Export, one at a time and app-wide.
    var coordinator: ExportCoordinator
    /// The Loudness correction preview for this Trim. Owned by the editor's model so a
    /// resolved measurement outlives a redraw, and handed here rather than fetched off it.
    var correction: LoudnessCorrectionModel
    /// Playback, for the one thing this pane does to it: the combined preview gain.
    var player: AudioPlayer

    private var format: SourceFormat { recording.sourceFormat }

    /// **One height for all four Export phases**, so the dock cannot move as an Export runs.
    private static let exportControlHeight: Double = 34

    /// The sticky Quality Preset can't always encode an adopted file. When it can't, the
    /// user's pick is a **display-over for this file only** — held here, never written to the
    /// app-wide sticky preference — and reset when the selection changes. Nil means "use the sticky".
    @State private var perFilePreset: QualityPreset?

    /// Whether this Recording's audio is still arriving, so nothing may be claimed about its
    /// length. The lane, the transport and the sidebar row ask the same.
    private var isStillArriving: Bool { capture.isStillArriving(recording) }

    /// The preset actually shown selected and exported: the per-file display-over if one was chosen,
    /// otherwise the sticky preference.
    private var effectivePreset: QualityPreset { perFilePreset ?? preference.preset }

    /// Whether an Export may start, and if not, what the dock says. The decision itself is
    /// `ExportReadiness`'s — five ordered rules over six scalars, which the dock **renders** and
    /// `ExportCoordinator` **refuses on**, so the two cannot drift apart again. This pane used to
    /// hold its own copy, in seconds where the coordinator counted frames.
    private var readiness: ExportReadiness {
        .evaluate(isOpenable: recording.isOpenable,
                  isCapturing: capture.isCapturing(recording),
                  trimmedFrameCount: recording.trimmedFrameRange.count,
                  preset: effectivePreset, format: format,
                  isExporting: coordinator.isExporting)
    }

    /// Choosing a rung. Picking one the sticky preset can encode updates the app-wide preference
    ///; picking one it can't — an adopted file the sticky doesn't fit — is a per-file
    /// display-over that leaves the sticky untouched. A rung the codec can't encode is
    /// never accepted here.
    private func pick(_ newValue: QualityPreset) {
        switch QualityPreset.PresetPick.resolve(picking: newValue, sticky: preference.preset,
                                                format: format) {
        case .setSticky(let preset): preference.preset = preset; perFilePreset = nil
        case .displayOver(let preset): perFilePreset = preset
        case .ignore: break
        }
    }

    /// Re-measure whenever the Recording, its Trim, or the toggle changes. The model
    /// dedupes an unchanged key, so binding this to observed state is cheap.
    /// `isStillArriving` is part of the key, not just a guard on the readout: the measurement is
    /// *skipped* while the audio arrives (— the Trim bounds it would measure are undefined),
    /// so Stop has to be a key change or the figure would never arrive at all.
    private var correctionKey: String {
        "\(recording.url.path)|\(recording.trim.lowerBound)|\(recording.trim.upperBound)|\(preference.normalizeLoudness)|\(isStillArriving)"
    }

    /// The one dB scalar playback applies (Play == Export): the correction when normalizing
    /// and resolved, plus this Recording's manual Gain. Zero correction while off or still measuring.
    private var playbackGainDB: Double {
        (preference.normalizeLoudness ? correction.correctionDB : 0) + recording.gain
    }

    /// Soft detent at 0: a Gain within ±0.5 dB of centre snaps to exactly 0, so the
    /// slider has a home the user can feel and land on.
    private var gainBinding: Binding<Double> {
        Binding(get: { recording.gain },
                set: { recording.gain = abs($0) < 0.5 ? 0 : $0 })
    }

    var body: some View {
        Form {
            // **No `Selection` section.** It stated the Trim's length and range forty points from a
            // transport that already states them, in a different colour — the window disagreeing
            Section("Quality") {
                // All four rungs and all four estimates on screen at once, so the choice is
                // *compared* rather than revealed one at a time by a menu. This is also the only
                ForEach(QualityPreset.allCases) { preset in
                    presetRow(preset)
                }
                sourceFormatLine
            }

            // Loudness and Gain sit below the rungs: they never move an estimate
            //, so they read after the thing they do not affect.
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
        .safeAreaBar(edge: .bottom) {
            exportControl
                // Idle ⇄ running ⇄ succeeded is the state change the user most needs to notice and
                // least directly causes — the encode finishing is the app's news, not theirs. The
                .motion(Metrics.motionState, value: coordinator.phase)
                .frame(height: Self.exportControlHeight)
                .padding(.horizontal, Metrics.lg)
                .padding(.vertical, Metrics.md)
                .frame(maxWidth: .infinity)
        // **No fill of ours, and the bar brings one of its own** (#120,
        // amending 's "no fill and no rule" for this one control). The `Material.bar` that
        }
        // **No `.motion` here.** Four of them used to sit on this `Form`, and that is why the
        // trailing column travelled in from the top-left of the detail pane and took seconds to
        .onChange(of: ObjectIdentifier(recording)) { perFilePreset = nil }
        .onChange(of: correctionKey, initial: true) {
            // Nothing to measure from a Trim whose end has not happened yet.
            guard !isStillArriving else { return }
            correction.update(recording: recording, normalize: preference.normalizeLoudness)
        }
        .onChange(of: playbackGainDB, initial: true) {
            player.setGlobalGainDB(playbackGainDB)
        }
    }

    /// One Quality Preset rung: checkmark, name, codec, and its **own** size estimate — and, on a
    /// rung that cannot encode, the plain reason why, *below* the control rather than inside it.
    private func presetRow(_ preset: QualityPreset) -> some View {
        let encodability = preset.encodability(for: format)
        let isSelected = preset == effectivePreset
        return VStack(alignment: .leading, spacing: 1) {
        Button {
            pick(preset)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.sm) {
                // Always drawn, never conditional: the accessible path and the default path are the
                // same path, which is the only version that stays correct.
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: Self.checkmarkSlotWidth)

                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.displayName)
                        .foregroundStyle(.primary)
                    // The **codec and bitrate only**, not the whole `subtitle(for:)`. The rate and
                    // channel count in that string come from the *source*, so all four rungs would
                    if encodability.isAvailable {
                        Text(preset.codecLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: Metrics.xs)

                // **No estimate while the audio is still arriving**. The figure is
                // reckoned from `trimmedDuration`, which for a growing master is the last folder
                if encodability.isAvailable {
                Text(isStillArriving ? "—"
                                     : ExportSizeEstimate.text(preset: preset, format: format,
                                                               duration: recording.trimmedDuration))
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
                    // The estimate re-reckons as the Trim moves: a figure that ticks, which is
                    // what `.numericText` is for. `.interpolate` used to be applied here from
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
        .accessibilityLabel(preset.displayName)
        .accessibilityValue([encodability.reason ?? preset.codecLabel,
                             isStillArriving ? "size not yet known"
                                             : ExportSizeEstimate.text(preset: preset, format: format,
                                                                       duration: recording.trimmedDuration)]
                                .joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            // The refusal, at full strength, outside everything that dims. Indented to the name's
            // own left edge — 12 pt of checkmark slot plus the `HStack`'s spacing — so it still
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
    /// source's, identical on every rung, and asks for them to be visible, not repeated.
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
                .accessibilityLabeledValue("Correction", correctionSpokenValue)
        }

        LabeledContent("Gain") {
            Text(LoudnessCorrection.signedDecibels(recording.gain)).monospacedDigit()
        }
        .accessibilityLabeledValue("Gain", LoudnessCorrection.signedDecibels(recording.gain))
        // The slider's own label is hidden, not removed: the `LabeledContent` row directly above
        // already names this control, and printing both made the inspector read
        Slider(value: gainBinding, in: -12...12) {
            Text("Gain")
        } minimumValueLabel: {
            Text("−12").font(.caption2).foregroundStyle(.secondary)
        } maximumValueLabel: {
            Text("+12").font(.caption2).foregroundStyle(.secondary)
        } onEditingChanged: { editing in
            // Persist once at drag-end, never per frame — like Trim.
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
        // spoken.
        guard !isStillArriving else { return "not yet known" }
        return switch correction.state {
        case .off, .measuring: "Measuring"
        case .measured(let correction):
            [correction.figureText, correction.caption].compactMap { $0 }.joined(separator: ", ")
        }
    }

    /// The correction figure, as dB and **never LUFS**: `Measuring…` until the BS.1770
    /// pass resolves, then the number, with the one land-short caption beneath it when it fell short.
    @ViewBuilder
    private var correctionReadout: some View {
        correctionReadoutContent
            // `Measuring…` resolving into a figure is the one thing in this pane that arrives on
            // its own clock — a BS.1770 pass landing seconds later — so it is exactly 's
            .motion(Metrics.motionState, value: correction.state)
    }

    @ViewBuilder
    private var correctionReadoutContent: some View {
        // **No verdict while the audio is still arriving**, the same em dash the rungs'
        // size estimates draw for the same reason. Ungated, this row re-measured on a `correctionKey`
        if isStillArriving {
            Text(verbatim: "—").foregroundStyle(.secondary)
        } else {
            switch correction.state {
            case .off, .measuring:
                Text("Measuring…").foregroundStyle(.secondary)
            case .measured(let correction):
                VStack(alignment: .trailing, spacing: 2) {
                    Text(correction.figureText)
                        .monospacedDigit()
                        .foregroundStyle(correction.gainResult == .undefined ? AnyShapeStyle(.secondary)
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
        if case .refused(.stillCapturing) = readiness {
            // Its `.caf` is still growing and its Trim end is undefined until Stop.
            // In ink, like every other sentence in this slot: `.secondary` here measured
            dockSentence(.stillCapturing)
        } else if coordinator.subjectURL == recording.url {
            switch coordinator.phase {
            case .idle: exportControlOrBlocker
            case .running(let fraction): runningControl(fraction)
            case .succeeded(let url): succeededControl(url)
            case .failed(let message): failedControl(message)
            }
        } else {
            exportControlOrBlocker
        }
    }

    /// **The dock states a refusal; it does not wear one**. A disabled
    /// `.borderedProminent` button is dimmed twice — the control at α ≈ 0.69 over the column's
    /// ground and its label at a further α = 0.50 over that — which put `Export…` at
    /// **1.75: 1 in Light** and under 3: 1 in all four measured cells. So there is no disabled
    /// button: when an Export cannot start, the button is replaced by the sentence that says why,
    /// which measures **12.66 / 13.87** and does not move when the window loses key.
    @ViewBuilder
    private var exportControlOrBlocker: some View {
        if let reason = readiness.blocker { dockSentence(reason) }
        else { exportButton }
    }

    /// The dock's one sentence shape, for every refusal there is. Holds the button's own box, so the
    /// dock keeps the single declared height pinned and nothing above it moves.
    private func dockSentence(_ reason: ExportReadiness.Reason) -> some View {
        Label(reason.sentence, systemImage: reason.symbolName)
            .font(.callout)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var exportButton: some View {
        // The width is asked for on the **label**, not on the `Button`. `.frame(maxWidth:.infinity)`
        // on a `Button` widens the layout slot and leaves the control hugging its title inside it,
        Button {
            coordinator.export(recording: recording, preset: effectivePreset, capture: capture)
        } label: {
            Text("Export…").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
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
            // Split for the same reason as the failed phase below: one
            // `.foregroundStyle(.green)` used to colour the checkmark *and* the word, and the word
            // measured **2.13: 1 in Light**. The check keeps the colour, `Exported` takes ink.
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
    private func failedControl(_ message: String) -> some View {
        HStack(spacing: Metrics.sm) {
            // **The warning's colour belongs to its mark, not to its sentence**. One
            // `.foregroundStyle(.orange)` used to cover the glyph *and* the message, which put the
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
                coordinator.export(recording: recording, preset: effectivePreset, capture: capture)
            }
            .font(.caption)
        }
        .help(message)
    }
}

private extension View {
    /// One accessibility element per inspector row, carrying **both** the label and the number.
    func accessibilityLabeledValue(_ label: LocalizedStringKey, _ value: String) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value)
    }
}

// MARK: - Previews

// `#if DEBUG`, as `PreviewFixtures.swift` is: a preview body is compiled in Release too.
#if DEBUG

/// The dock's states, and the reason the pane accepts its four collaborators rather than reaching for
/// them. The three Export phases below need a coordinator parked in one, which the running
/// app reaches only by starting a real Export through the save panel — so 's claim that all
/// four phases render at **one height** is checkable here for the first time. Read them together:
/// nothing in the column may move as the phase changes.

/// A pane over a Recording that does not exist, with its own defaults suite so a preview can never
/// write the user's sticky Quality Preset.
@MainActor
private func previewDock(_ recording: Recording,
                         capture: any CaptureState,
                         coordinator: ExportCoordinator) -> some View {
    ExportInspector(recording: recording,
                    capture: capture,
                    preference: ExportPreference(defaults: UserDefaults(suiteName: "com.apptape.previews")
                        ?? .standard),
                    coordinator: coordinator,
                    correction: LoudnessCorrectionModel(),
                    player: AudioPlayer())
        .frame(width: 276)
        .background(Color(nsColor: .controlBackgroundColor))
}

#Preview("Dock · ready") {
    previewDock(.stub(), capture: PreviewCapture.settled, coordinator: ExportCoordinator())
}

/// The Recording being written right now: its `.caf` is still growing and its Trim end is undefined
/// until Stop, so the dock states that instead of offering Export.
#Preview("Dock · still capturing") {
    let recording = Recording.stub(seconds: 93)
    return previewDock(recording, capture: PreviewCapture.capturing(recording),
                       coordinator: ExportCoordinator())
}

#Preview("Dock · running") {
    let recording = Recording.stub()
    let coordinator = ExportCoordinator()
    coordinator.enter(phase: .running(fraction: 0.42), subject: recording)
    return previewDock(recording, capture: PreviewCapture.settled, coordinator: coordinator)
}

#Preview("Dock · succeeded") {
    let recording = Recording.stub()
    let coordinator = ExportCoordinator()
    coordinator.enter(phase: .succeeded(url: recording.url), subject: recording)
    return previewDock(recording, capture: PreviewCapture.settled, coordinator: coordinator)
}

/// The tallest phase — a two-line failure — which is the one `exportControlHeight` is sized to. The
/// message is one the app actually produces, and it is the longest of them: found the
/// sentence shortened to fit these two `.caption` lines beside `Try Again…`, so a preview carrying a
/// made-up longer one would be testing a straw man.
#Preview("Dock · failed") {
    let recording = Recording.stub()
    let coordinator = ExportCoordinator()
    coordinator.enter(phase: .failed(message: "Not enough space: needs 5.41 MB, 2.96 MB free."),
                     subject: recording)
    return previewDock(recording, capture: PreviewCapture.settled, coordinator: coordinator)
}

/// An empty Recording — a hand-adopted file with no audio in it. Until it was refused only
/// because `Trim(duration: 0).length` happens to be 0; it is `ExportReadiness`'s own rule now.
#Preview("Dock · refused · nothing in the Trim") {
    previewDock(.stub(seconds: 0), capture: PreviewCapture.settled,
                coordinator: ExportCoordinator())
}

/// A 96 kHz adopted file against the default `high` sticky — the three AAC rungs refuse it,
/// so the dock names the situation while each rung states its own specific reason above.
/// **The state could only photograph with a doctored Library and a `defaults write`**; here
/// it is one line.
#Preview("Dock · refused · unencodable") {
    previewDock(.stub("ZZ Probe 96k", sampleRate: 96_000), capture: PreviewCapture.settled,
                coordinator: ExportCoordinator())
}

/// An Export running on a *different* subject. Its one route used to be — a rename
/// mid-encode moved `recording.url` while `subjectURL` kept the old path — which closed by
/// having the telling follow its Recording; what is left is the compound case in
/// `ExportReadiness.Reason.alreadyRunning`. So this refusal has still never been seen in the running
/// app, and this is where it is looked at. Parked on a Recording that is deliberately not this one.
#Preview("Dock · refused · already running") {
    let coordinator = ExportCoordinator()
    coordinator.enter(phase: .running(fraction: 0.42), subject: .stub("Some Other Recording"))
    return previewDock(.stub(), capture: PreviewCapture.settled, coordinator: coordinator)
}

#endif

