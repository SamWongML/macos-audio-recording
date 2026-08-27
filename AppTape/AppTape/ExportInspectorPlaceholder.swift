//
//  ExportInspectorPlaceholder.swift
//  AppTape
//

import SwiftUI

/// The trailing Export inspector, **permanently visible** so the window has exactly one pane
/// control — the system's leading sidebar toggle — and nothing to mirror on the trailing edge
/// (issue #7's recommended "permanent inspector"). The panel exists so the estimated Export size
/// can stay live beside the waveform while a Trim handle moves; that machinery — the Quality
/// Presets, the size estimate, the Level block — is Ticket 5's (issues #9/#24/#25). Here it is a
/// placeholder that shows only what this ticket already knows: the Trim's length.
struct ExportInspectorPlaceholder: View {
    var recording: Recording

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
                Text("Quality Presets and the size estimate arrive with Export.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Export…") {}
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(true)
            }
        }
        .formStyle(.grouped)
        .animation(.default, value: recording.trimmedDuration)
    }
}
