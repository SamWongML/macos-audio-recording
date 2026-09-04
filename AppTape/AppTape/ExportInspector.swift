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

    /// The picker's selection. Reading gives the effective preset; writing a rung the sticky preset
    /// can encode updates the app-wide preference (issue #9), but writing one it can't (an adopted
    /// file the sticky doesn't fit) is a per-file display-over that leaves the sticky untouched
    /// (ADR-0015). A rung the codec can't encode is never accepted here.
    private var qualityBinding: Binding<QualityPreset> {
        Binding(
            get: { effectivePreset },
            set: { newValue in
                switch QualityPreset.PresetPick.resolve(picking: newValue, sticky: preference.preset,
                                                        format: format) {
                case .setSticky(let preset): preference.preset = preset; perFilePreset = nil
                case .displayOver(let preset): perFilePreset = preset
                case .ignore: break
                }
            })
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
            // The four Quality Presets, all four rungs and all four size estimates visible at once
            // (issue #7's variant O/Q): the selected rung tinted, an unusable rung dimmed with its
            // plain reason on hover (ADR-0015).
            Section("Quality Preset") {
                qualityPresetList
            }

            // Loudness and Gain (issue #55). They never move the size estimate (ADR-0012), so they
            // sit in their own section below the preset, above the summary.
            Section("Level") {
                loudnessAndGainControls
            }

            // The trailing summary: the effective preset's estimate and the Trim's length, directly
            // above the Export control that acts on them.
            Section {
                LabeledContent("Estimated size") {
                    Text(ExportSizeEstimate.text(preset: effectivePreset, format: format,
                                                 duration: recording.trimmedDuration))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                LabeledContent("Length") {
                    Text(Format.time(recording.trimmedDuration)).monospacedDigit()
                }
                exportControl
            }
        }
        .formStyle(.grouped)
        .animation(.default, value: recording.trimmedDuration)
        .animation(.default, value: coordinator.phase)
        .animation(.default, value: preference.normalizeLoudness)
        .animation(.default, value: editor.correction.state)
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

    /// All four Quality Preset rungs stacked, each with its codec/rate subtitle and its **own** live
    /// size estimate, so dragging a Trim handle moves all four figures at once (issue #7's variant O/Q,
    /// issue #41). The selected rung is tinted; a rung the source's format can't encode faithfully is
    /// dimmed and disabled, with its plain reason on hover, and when the *effective* rung is the one
    /// that can't encode, that reason is spelled out beneath the list so Export's refusal has a stated
    /// cause (ADR-0015).
    @ViewBuilder
    private var qualityPresetList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(QualityPreset.allCases) { preset in
                presetRow(preset)
            }
        }
        .listRowInsets(EdgeInsets())

        if let reason = effectiveEncodability.reason {
            VStack(alignment: .leading, spacing: 3) {
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Choose a quality that fits this file.")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    private func presetRow(_ preset: QualityPreset) -> some View {
        let encodability = preset.encodability(for: format)
        let selected = effectivePreset == preset
        return Button {
            qualityBinding.wrappedValue = preset
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.displayName)
                    Text(preset.subtitle(for: format))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(ExportSizeEstimate.text(preset: preset, format: format,
                                             duration: recording.trimmedDuration))
                    .font(.caption).monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .padding(.vertical, 4).padding(.horizontal, 8)
            .background(selected ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .opacity(encodability.isAvailable ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!encodability.isAvailable)
        .help(encodability.reason ?? "")
    }

    // MARK: - Loudness & Gain (normalize toggle, correction read-out, Gain slider)

    @ViewBuilder
    private var loudnessAndGainControls: some View {
        Toggle("Normalize loudness", isOn: $preference.normalizeLoudness)

        if preference.normalizeLoudness {
            LabeledContent("Correction") { correctionReadout }
        }

        LabeledContent("Gain") {
            Text(LoudnessCorrection.signedDecibels(recording.gain)).monospacedDigit()
        }
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
        if recording.gain != 0 {
            Button("Reset Gain") {
                recording.gain = 0
                recording.persistGain()
            }
            .buttonStyle(.link)
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
        Button("Export…") {
            coordinator.export(recording: recording, preset: effectivePreset)
        }
        .buttonStyle(.glassProminent)
        .frame(maxWidth: .infinity)
        .keyboardShortcut("e")
        // Blocked while the effective preset can't encode this file, until a working rung is chosen
        // (ADR-0015).
        .disabled(recording.trimmedDuration <= 0 || coordinator.isExporting
                  || !effectiveEncodability.isAvailable)
    }

    private func runningControl(_ fraction: Double) -> some View {
        VStack(spacing: 6) {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
            HStack {
                Text("Exporting… \(Int((fraction * 100).rounded()))%")
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { coordinator.cancel() }
                    .buttonStyle(.link)
            }
        }
    }

    private func succeededControl(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Exported", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            HStack {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                Spacer()
                Button("Done") { coordinator.cancel() }
                    .buttonStyle(.link)
            }
        }
    }

    private func failedControl(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
            Button("Try Again…") {
                coordinator.cancel()   // clear the failure, then re-present the save panel
                coordinator.export(recording: recording, preset: effectivePreset)
            }
            .buttonStyle(.glassProminent)
            .frame(maxWidth: .infinity)
        }
    }
}
