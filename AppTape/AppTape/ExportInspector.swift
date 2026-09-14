import AppKit
import SwiftUI

/// The trailing Export inspector, permanently visible so the window has exactly one pane
/// control.
struct ExportInspector: View {
    var recording: Recording
    /// What capture is doing.
    var capture: any CaptureState

    /// The sticky Quality Preset and the Loudness switch. `@Bindable` because the dock
    /// writes them: the Toggle binds `normalizeLoudness` and picking a preset row assigns `preset`.
    @Bindable var preference: ExportPreference
    /// The running Export, one at a time and app-wide.
    var coordinator: ExportCoordinator
    /// The Loudness correction preview for this Trim. Owned by the editor's model so a
    /// resolved measurement outlives a redraw, and handed here rather than fetched off it.
    var correction: LoudnessCorrectionModel
    /// Playback, for the one thing this pane does to it: the combined preview gain.
    var player: AudioPlayer

    private var format: SourceFormat { recording.sourceFormat }

    /// One height for all four Export phases, so the dock cannot move as an Export runs.
    private static let exportControlHeight: Double = 34

    /// The sticky Quality Preset can't always encode an adopted file.
    @State private var perFilePreset: QualityPreset?

    /// Whether this Recording's audio is still arriving, so nothing may be claimed about its
    /// length. The lane, the transport and the sidebar row ask the same.
    private var isStillArriving: Bool { capture.isStillArriving(recording) }

    /// The preset actually shown selected and exported: the per-file display-over if one was chosen,
    /// otherwise the sticky preference.
    private var effectivePreset: QualityPreset { perFilePreset ?? preference.preset }

    /// Whether an Export may start, and if not, what the dock says.
    private var readiness: ExportReadiness {
        .evaluate(isOpenable: recording.isOpenable,
                  isCapturing: capture.isCapturing(recording),
                  trimmedFrameCount: recording.trimmedFrameRange.count,
                  preset: effectivePreset, format: format,
                  isExporting: coordinator.isExporting)
    }

    /// Choosing a preset row.
    private func pick(_ newValue: QualityPreset) {
        switch QualityPreset.PresetPick.resolve(picking: newValue, sticky: preference.preset,
                                                format: format) {
        case .setSticky(let preset): preference.preset = preset; perFilePreset = nil
        case .displayOver(let preset): perFilePreset = preset
        case .ignore: break
        }
    }

    /// Re-measure whenever the Recording, its Trim, or the toggle changes.
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
            // No `Selection` section. It stated the Trim's length and range forty points from a
            // transport that already states them, in a different colour — the window disagreeing
            Section("Quality") {
                // All four preset rows and all four estimates on screen at once, so the choice is
                // *compared* rather than revealed one at a time by a menu.
                ForEach(QualityPreset.allCases) { preset in
                    presetRow(preset)
                }
                sourceFormatLine
            }

