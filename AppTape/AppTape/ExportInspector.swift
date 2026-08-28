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

    private var format: SourceFormat { recording.sourceFormat }

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
