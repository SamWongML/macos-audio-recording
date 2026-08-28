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
            Section("Selection") {
                LabeledContent("Length") {
                    Text(Format.time(recording.trimmedDuration)).monospacedDigit()
                }
                LabeledContent("Trim") {
                    Text(recording.isTrimmed ? recording.trimRangeText : "Whole Recording")
                        .monospacedDigit()
                        .foregroundStyle(recording.isTrimmed ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
            }

            Section("Export") {
                Picker("Quality", selection: $preference.preset) {
                    ForEach(QualityPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }

                // The chosen preset's codec, bitrate, rate and channels — visible, never editable.
                Text(preference.preset.subtitle(for: format))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Loudness and Gain sit between the Quality Preset and the estimate (issue #55): they
                // never move the estimate (ADR-0012), so they read below the preset, unaffected.
                loudnessAndGainControls

                LabeledContent("Estimated size") {
                    Text(ExportSizeEstimate.text(preset: preference.preset, format: format,
                                                 duration: recording.trimmedDuration))
                        .monospacedDigit()
                }

                exportControl
            }
        }
        .formStyle(.grouped)
        .animation(.default, value: recording.trimmedDuration)
        .animation(.default, value: coordinator.phase)
        .animation(.default, value: preference.normalizeLoudness)
        .animation(.default, value: editor.correction.state)
        .onChange(of: correctionKey, initial: true) {
            editor.correction.update(recording: recording, normalize: preference.normalizeLoudness)
        }
        .onChange(of: playbackGainDB, initial: true) {
            editor.player.setGlobalGainDB(playbackGainDB)
        }
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
            coordinator.export(recording: recording, preset: preference.preset)
        }
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity)
        .disabled(recording.trimmedDuration <= 0 || coordinator.isExporting)
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
                coordinator.export(recording: recording, preset: preference.preset)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
    }
}