            // Loudness and Gain sit below the preset rows: they never move an estimate, so they read
            // after the thing they do not affect.
            Section("Level") {
                loudnessAndGainControls
            }
        }
        .formStyle(.grouped)
        // The trailing column now paints its own `.controlBackgroundColor` to separate itself from
        // the detail pane (research report 0006), so the `Form` must not paint the window
        // background it assumes it is sitting on back over it.
        .scrollContentBackground(.hidden)
        // The Export control is pinned to the pane's bottom edge, not scrolled with the Form.
        .safeAreaBar(edge: .bottom) {
            exportControl
                // Idle ⇄ running ⇄ succeeded is the state change the user most needs to notice
                // and least directly causes — the encode finishing is the app's news, not theirs.
                .motion(Metrics.motionState, value: coordinator.phase)
                .frame(height: Self.exportControlHeight)
                .padding(.horizontal, Metrics.lg)
                .padding(.vertical, Metrics.md)
                .frame(maxWidth: .infinity)
        }
        // No `.motion` here. Four of them used to sit on this `Form`, and that is why the
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

    /// One Quality Preset preset row: checkmark, name, codec, and its own size estimate — and, on a
    /// preset row that cannot encode, the plain reason why, *below* the control rather than inside it.
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
                    // The codec and bitrate only, not the whole `subtitle(for:)`.
                    if encodability.isAvailable {
                        Text(preset.codecLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: Metrics.xs)

                // No estimate while the audio is still arriving.
                if encodability.isAvailable {
                Text(isStillArriving ? "—"
                                     : ExportSizeEstimate.text(preset: preset, format: format,
                                                               duration: recording.trimmedDuration))
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
                    // The estimate re-reckons as the Trim moves: a figure that ticks, which is what
                    // `.numericText` is for.
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
        // inspector *row* wants would cost the button trait.
        .accessibilityLabel(preset.displayName)
        .accessibilityValue([encodability.reason ?? preset.codecLabel,
                             isStillArriving ? "size not yet known"
                                             : ExportSizeEstimate.text(preset: preset, format: format,
                                                                       duration: recording.trimmedDuration)]
                                .joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            // The blocker, at full strength, outside everything that dims.
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

    /// The leading slot every preset row reserves for its checkmark, shared by the mark and by the
    /// indent that keeps an unencodable preset row's reason aligned under the preset's name.
    private static let checkmarkSlotWidth: CGFloat = 12

    /// The rate and channel count Export carries through untouched, said once: they are the
    /// source's, identical on every preset row, and asks for them to be visible, not repeated.
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

    /// The Correction row in words.
    private var correctionSpokenValue: String {
        // Matches the preset rows' `size not yet known` while the audio arrives: what the dash means,
        // spoken.
        guard !isStillArriving else { return "not yet known" }
        return switch correction.state {
        case .off, .measuring: "Measuring"
        case .measured(let correction):
            [correction.figureText, correction.caption].compactMap { $0 }.joined(separator: ", ")
        }
    }

    /// The correction figure, as dB and never LUFS: `Measuring…` until the BS.1770
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
        // No verdict while the audio is still arriving, the same em dash the preset rows' size
        // estimates draw for the same reason.
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

    /// The dock states a blocker; it does not wear one.
    @ViewBuilder
    private var exportControlOrBlocker: some View {
        if let reason = readiness.blocker { dockSentence(reason) }
        else { exportButton }
    }

    /// The dock's one sentence shape, for every blocker there is. Holds the button's own box, so the
    /// dock keeps the single declared height pinned and nothing above it moves.
    private func dockSentence(_ reason: ExportReadiness.Reason) -> some View {
        Label(reason.sentence, systemImage: reason.symbolName)
            .font(.callout)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var exportButton: some View {
        // The width is asked for on the label, not on the `Button`.
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
            // Split for the same reason as the failed phase below: one `.foregroundStyle(.green)`
            // Light.
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

    /// The tallest phase, and so the one that sets `exportControlHeight`: two lines of reason
    /// beside a retry.
    private func failedControl(_ message: String) -> some View {
        HStack(spacing: Metrics.sm) {
            // The warning's colour belongs to its mark, not to its sentence.
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
    /// One accessibility element per inspector row, carrying both the label and the number.
    func accessibilityLabeledValue(_ label: LocalizedStringKey, _ value: String) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value)
    }
}

// MARK: - Previews

// `#if DEBUG`, as `PreviewFixtures.swift` is: a preview body is compiled in Release too.
#if DEBUG

/// The dock's states, and the reason the pane accepts its four collaborators rather than reaching
/// for them.

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

/// The tallest phase — a two-line failure — which is the one `exportControlHeight` is sized to.
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

/// A 96 kHz adopted file against the default `high` sticky — the three AAC preset rows refuse it, so
/// the dock names the situation while each preset row states its own specific reason above.
#Preview("Dock · refused · unencodable") {
    previewDock(.stub("ZZ Probe 96k", sampleRate: 96_000), capture: PreviewCapture.settled,
                coordinator: ExportCoordinator())
}

/// An Export running on a *different* subject.
#Preview("Dock · refused · already running") {
    let coordinator = ExportCoordinator()
    coordinator.enter(phase: .running(fraction: 0.42), subject: .stub("Some Other Recording"))
    return previewDock(.stub(), capture: PreviewCapture.settled, coordinator: coordinator)
}

#endif

