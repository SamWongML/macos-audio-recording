//  PROTOTYPE — Variant P: the tape deck.
//
//  Claim: on a twenty-minute capture you find the edit by ear, not by eye. A pixel is more
//  than a second wide, so dragging a handle can never land on the word you meant. So the
//  playhead is the instrument: play, listen, and press Mark In (⌘I) / Mark Out (⌘O).
//  The waveform is demoted to a passive strip that only confirms where the marks landed —
//  its handles are inert on purpose.
//
//  Price: setting a Trim now costs a listen. For "cut the eight seconds of silence off the
//  front", which you can *see*, that is strictly worse than one drag.

import SwiftUI

struct VariantP: View {
    var editor: Editor

    var body: some View {
        Group {
            if let recording = editor.selection {
                content(recording)
            } else {
                ContentUnavailableView("No Recordings", systemImage: "waveform")
            }
        }
    }

    private func content(_ recording: Recording) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            readout(recording)
            transport(recording)
            Spacer(minLength: 0)

            TrimTimeline(recording: recording,
                         envelope: recording.envelope,
                         player: editor.player,
                         precision: editor.precision,
                         state: editor.timeline,
                         showsRuler: false,
                         handlesEnabled: false)
                .frame(height: 58)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

            deck
        }
        .navigationTitle(recording.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                PresetPicker(recording: recording, settings: editor.settings, style: .menu)
                    .labelsHidden().frame(width: 200)
                Button("Export…") { editor.settings.run(recording) }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut("e")
            }
        }
    }

    /// The whole variant in one element: the time you are at, big enough to read across a desk.
    private func readout(_ recording: Recording) -> some View {
        VStack(spacing: 6) {
            Text(Format.time(editor.player.position, precise: true))
                .font(.system(size: 56, weight: .light, design: .monospaced))
                .monospacedDigit()
                .contentTransition(.numericText())

            HStack(spacing: 18) {
                markLabel("IN", recording.trim.lowerBound, set: recording.trim.lowerBound > 0.0005)
                Text("→").foregroundStyle(.tertiary)
                markLabel("OUT", recording.trim.upperBound,
                          set: recording.trim.upperBound < recording.duration - 0.0005)
                Divider().frame(height: 14)
                Text("\(Format.time(recording.trimmedDuration)) · \(recording.estimateText(editor.settings.preset))")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.callout)
        }
        .padding(.bottom, 18)
    }

    private func markLabel(_ title: String, _ value: Double, set: Bool) -> some View {
        HStack(spacing: 5) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            Text(Format.time(value, precise: true))
                .monospacedDigit()
                .foregroundStyle(set ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
    }

    private func transport(_ recording: Recording) -> some View {
        HStack(spacing: 10) {
            Button("Go to In", systemImage: "backward.end.fill") {
                editor.player.seek(to: recording.trim.lowerBound)
            }
            Button("Back 5s", systemImage: "gobackward.5") {
                editor.player.seek(to: editor.player.position - 5)
            }
            Button {
                editor.player.toggle(scope: editor.variant.playScope)
            } label: {
                Image(systemName: editor.player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2).frame(width: 44, height: 30)
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.space, modifiers: [])
            Button("Forward 5s", systemImage: "goforward.5") {
                editor.player.seek(to: editor.player.position + 5)
            }
            Button("Go to Out", systemImage: "forward.end.fill") {
                editor.player.seek(to: recording.trim.upperBound)
            }

            Divider().frame(height: 22).padding(.horizontal, 6)

            Button("Mark In") {
                let inPoint = min(editor.player.position, recording.trim.upperBound - 0.2)
                recording.trim = max(0, inPoint)...recording.trim.upperBound
            }
            .keyboardShortcut("i")
            Button("Mark Out") {
                let outPoint = max(editor.player.position, recording.trim.lowerBound + 0.2)
                recording.trim = recording.trim.lowerBound...min(recording.duration, outPoint)
            }
            .keyboardShortcut("o")
            Button("Clear") { recording.resetTrim() }
                .disabled(!recording.isTrimmed)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
    }

    /// The Library as a shelf you flick along, rather than a list you navigate.
    private var deck: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(editor.recordings) { recording in
                    let selected = recording.url == editor.selection?.url
                    Button { editor.select(recording) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            WaveformShape(columns: recording.envelope
                                            .columns(over: 0...max(recording.duration, 0.001), count: 90),
                                          peakStyle: AnyShapeStyle(.secondary.opacity(0.3)),
                                          bodyStyle: AnyShapeStyle(selected ? AnyShapeStyle(.tint)
                                                                            : AnyShapeStyle(.secondary)))
                                .frame(width: 120, height: 26)
                            Text(recording.source).font(.caption).lineLimit(1)
                            Text(Format.time(recording.duration))
                                .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .frame(width: 138, alignment: .leading)
                        .background(selected ? AnyShapeStyle(.tint.opacity(0.13))
                                             : AnyShapeStyle(.quaternary.opacity(0.4)),
                                    in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .frame(height: 96)
        .background(.bar)
    }
}
