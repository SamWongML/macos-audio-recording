//  PROTOTYPE — Variant O: waveform plus a trailing inspector.
//
//  Claim: Export is not a button, it is a small panel of settings that is about to grow —
//  #24 and #25 are queued to add Loudness and Gain to it — so it should have a permanent
//  home now instead of being crammed into a toolbar and then re-designed twice.
//
//  Also the only variant where playing means playing *the Trim*, looping: the inspector
//  shows what you will get, so the transport should too.
//
//  Price: the widest window of the four, and the inspector is mostly empty until #25 lands.

import SwiftUI

struct VariantO: View {
    var editor: Editor
    @State private var showsInspector = true
    @State private var showsLibrary = false

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
            TrimTimeline(recording: recording,
                         envelope: recording.envelope,
                         player: editor.player,
                         precision: editor.precision,
                         state: editor.timeline,
                         showsRuler: false)
                .padding(.horizontal, 22)
                .padding(.top, 20)

            transport(recording)
        }
        .navigationTitle(recording.name)
        .navigationSubtitle(recording.source)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Library", systemImage: "rectangle.stack") { showsLibrary.toggle() }
                    .popover(isPresented: $showsLibrary, arrowEdge: .bottom) {
                        libraryPopover
                    }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Inspector", systemImage: "sidebar.trailing") { showsInspector.toggle() }
            }
        }
        .inspector(isPresented: $showsInspector) {
            inspector(recording)
                .inspectorColumnWidth(min: 240, ideal: 270, max: 340)
        }
    }

    private func transport(_ recording: Recording) -> some View {
        HStack(spacing: 14) {
            Button {
                editor.player.toggle(scope: editor.variant.playScope)
            } label: {
                Image(systemName: editor.player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 24, height: 20)
            }
            .buttonStyle(.glass)
            .keyboardShortcut(.space, modifiers: [])
            .help("Plays the Trim, looping")

            Text(Format.time(editor.player.position, precise: true))
                .font(.system(.title3, design: .monospaced)).monospacedDigit()

            Spacer()

            Text(recording.isTrimmed
                 ? "Trim \(Format.time(recording.trim.lowerBound)) – \(Format.time(recording.trim.upperBound))"
                 : "Whole Recording · \(Format.time(recording.duration))")
                .font(.callout).monospacedDigit()
                .foregroundStyle(recording.isTrimmed ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))

            if recording.isTrimmed {
                Button("Reset") { recording.resetTrim() }.buttonStyle(.link)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private func inspector(_ recording: Recording) -> some View {
        Form {
            Section("Quality Preset") {
                PresetPicker(recording: recording, settings: editor.settings, style: .list)
                    .listRowInsets(EdgeInsets())
            }
            Section("Level") {
                LevelControlsStub(settings: editor.settings)
            }
            Section {
                LabeledContent("Estimated size") {
                    Text(recording.estimateText(editor.settings.preset))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                LabeledContent("Length") {
                    Text(Format.time(recording.trimmedDuration)).monospacedDigit()
                }
                Button("Export…") { editor.settings.run(recording) }
                    .buttonStyle(.glassProminent)
                    .frame(maxWidth: .infinity)
                    .keyboardShortcut("e")
            }
        }
        .formStyle(.grouped)
        .animation(.default, value: recording.trimmedDuration)
    }

    private var libraryPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(editor.recordings) { recording in
                Button {
                    editor.select(recording); showsLibrary = false
                } label: {
                    HStack {
                        Text(recording.source)
                        Spacer(minLength: 24)
                        Text(Format.time(recording.duration))
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 5).padding(.horizontal, 10)
                    .frame(width: 260, alignment: .leading)
                    .background(recording.url == editor.selection?.url
                                ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }
}
