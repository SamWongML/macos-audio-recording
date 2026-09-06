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
    /// Whether the selected Recording is the one capturing right now — the transport asks, as the
    /// lane and the inspector already do (ADR-0021).
    @State private var recorder = RecordingController.shared
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    /// The editor honours these itself; only `PanelView` used to (issue #73, finding 15). Reduce
    /// Motion rides the token set's `.motion(_:value:)` helper rather than being read here.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// The Recordings the sidebar is actually showing. Named, rather than filtered inline, because
    /// the footer counts it too: it used to count `store.recordings`, so a query matching nothing
    /// left an empty list under the words `44 Recordings` (issue #73, finding 35).
    private var matches: [Recording] {
        model.store.recordings.filter {
            query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.name.localizedCaseInsensitiveContains(query)
        }
    }

    private var days: [RecordingDay] { RecordingDay.group(matches) }

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
                        LibraryRow(recording: recording, model: model)
                            .tag(recording.url)
                    }
                }
            }
        }
        // A `List` with nothing in it simply renders nothing, so both empty states were a blank
        // grey column with only the footer's "0 Recordings" to explain them (issue #73, findings
        // 16 and 17). Two different silences, told apart: a Library with no Recordings yet points
        // at where they come from, a query with no matches names the query.
        .overlay {
            if matches.isEmpty {
                if !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ContentUnavailableView {
                        Label("No Recordings", systemImage: "waveform")
                    } description: {
                        Text("Recordings you make from the menu bar appear here.")
                    }
                }
            }
        }
        .searchable(text: $query, placement: .sidebar, prompt: "Recordings")
        .searchFocused($isSearchFocused)
        .onKeyPress(.return) {
            // Return renames the selected row, as it does in a Finder list. Ignored while the
            // search field has focus, where Return means "search", and while a rename is already
            // open, where Return belongs to the field's own submit (ADR-0020).
            guard !isSearchFocused, model.renamingURL == nil, let selection = model.selection
            else { return .ignored }
            model.beginRename(selection)
            return .handled
        }
        // Published only while the sidebar itself has focus: this is what gates File ▸ Move to
        // Trash, so ⌘⌫ cannot fire out of the search field or a Trim drag (ADR-0020).
        .focusedValue(\.librarySidebarRecording, model.selection?.url)
        .navigationSplitViewColumnWidth(min: 232, ideal: 268, max: 360)
        .safeAreaInset(edge: .bottom) {
            // Nothing critical lives down here: the HIG's Sidebars page warns that people
            // relocate windows in ways that hide the bottom edge.
            HStack {
                Text("^[\(matches.count) Recording](inflect: true)")
                Spacer()
                Button("Reveal", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([model.store.directory])
                }
                .buttonStyle(.borderless)
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 7)
            // Reduce Transparency: the vibrant `.bar` becomes an opaque window background, as
            // `PanelView` has always done. The map's Notes carry this constraint forward, and the
            // editor was honouring neither of the two (issue #73, finding 15).
            .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                                           : AnyShapeStyle(.bar))
        }
    }

    private var selectionBinding: Binding<URL?> {
        Binding(get: { model.selection?.url },
                set: { url in model.select(url.flatMap(model.recording(for:))) })
    }

    // MARK: - Detail (waveform, Trim, transport) + permanent inspector

    /// The trailing inspector is attached **here**, above the three branches, not inside the one
    /// that has a Recording to export. It used to hang off `editorDetail` alone, so selecting a
    /// can't-open file — or deselecting — made the whole trailing column disappear and the window's
    /// layout jump as the user arrowed down the Library (issue #73, finding 24). "Permanently
    /// visible" (issue #7) has to mean permanently, or the pane is a third pane control.
    private var detail: some View {
        detailContent
            .inspector(isPresented: .constant(true)) {
                inspectorColumn
                    .inspectorColumnWidth(min: 248, ideal: 276, max: 340)
            }
    }

    @ViewBuilder
    private var detailContent: some View {
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

    /// What the permanent inspector holds when there is nothing to export. It says why rather than
    /// showing a disabled Export ladder, which would invite a click that can never work.
    @ViewBuilder
    private var inspectorColumn: some View {
        if let recording = model.selection, recording.isOpenable {
            ExportInspector(recording: recording)
        } else {
            ContentUnavailableView {
                Label("Nothing to export", systemImage: "square.and.arrow.up")
            } description: {
                Text(model.selection == nil
                     ? "Select a Recording in the Library."
                     : "AppTape can't decode this file, so there is nothing to export from it.")
            }
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
        .navigationTitle(recording.displayName)
        .navigationSubtitle(recording.windowSubtitle)
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
        // The Library's own name for the Recording, not the filename. The title bar used to read
        // `Google Chrome 2026-09-04 at 21.52.43` over the subtitle `Google Chrome` — the Source
        // stated twice, once wrapped in the on-disk naming scheme — and for a hand-adopted file
        // with no date and no Source xattr both lines were the same string (issue #73, findings 2
        // and 32). `windowSubtitle` says when instead, and adds the Source back only once the
        // title has stopped being it.
        .navigationTitle(recording.displayName)
        .navigationSubtitle(recording.windowSubtitle)
    }

    private func transport(_ recording: Recording) -> some View {
        // A Recording whose audio is still arriving has no dependable length and nothing to play
        // (ADR-0021): the lane says so, and the transport must not contradict it.
        let isStillArriving = recorder.isStillArriving(recording)
        return HStack(spacing: 14) {
            Button {
                model.player.toggle()
            } label: {
                Image(systemName: model.player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 24, height: 20)
            }
            .buttonStyle(.glass)
            .keyboardShortcut(.space, modifiers: [])
            .help("Plays the Trim, looping")
            // The space shortcut goes inert with the button (ADR-0021).
            .disabled(isStillArriving)

            Text(Format.time(model.player.position, precise: true))
                .font(.system(.title3, design: .monospaced)).monospacedDigit()
                .foregroundStyle(isStillArriving ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))

            Spacer()

            // Nothing is said about the length of a Recording whose file is still being written:
            // the lane already says why, and `Whole Recording · 0:00` was a confident statement of
            // a length that had simply not been read yet (issue #80).
            if !isStillArriving {
                Text(recording.isTrimmed
                     ? "Trim \(recording.trimRangeText)"
                     : "Whole Recording · \(Format.time(recording.duration))")
                    .font(.callout).monospacedDigit()
                    .foregroundStyle(recording.isTrimmed ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))

                if recording.isTrimmed {
                    Button("Reset") { recording.resetTrim() }.buttonStyle(.link)
                }
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
    var model: EditorModel

    @FocusState private var isEditing: Bool
    @State private var draft = ""
    @State private var refusal: LibraryLocation.NameRefusal?

    private var isRenaming: Bool { model.renamingURL == recording.url }

    var body: some View {
        Group {
            if isRenaming { renameField } else { content }
        }
        .frame(height: 32)
        // Not drawn under the name field: the silhouette is a comparison aid for browsing, and
        // behind editable text it is just noise.
        .background(alignment: .leading) { if !isRenaming, recording.isOpenable { silhouette } }
        .contextMenu {
            // Exactly three (issue #75). `Duplicate` is out of scope: a master is 1.4 GB/hour
            // (ADR-0003), and a second Trim over one master has nowhere to live under ADR-0006.
            RenameButton()
            Button("Reveal in Finder") { model.reveal(recording) }
            Divider()
            // No confirm sheet — the Trash is the confirmation (ADR-0006).
            Button("Move to Trash", role: .destructive) { model.trash(recording) }
        }
        // Feeds `RenameButton` above, and is why the menu item needs no action of its own.
        .renameAction { model.beginRename(recording) }
    }

    private var content: some View {
        HStack(spacing: 7) {
            // The Source until the user names the Recording themselves, their name after
            // (ADR-0020) — otherwise a rename would change nothing the Library shows.
            Text(recording.displayName)
                .lineLimit(1)
                .foregroundStyle(recording.isOpenable ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))

            // No negative layout priority: starved of width it collapsed the timestamp to a bare
            // `…` rather than dropping it, leaving a stray ellipsis between the name and
            // `Can't open` (issue #73, finding 34). It is either shown or it is not.
            Text(recording.recordedAt?.formatted(date: .omitted, time: .shortened) ?? "")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .fixedSize()

            Spacer(minLength: 0)

            if !recording.isOpenable {
                // A `public.audio`-typed file the decoder can't open (ADR-0015): listed so it doesn't
                // vanish, but marked so the user knows why it won't play — no duration, no silhouette.
                //
                // The extension stands in for the duration a playable row shows. Without it two
                // different files — a `.wma` and a `.mid` — rendered as byte-identical rows, so the
                // Library could not tell the user which was which (issue #73, finding 33).
                Text(recording.url.pathExtension.uppercased())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
    }

    /// The name field, in the row rather than in a sheet — a rename is a file rename (ADR-0006),
    /// and Finder is the idiom the user already has for it. It takes focus as it appears, commits
    /// on Return, reverts on Escape, and on a name the Library refuses it stays open with what was
    /// typed still in it, saying why (ADR-0020).
    private var renameField: some View {
        TextField("Name", text: $draft)
            .textFieldStyle(.plain)
            .focused($isEditing)
            .onSubmit { commit(keepingFocus: true) }
            .onExitCommand { model.endRename() }
            .onAppear {
                draft = recording.name   // the base name: the extension is never the user's to edit
                isEditing = true
            }
            .onChange(of: draft) { refusal = nil }
            .onChange(of: isEditing) { _, focused in
                // Focus left the field — another row, or the window. Finder commits here; a name
                // it would refuse is abandoned instead, because there is no longer a field to hold
                // open and a popover over a row the user has left is noise.
                if !focused, isRenaming { commit(keepingFocus: false) }
            }
            .popover(isPresented: refusalPresented, arrowEdge: .trailing) {
                Text(refusal?.message ?? "")
                    .font(.callout)
                    // Wraps rather than truncates: the reason is the whole point of the popover,
                    // and a name long enough to collide is long enough to overflow one line.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 240, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
    }

    private var refusalPresented: Binding<Bool> {
        Binding(get: { refusal != nil }, set: { if !$0 { refusal = nil } })
    }

    private func commit(keepingFocus: Bool) {
        switch model.rename(recording, to: draft) {
        case .unchanged, .rename:
            model.endRename()
        case .refused(let why):
            guard keepingFocus else { model.endRename(); return }
            refusal = why
            isEditing = true
        }
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

// MARK: - Focused values

extension FocusedValues {
    /// The Library sidebar's selected Recording, published **only while the sidebar has focus**.
    /// ADR-0020 gates File ▸ Move to Trash on it: Rename and Reveal are harmless from anywhere,
    /// but ⌘⌫ moves a file to the Trash, and firing that out of a search field the user is typing
    /// into is the one outcome worth spending a focus value on.
    @Entry var librarySidebarRecording: URL?
}

#Preview {
    EditorView()
}
