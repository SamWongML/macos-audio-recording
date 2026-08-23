//  PROTOTYPE — Variant M: the document window.
//
//  Claim: ADR-0006 made the folder the truth, so the app should not ship a second Finder.
//  One window per Recording, titled with the Recording's name, with a proxy icon that is
//  the actual file. Older Recordings are opened from Finder or ⌘O. Nothing else is on screen.
//
//  Price: no way to compare two Recordings without two windows, and after a busy afternoon
//  you have eight of them.

import SwiftUI

struct VariantM: View {
    var editor: Editor
    var recording: Recording

    var body: some View {
        VStack(spacing: 0) {
            TrimTimeline(recording: recording,
                         envelope: recording.envelope,
                         player: editor.player,
                         precision: editor.precision,
                         state: editor.timeline)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 10)

            Divider()
            footer
        }
        .navigationTitle(recording.name)
        .navigationDocument(recording.url)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    editor.player.toggle(scope: editor.variant.playScope)
                } label: {
                    Label(editor.player.isPlaying ? "Pause" : "Play",
                          systemImage: editor.player.isPlaying ? "pause.fill" : "play.fill")
                }
                .keyboardShortcut(.space, modifiers: [])

                Text(Format.time(editor.player.position, precise: true))
                    .font(.system(.body, design: .monospaced)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            ToolbarItem(placement: .principal) {
                Button("Reveal in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([recording.url])
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                PresetPicker(recording: recording, settings: editor.settings, style: .menu)
                    .labelsHidden()
                    .frame(width: 210)

                Button("Export…") { editor.settings.run(recording) }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut("e")
            }
        }
    }

    /// The one line of chrome M allows itself: what you will get, and what it will cost.
    private var footer: some View {
        HStack(spacing: 14) {
            Label(recording.source, systemImage: "app.dashed")
            Text(recording.isTrimmed
                 ? "\(Format.time(recording.trimmedDuration)) of \(Format.time(recording.duration))"
                 : Format.time(recording.duration))
            if recording.isTrimmed {
                Button("Reset Trim") { recording.resetTrim() }
                    .buttonStyle(.link)
            }
            Spacer()
            Text(recording.estimateText(editor.settings.preset))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.default, value: recording.trimmedDuration)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .background(.bar)
    }
}
