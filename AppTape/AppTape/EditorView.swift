//
//  EditorView.swift
//  AppTape
//

import AppKit
import SwiftUI

/// The editor window: three columns — the Library as a leading sidebar, the waveform and Trim in
/// the middle, and a permanently-visible trailing Export inspector (issue #7, variant Q with the
/// "permanent inspector" pane treatment). It has **exactly one pane control**, the system sidebar
/// toggle `NavigationSplitView` installs for free on the leading edge, so there is nothing to
/// mirror on the trailing edge; `SidebarCommands()`/`InspectorCommands()` are deliberately not
/// added (they left the app with zero windows — issue #7, ADR-0017), and the title bar drops its
/// toolbar background so the waveform reads to the window's edge.
struct EditorView: View {
    @State private var model = EditorModel.shared
    @State private var query = ""
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    private var days: [RecordingDay] {
        RecordingDay.group(model.store.recordings.filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
        })
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            // The hidden window-toolbar background is unconditional (the spec asks for it on the
            // title bar, not only when a Recording is shown), so it rides the detail wrapper —
            // above the empty-state branch as well as the editor.
            detail
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        }
        .navigationSplitViewStyle(.balanced)
        .task { model.activate() }
        .onChange(of: model.vanishedTick) {
            // The open Recording was deleted or moved out from under the editor: close the
            // window rather than hold a stale one (ADR-0006).
            dismissWindow(id: AppTapeApp.editorWindowID)
        }
        .editorActivationPolicy()
    }

    // MARK: - Sidebar (the Library)

    private var sidebar: some View {
        List(selection: selectionBinding) {
            ForEach(days) { day in
                Section(day.title) {
                    ForEach(day.recordings) { recording in
                        LibraryRow(recording: recording)
                            .tag(recording.url)
                    }
                }
            }
        }
        .searchable(text: $query, placement: .sidebar, prompt: "Recordings")
        .navigationSplitViewColumnWidth(min: 232, ideal: 268, max: 360)
        .safeAreaInset(edge: .bottom) {
            // Nothing critical lives down here: the HIG's Sidebars page warns that people
            // relocate windows in ways that hide the bottom edge.
            HStack {
                Text("^[\(model.store.recordings.count) Recording](inflect: true)")
                Spacer()
                Button("Reveal", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([model.store.directory])
                }
                .buttonStyle(.borderless)
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(.bar)
        }
    }

    private var selectionBinding: Binding<URL?> {
        Binding(get: { model.selection?.url },
                set: { url in model.select(url.flatMap(model.recording(for:))) })
    }

    // MARK: - Detail (waveform, Trim, transport) + permanent inspector

    @ViewBuilder
    private var detail: some View {
        if let recording = model.selection {
            if recording.isOpenable {
                editorDetail(recording)
            } else {
                cantOpenDetail(recording)
            }
        } else {
            ContentUnavailableView("No Recording selected", systemImage: "waveform")
        }
    }

    /// A `public.audio`-typed file the decoder can't open (ADR-0015). It is adopted and listed so it
    /// doesn't silently vanish, but nothing can be done with it except delete it — no waveform, no
    /// Trim, no Export inspector.
    private func cantOpenDetail(_ recording: Recording) -> some View {
        ContentUnavailableView {
            Label("Can't open this file", systemImage: "waveform.slash")
        } description: {
            Text("It's an audio file AppTape can't decode. It stays here until you remove it.")
        } actions: {
            Button("Move to Trash", role: .destructive) {
                model.trash(recording)
            }
        }
        .navigationTitle(recording.name)
    }

    @ViewBuilder
    private func editorDetail(_ recording: Recording) -> some View {
        VStack(spacing: 0) {
            TrimTimeline(recording: recording,
                         envelope: recording.envelope,
                         player: model.player,
                         onTrimCommitted: { recording.persistTrim() },
                         showsRuler: false)
                .padding(.horizontal, 22)
                .padding(.top, 20)

            transport(recording)

            if let summary = recording.seamSummary {
                // Every Seam is recorded; the small ones that do not draw are told here in one
                // line rather than littering the lane (ADR-0010).
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.dashed")
                    Text(summary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 22)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle(recording.name)
        .navigationSubtitle(recording.source)
        .inspector(isPresented: .constant(true)) {
            ExportInspector(recording: recording)
                .inspectorColumnWidth(min: 248, ideal: 276, max: 340)
        }
    }

    private func transport(_ recording: Recording) -> some View {
        HStack(spacing: 14) {
            Button {
                model.player.toggle()
            } label: {
                Image(systemName: model.player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 24, height: 20)
            }
            .buttonStyle(.glass)
            .keyboardShortcut(.space, modifiers: [])
            .help("Plays the Trim, looping")

            Text(Format.time(model.player.position, precise: true))
                .font(.system(.title3, design: .monospaced)).monospacedDigit()

            Spacer()

            Text(recording.isTrimmed
                 ? "Trim \(recording.trimRangeText)"
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
}

// MARK: - The sidebar row

/// One line, 32 points. The Recording's own silhouette runs behind the row but is **masked away
/// from both ends** — it fades in past the text and out again before the duration — so nothing is
/// drawn under a glyph and nothing is truncated to make room for it. Drawn as a `WaveformPath`
/// (`Shape`), because a `Canvas` inside a `List` row draws nothing on macOS 27 (issue #7). The
/// mask keeps the waveform's drawn region at a fixed *fraction* of the row, so two Recordings'
/// silhouettes stay comparable — the only reason it is here, given Sources repeat within a day.
private struct LibraryRow: View {
    var recording: Recording

    var body: some View {
        HStack(spacing: 7) {
            Text(recording.source)
                .lineLimit(1)
                .foregroundStyle(recording.isOpenable ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))

            Text(recording.recordedAt?.formatted(date: .omitted, time: .shortened) ?? "")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .layoutPriority(-1)

            Spacer(minLength: 0)

            if !recording.isOpenable {
                // A `public.audio`-typed file the decoder can't open (ADR-0015): listed so it doesn't
                // vanish, but marked so the user knows why it won't play — no duration, no silhouette.
                Text("Can't open")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("An audio file AppTape can't decode. Select it to remove it.")
            } else {
                if recording.isTrimmed {
                    Image(systemName: "scissors")
                        .font(.caption2)
                        .foregroundStyle(Palette.signal)
                }

                // A subtle trailing glyph on Recordings with surfaced Seams — the Library is where a
                // user arrives weeks later, when the moment's telling is long gone (ADR-0010). Tertiary,
                // not tinted: it is *no data here*, not a warning.
                if recording.isSurfacedForSeams {
                    Image(systemName: "rectangle.dashed")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .help("Contains Seams — silence padded in where audio was interrupted")
                }

                Text(Format.time(recording.duration))
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 32)
        .background(alignment: .leading) { if recording.isOpenable { silhouette } }
    }

    private var silhouette: some View {
        WaveformPath(columns: recording.envelope.columns(
            over: 0...max(recording.duration, 0.001), count: 120))
            .fill(.secondary.opacity(0.5))
            .frame(height: 15)
            .mask {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.00),
                    .init(color: .clear, location: 0.42),
                    .init(color: .black, location: 0.56),
                    .init(color: .black, location: 0.80),
                    .init(color: .clear, location: 0.90),
                ], startPoint: .leading, endPoint: .trailing)
            }
            .allowsHitTesting(false)
    }
}

#Preview {
    EditorView()
}
