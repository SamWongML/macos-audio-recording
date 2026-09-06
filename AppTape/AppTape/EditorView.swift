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
            // A bare `ContentUnavailableView(_:systemImage:)` — title and glyph, no second line.
            // Report 0002 found no premium comparison app with a bespoke empty state and Apple's
            // own guidance is the only grounding there is: say what to do next. So it says it.
            // No button: the action is *pick a row*, and a button that merely moved focus to the
            // sidebar would be a control invented to fill a hole.
            ContentUnavailableView {
                Label("No Recording selected", systemImage: "waveform")
            } description: {
                Text("Choose one in the Library to play it, set its Trim, and Export it.")
            }
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

    /// Top to bottom: the ruled lane, the **brief**, then air, with the transport in the bottom
    /// safe area (issue #77, ADR-0023).
    ///
    /// The lane is the only element allowed to take the leftover height (ADR-0019) — but it is
    /// **capped**, which the ADR did not say and the running app did. Uncapped, a tall window gave
    /// it four hundred points of one silhouette; the cap turns extra height into air below the
    /// brief instead.
    ///
    /// **Everything above the bar has a height that does not depend on which Recording is shown.**
    /// The Seam line used to be its own conditionally-present row, and the brief dropped `Captured`
    /// or `Master` when it had nothing to put there, so the stack was between three and five rows
    /// tall depending on the file — and because the lane takes what is left, arrowing down the
    /// Library made the lane shrink and grow under the pointer on every keystroke. The brief is now
    /// always exactly five rows, Seams among them, and the lane resolves to the same height for
    /// every Recording at a given window size.
    @ViewBuilder
    private func editorDetail(_ recording: Recording) -> some View {
        VStack(spacing: 0) {
            TrimTimeline(recording: recording,
                         envelope: recording.envelope,
                         player: model.player,
                         onTrimCommitted: { recording.persistTrim() })
                .frame(minHeight: Self.laneMinimumHeight, maxHeight: Self.laneMaximumHeight)
                .padding(.horizontal, Metrics.xl)
                .padding(.top, Metrics.lg)

            RecordingBrief(recording: recording)
                .padding(.horizontal, Metrics.xl)
                .padding(.top, Metrics.xl)

            Spacer(minLength: Metrics.lg)

            // A plain last child behind the `Spacer`. **All three of the framework's own bottom-bar
            // placements are unusable here**, which is worth writing down because each looks like
            // the obvious answer: `ToolbarItem(placement: .bottomBar)` does not compile on macOS at
            // all; `safeAreaInset(edge: .bottom)` and macOS 26's `safeAreaBar(edge: .bottom)` both
            // compile and both **abort the app on open** — a bottom bar on the content hosting the
            // permanently presented `.inspector` re-enters the layout pass until AppKit throws
            // (issue #85's loop). So the bar is laid out by hand, and only its *appearance*
            // follows the guidance (issue #77, ADR-0023).
            transport(recording)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The lane's height, floor and cap. The floor keeps a short window from crushing the waveform
    /// to a line; the cap is what stops a tall one from stretching it into a smear (issue #77).
    static let laneMinimumHeight: Double = 168
    static let laneMaximumHeight: Double = 340

    /// The transport, in the window's bottom safe area rather than under the lane. Its position no
    /// longer depends on how much the pane above it holds — the reasoning that pinned the
    /// inspector's Export control (issue #76) — and the playhead clock lands where a clock belongs,
    /// as the largest type in the window.
    ///
    /// **No rule and no fill.** It had a hairline `Divider` over a `.bar` material, which is the
    /// shape Apple's own Liquid Glass guidance names: *avoid adding custom darkening backgrounds
    /// behind toolbars*, and glass belongs to the navigation layer, never painted onto content. A
    /// bar earns its separation from air and alignment, not from a rule drawn across the pane.
    /// (`ToolbarItem(placement: .bottomBar)` would be the sanctioned container and is **unavailable
    /// on macOS** — it does not compile.) Nothing here takes glass either: ADR-0019 spends the
    /// app's two Liquid Glass controls on this play button and the Export button, and two is the
    /// rule.
    ///
    /// **This is the one place the Trim's numbers are stated.** They were on the ruler, as a span
    /// bar *and* a readout stacked above a lane that already draws the range — three statements
    /// inside sixty points. Here they sit beside the control that resets them, which is where the
    /// peers put a selection's figures.
    private func transport(_ recording: Recording) -> some View {
        // A Recording whose audio is still arriving has no dependable length and nothing to play
        // (ADR-0021): the lane says so, and the transport must not contradict it.
        let isStillArriving = recorder.isStillArriving(recording)
        return HStack(spacing: Metrics.lg) {
            Button {
                model.player.toggle()
            } label: {
                Image(systemName: model.player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.glass)
            // `buttonBorderShape`, not a `clipShape` over the glass: the style draws its own
            // material and clipping it crops the material rather than reshaping the control.
            .buttonBorderShape(.circle)
            .keyboardShortcut(.space, modifiers: [])
            .help("Plays the Trim, looping")
            // The space shortcut goes inert with the button (ADR-0021).
            .disabled(isStillArriving)

            Text(Format.time(model.player.position, precise: true))
                .font(.system(.largeTitle, design: .monospaced)).monospacedDigit()
                .foregroundStyle(isStillArriving ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                .accessibilityLabel("Playhead")
                .accessibilityValue(Format.time(model.player.position, precise: true))

            Spacer()

            // Nothing is claimed about a Recording whose file is still being written: the lane
            // already says why, and a Trim over a length that has not been read yet is a
            // confident statement of a number nobody has (issue #80).
            if !isStillArriving {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(recording.isTrimmed ? recording.trimRangeText
                                             : Format.time(recording.duration))
                        .font(Metrics.readout)
                    Text(recording.isTrimmed ? "Trim" : "Whole Recording")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(recording.isTrimmed ? "Trim" : "Length")
                .accessibilityValue(recording.isTrimmed ? recording.trimRangeText
                                                        : Format.time(recording.duration))

                // Reset keeps its place beside the figure it undoes. It is `.borderless` with a
                // glyph rather than a blue `.link`: a link reads as navigation, and this is the
                // only destructive-ish control in the bar.
                Button {
                    recording.resetTrim()
                } label: {
                    Label("Reset Trim", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .help("Restores the Trim to the whole Recording")
                // Kept in the layout when there is nothing to reset, so the bar does not reflow
                // the moment a Trim is set or cleared.
                .disabled(!recording.isTrimmed)
                .opacity(recording.isTrimmed ? 1 : 0.25)
            }
        }
        .padding(.horizontal, Metrics.xl)
        .padding(.vertical, Metrics.md)
    }
}

// MARK: - The brief

/// What this master **is**, and where it came from — the space below the lane, filled with the
/// app's own data rather than with chrome (issue #77, ADR-0023).
///
/// It states nothing the Export inspector states. Length, Trim, Quality, the Loudness correction,
/// Gain and the estimated size are all the inspector's, and a window that says the same fact in two
/// panes is a window disagreeing with itself. What had no home anywhere was the master's provenance
/// and shape, which is the one thing here.
///
/// **There is no loudness figure, and that is ADR-0013's doing, not an omission.** The obvious
/// filler — *measures −21.4 LUFS, corrected to −16.0 at Export* — is forbidden in as many words:
/// the figure shown is always dB, and the measured LUFS is never shown to the user. The correction
/// in dB is already an inspector row, so there is nothing left for this block to add.
private struct RecordingBrief: View {
    var recording: Recording
    @State private var recorder = RecordingController.shared

    private var isStillArriving: Bool { recorder.isStillArriving(recording) }

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline,
             horizontalSpacing: Metrics.lg,
             verticalSpacing: Metrics.sm) {
            row("Source", recording.source)
            row("Captured", recording.recordedAt?.formatted(date: .long, time: .shortened) ?? "—")
            row("Format", formatText)
            // A file still being written has a byte count that is already out of date, and
            // ADR-0021 is the whole record of what that costs. An em dash rather than a stale
            // number — and rather than a missing row, which would change the pane's height.
            row("Master", isStillArriving ? "—"
                        : recording.openedByteCount?.formatted(.byteCount(style: .file)) ?? "—")
            // Seams were a separate line under the lane, present only for Recordings that have
            // any. That made the pane two different heights, and the lane above it took up the
            // slack — so arrowing down the Library resized the waveform on every keystroke. It is
            // a fact about the master like the four above it, so it is a row like them, and it is
            // always here (ADR-0010, ADR-0023).
            seamRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var seamRow: some View {
        GridRow {
            Text("Seams")
                .font(Metrics.metadata)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            Group {
                if let summary = recording.seamSummary {
                    HStack(spacing: Metrics.xs) {
                        Image(systemName: "rectangle.dashed").foregroundStyle(.tertiary)
                        Text(summary)
                    }
                } else {
                    Text("None").foregroundStyle(.secondary)
                }
            }
            .font(Metrics.metadata)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Seams")
        .accessibilityValue(recording.seamSummary.map { String(localized: $0) } ?? "None")
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        GridRow {
            Text(label)
                .font(Metrics.metadata)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            Text(value)
                .font(Metrics.metadata)
        }
        // Each row states its own label and value. `.combine` collapses a two-`Text` row into one
        // element and drops the value with it — measured on the inspector's rows, which kept their
        // label and had no `AXValueDescription` at all (issue #76).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    /// `48 kHz · Stereo · 32-bit float`. The captured master is Float32 (ADR-0003); an adopted file
    /// states its own depth, so "float" is claimed only where it is true.
    private var formatText: String {
        let format = recording.sourceFormat
        let rate = (format.sampleRate / 1000).formatted(.number.precision(.fractionLength(0...1)))
        let channels = switch format.channelCount {
        case 1: "Mono"
        case 2: "Stereo"
        default: "\(format.channelCount) channels"
        }
        let depth = format.bitsPerChannel == 32 ? "32-bit float" : "\(format.bitsPerChannel)-bit"
        return "\(rate) kHz · \(channels) · \(depth)"
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

    /// Whether this row is the selected one. macOS fills a selected sidebar row with the user's
    /// accent at full saturation and turns `.primary` content white for you — but it does nothing
    /// for content that names its own colour, which is most of this row (ADR-0023).
    private var isSelected: Bool { model.selection?.url == recording.url }

    var body: some View {
        Group {
            if isRenaming { renameField } else { content }
        }
        .frame(height: 32)
        // Not drawn under the name field: the silhouette is a comparison aid for browsing, and
        // behind editable text it is just noise.
        //
        // Nor under the **selected** row. Over a saturated accent fill the silhouette stops being
        // a comparison aid and becomes texture on the one row that least needs it — the selected
        // Recording's waveform is drawn full size two panes to the right. Dropping it is most of
        // what made the selection read as hard rather than elegant (issue #77, ADR-0023).
        .background(alignment: .leading) {
            if !isRenaming, !isSelected, recording.isOpenable { silhouette }
        }
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
                // `.tertiary` is a legible grey on the window background and very nearly invisible
                // on a saturated selection fill. A selected row gets one rung brighter.
                .foregroundStyle(isSelected ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
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
                    // Indigo on the accent fill is indigo on blue: the glyph vanished on exactly
                    // the row the user is looking at. Selected, it takes `.primary`, which macOS
                    // renders white on a focused selection and dark on an unfocused one — the
                    // behaviour Mail's VIP star and Finder's tag dots already have. ADR-0019's
                    // where-`Signal`-may-appear list is unchanged in substance: this is still the
                    // scissors' colour, it simply yields where contrast would otherwise be lost.
                    Image(systemName: "scissors")
                        .font(.caption2)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.primary)
                                                    : AnyShapeStyle(Palette.signal))
                }

                // A subtle trailing glyph on Recordings with surfaced Seams — the Library is where a
                // user arrives weeks later, when the moment's telling is long gone (ADR-0010). Tertiary,
                // not tinted: it is *no data here*, not a warning.
                if recording.isSurfacedForSeams {
                    Image(systemName: "rectangle.dashed")
                        .font(.caption2)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.secondary)
                                                    : AnyShapeStyle(.tertiary))
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
