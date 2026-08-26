//  PROTOTYPE — throwaway app shell for issue #25. Not production code.
//
//  One window: the #7 editor frame (waveform + Trim on the left, the permanent Export
//  inspector on the right). A second floating window switches the one axis this prototype is
//  actually about — Treatment A (stock components) ↔ B (custom meter) — and jumps between the
//  five loudness fixtures. ⌘Q quits.

import AppKit
import SwiftUI

@main
struct LevelControlsApp: App {
    @State private var editor = Editor()

    init() { Diag.start() }

    var body: some Scene {
        Window("AppTape", id: "editor") {
            EditorView(editor: editor)
                .tint(.orange)
                .task { await bootstrap() }
        }
        .defaultSize(width: 900, height: 460)
        .restorationBehavior(.disabled)

        Window("Level controls", id: "switcher") {
            Switcher(editor: editor).tint(.orange)
        }
        .windowLevel(.floating)
        .windowResizability(.contentSize)
        .defaultPosition(.bottomTrailing)
        .restorationBehavior(.disabled)
    }

    @MainActor private func bootstrap() async {
        do { try Fixtures.ensureLibrary() } catch { Diag.note("fixtures failed: \(error)") }
        editor.loadLibrary()
        Diag.note("library \(editor.recordings.count) Recordings")
        installKeys()
    }

    @MainActor private func installKeys() {
        _ = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.charactersIgnoringModifiers == " ",
               !event.modifierFlags.contains(.command) {
                editor.player.toggle(scope: .trimLooping); return nil
            }
            if TimelineKeys.handle(event, editor: editor) { return nil }
            return event
        }
    }
}

// MARK: - The editor frame (#7), reused only as a home for the Level section

struct EditorView: View {
    var editor: Editor

    var body: some View {
        Group {
            if let recording = editor.selection {
                detail(recording)
            } else {
                ContentUnavailableView("No Recording", systemImage: "waveform")
            }
        }
    }

    private var recordingBinding: Binding<URL?> {
        Binding(get: { editor.selection?.url },
                set: { url in editor.select(url.flatMap(editor.recording(for:))) })
    }

    private func detail(_ recording: Recording) -> some View {
        VStack(spacing: 0) {
            TrimTimeline(recording: recording, envelope: recording.envelope, player: editor.player,
                         precision: .whole, state: editor.timeline, showsRuler: true)
                .frame(minHeight: 150)
                .padding(.horizontal, 20).padding(.top, 18)

            transport(recording)
        }
        .navigationTitle(recording.name)
        .navigationSubtitle(recording.source)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            // Everything the switcher window carries, in the editor itself, so nothing is
            // hidden behind another window. The switcher stays as a bonus, not a requirement.
            ToolbarItem(placement: .navigation) {
                Picker("Recording", selection: recordingBinding) {
                    ForEach(editor.recordings) { r in
                        Text(r.source).tag(Optional(r.url))
                    }
                }
            }
            ToolbarItem(placement: .principal) {
                Picker("Treatment", selection: Bindable(editor.settings).treatment) {
                    ForEach(Treatment.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            ToolbarItem(placement: .primaryAction) {
                Toggle("Normalize", isOn: Bindable(editor.settings).normalizeLoudness)
                    .toggleStyle(.switch)
                    .onChange(of: editor.settings.normalizeLoudness) { editor.loudness.refresh(editor) }
            }
        }
        .inspector(isPresented: .constant(true)) {
            // #7: Export is a *permanent* trailing inspector — never hides, so the size
            // estimate stays live while a Trim handle moves. The Level section is #25's.
            ExportInspector(editor: editor, recording: recording)
                .inspectorColumnWidth(min: 260, ideal: 288, max: 360)
        }
    }

    private func transport(_ recording: Recording) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 14) {
                Button {
                    editor.player.toggle(scope: .trimLooping)
                } label: {
                    Image(systemName: editor.player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 24, height: 20)
                }
                .buttonStyle(.glass)
                .keyboardShortcut(.space, modifiers: [])

                Text(Format.time(editor.player.position, precise: true))
                    .font(.system(.title3, design: .monospaced)).monospacedDigit()

                Spacer()

                Text(recording.isTrimmed
                     ? "Trim \(Format.time(recording.trim.lowerBound)) – \(Format.time(recording.trim.upperBound))"
                     : "Whole · \(Format.time(recording.duration))")
                    .font(.callout).monospacedDigit()
                    .foregroundStyle(recording.isTrimmed ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))

                if recording.isTrimmed {
                    Button("Reset") { recording.resetTrim(); editor.loudness.refresh(editor) }
                        .buttonStyle(.link)
                }
            }
            // #25's contract, stated on screen: play is the check.
            Text("Playing auditions Loudness + Gain — what you hear is the Export.")
                .font(.caption2).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }
}

// MARK: - The switcher (deliberately plain, in its own floating window)

private struct Switcher: View {
    var editor: Editor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Level section — treatment").font(.caption).foregroundStyle(.secondary)
            Picker("", selection: Bindable(editor.settings).treatment) {
                ForEach(Treatment.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden().pickerStyle(.segmented).frame(width: 340)

            Text(editor.settings.treatment.claim)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).frame(width: 340, alignment: .leading)

            Divider()

            Picker("Recording", selection: Binding(
                get: { editor.selection?.url },
                set: { url in editor.select(url.flatMap(editor.recording(for:))) })) {
                ForEach(editor.recordings) { r in
                    Text("\(r.source) · \(Format.time(r.duration))").tag(Optional(r.url))
                }
            }
            .frame(width: 340)

            Toggle("Normalize loudness (app-wide, sticky)",
                   isOn: Bindable(editor.settings).normalizeLoudness)
                .onChange(of: editor.settings.normalizeLoudness) { editor.loudness.refresh(editor) }
                .frame(width: 340, alignment: .leading)

            Text(stateLine).font(.caption2).foregroundStyle(.tertiary)
                .frame(width: 340, alignment: .leading)

            if let message = editor.settings.lastMessage {
                Text(message).font(.caption2).foregroundStyle(.tertiary)
                    .frame(width: 340, alignment: .leading).lineLimit(3)
            }

            Text("space plays the Trim, looping · [ or ] picks a handle · ← / → nudge (⇧ = 1 s)")
                .font(.caption2).foregroundStyle(.tertiary)
                .frame(width: 340, alignment: .leading)
        }
        .padding(14)
    }

    private var stateLine: String {
        guard editor.settings.normalizeLoudness else { return "Correction: off" }
        switch editor.loudness.state {
        case .off: return "Correction: off"
        case .measuring: return "Correction: measuring…"
        case .ready(let c):
            let m = c.integratedLUFS.map { String(format: "%.1f LUFS", $0) } ?? "—"
            let p = c.truePeakDBTP.map { String(format: "%.1f dBTP", $0) } ?? "—"
            return "measured \(m), peak \(p) → \(c.figure)\(c.caption.map { " · \($0)" } ?? "")"
        }
    }
}
