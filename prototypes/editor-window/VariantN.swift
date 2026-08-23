//  PROTOTYPE — Variant N: the Library split.
//
//  Claim: you record the same Source over and over and want to compare takes, so one window
//  that never goes away beats a window per Recording. The Library is a sidebar; selecting a
//  row swaps the Recording under the same waveform.
//
//  Price: the app now owns a browser it has to keep in step with a folder the user can edit
//  behind its back, and the editor gets the narrower half of the window.

import SwiftUI

struct VariantN: View {
    var editor: Editor

    var body: some View {
        NavigationSplitView {
            List(editor.recordings, selection: selectionBinding) { recording in
                LibraryRow(recording: recording)
                    .tag(recording.url)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Text("^[\(editor.recordings.count) Recording](inflect: true)")
                    Spacer()
                    Button("Reveal", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Library.folder])
                    }
                    .buttonStyle(.borderless)
                }
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.bar)
            }
        } detail: {
            if let recording = editor.selection {
                detail(recording)
            } else {
                ContentUnavailableView("No Recording selected", systemImage: "waveform")
            }
        }
    }

    private var selectionBinding: Binding<URL?> {
        Binding(get: { editor.selection?.url },
                set: { url in editor.select(url.flatMap(editor.recording(for:))) })
    }

    private func detail(_ recording: Recording) -> some View {
        VStack(spacing: 0) {
            TrimTimeline(recording: recording,
                         envelope: recording.envelope,
                         player: editor.player,
                         precision: editor.precision,
                         state: editor.timeline)
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 8)

            HStack(spacing: 12) {
                Button {
                    editor.player.toggle(scope: editor.variant.playScope)
                } label: {
                    Image(systemName: editor.player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 22)
                }
                .buttonStyle(.glass)
                .keyboardShortcut(.space, modifiers: [])

                Text(Format.time(editor.player.position, precise: true))
                    .font(.system(.title3, design: .monospaced)).monospacedDigit()

                Spacer()

                if recording.isTrimmed {
                    Button("Reset Trim") { recording.resetTrim() }.buttonStyle(.link)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
        .navigationTitle(recording.name)
        .navigationSubtitle("\(recording.source) · \(Format.time(recording.duration))")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                PresetPicker(recording: recording, settings: editor.settings, style: .menu)
                    .labelsHidden().frame(width: 200)
                Text(recording.estimateText(editor.settings.preset))
                    .monospacedDigit().foregroundStyle(.secondary)
                Button("Export…") { editor.settings.run(recording) }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut("e")
            }
        }
    }
}

/// A sidebar row that has to say enough to pick between two Recordings of the same Source
/// on the same afternoon. The sparkline is the cheapest thing that distinguishes them.
private struct LibraryRow: View {
    var recording: Recording

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(recording.source).lineLimit(1)
                Text(recording.recordedAt?.formatted(date: .omitted, time: .shortened) ?? "")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            WaveformPath(columns: recording.envelope.columns(over: 0...max(recording.duration, 0.001), count: 46))
                .fill(.secondary.opacity(0.7))
                .frame(width: 46, height: 20)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.time(recording.duration)).monospacedDigit()
                if recording.isTrimmed {
                    Image(systemName: "scissors").font(.caption2).foregroundStyle(.tint)
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}
