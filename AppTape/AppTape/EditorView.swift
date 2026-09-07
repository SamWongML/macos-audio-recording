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
    /// Whether the Library list holds the window's keyboard focus. Written, not just read:
    /// picking a row is what puts focus here (issue #95).
    @FocusState private var isSidebarFocused: Bool
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

    /// **No animation scope here, deliberately** (ADR-0028). A Recording arriving in the Library
    /// does not slide in: the Library is a view of a folder (ADR-0006), and a row animating its own
    /// arrival claims the app did something when the folder merely changed. The same reasoning
    /// covers a row leaving on a Move to Trash and a row re-sorting after a rename.
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
        // The two selection fills are **macOS's, and both are correct**: the accent while this
        // list is the key window's first responder, a mid grey when it is not (ADR-0029). What
        // was wrong was the focus, not the fill — see `selectionBinding`.
        .focused($isSidebarFocused)
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

    /// Picking a row **moves the keyboard focus into the list**, which macOS would do for you in
    /// an `NSTableView` and SwiftUI's `List` does not: with the sidebar search field focused, a
    /// click selected the row but left first responder in the field, so the row the user was
    /// looking straight at wore the unemphasized grey and ↑/↓ and Return still belonged to the
    /// search (issue #95, ADR-0029). Nothing else in the window released the field — not the
    /// waveform, not the inspector — only Tab or Escape.
    ///
    /// This setter is the right place because it is only ever driven by the list's own selection
    /// UI: a click or an arrow key. It is not called when a query filters the selected row out of
    /// view, so typing in the search field keeps its focus.
    private var selectionBinding: Binding<URL?> {
        Binding(get: { model.selection?.url },
                set: { url in
                    model.select(url.flatMap(model.recording(for:)))
                    isSidebarFocused = true
                })
    }

    // MARK: - Detail (waveform, Trim, transport) + permanent inspector

    /// The trailing pane is an **ordinary column of the detail view, not a SwiftUI `.inspector`**
    /// (ADR-0024).
    ///
    /// `.inspector` on a `NavigationSplitView` is a broken combination, and the evidence is not
    /// ours alone: FB20061521 (*abnormal Sidebar and Columns state*) and FB20061260 (*the sidebar
    /// toggle disappears when the sidebar is collapsed*) were filed in September 2025, still
    /// reproduce on macOS 26.2 RC, have no Apple reply and no published workaround — and the
    /// reporter's own conclusion is the one issue #85 reached independently by bisection: *the bug
    /// only occurs if the inspector modifier is present; removing it resolves the issue.*
    ///
    /// Three symptoms in this app were that one bug wearing three costumes: the toggle flickering
    /// into the toolbar for a frame while the leading sidebar animated; the leading sidebar
    /// collapsing and returning when the trailing pane was shown; and the editor aborting in
    /// `_NSViewLayout` under any constraint it could not satisfy — too little width, too little
    /// height, or a bottom safe-area bar (issue #85).
    ///
    /// **The column is permanent and it is one fixed width.** `.inspector` gave a toggle and a
    /// drag-to-resize divider for free, and an earlier pass in this branch rebuilt both by hand
    /// once the modifier was gone. Neither is here now: issue #7's *permanently-visible inspector*
    /// and *exactly one pane control* both stand, reached by a different mechanism. What the pane
    /// holds is the Export ladder and the empty state that explains its absence — nothing a window
    /// this size needs to put away, and a hideable pane is a second pane control, a stored
    /// preference and an animation bought for that.
    private var detail: some View {
        HStack(spacing: 0) {
            detailContent
                .frame(maxWidth: .infinity)

            // **No hairline.** The `Divider()` that used to be here started below the title bar and
            // ran to the window's bottom edge, and that asymmetry is what read as wrong. Research
            // report 0006 found the hairline is not the norm at all: Xcode's inspector boundary is a
            // material shift reaching the literal top edge, and Finder's preview column has no
            // boundary drawn whatsoever — the panes are told apart by background colour. So the
            // column takes `.controlBackgroundColor`, one step off the window's own background, and
            // where a line should start and stop stops being a question (#78).
            // `.toolbarBackgroundVisibility(.hidden)` is untouched by this.
            inspectorColumn
                .frame(width: Self.inspectorWidth)
                .background(Color(nsColor: .controlBackgroundColor))
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

            // A plain last child behind the `Spacer`, laid out by hand — only its *appearance*
            // follows the bottom-bar guidance (issue #77, ADR-0023).
            //
            // `ToolbarItem(placement: .bottomBar)` does not compile on macOS at all, so that
            // route stays closed. The other two, `safeAreaInset(edge: .bottom)` and macOS 26's
            // `safeAreaBar(edge: .bottom)`, used to **abort the app on open** — that was
            // `.inspector` re-entering the layout pass until AppKit threw (issue #85's loop), and
            // `.inspector` is gone (ADR-0024).
            //
            // **Both were measured against this code, and neither aborts any more — and neither is
            // usable.** A bottom safe area is resolved against the **window**, not against the view
            // it is attached to: applied here, the detail lays itself out at the full window width,
            // runs underneath the trailing column, and the column draws on top of it. The bar spans
            // the sidebar and the column too. The sidebar's own `.safeAreaInset` a few lines up
            // works only because a split-view column *is* the window's width there; this pane is
            // one part of a row and never is. So the transport stays hand-laid, for a new reason:
            // not that the idiomatic route crashes, but that it docks to the wrong box (issue #85).
            transport(recording)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // PROTOTYPE (#98): the variant switcher, overlaid on the pane whose lane it changes.
        // Top-trailing rather than bottom-centre: the bottom of this pane is the transport, and
        // the transport's live readout is one of the things being judged.
        .overlay(alignment: .topTrailing) {
            CaptureLaneSwitcher().padding(.trailing, Metrics.xl).padding(.top, 2)
        }
    }

    /// The trailing pane's width — one number, because the pane neither hides nor resizes. 276 was
    /// the ideal the resizable version defaulted to and the width every screenshot was judged at.
    static let inspectorWidth: Double = 276

    /// The lane's height, floor and cap. The floor keeps a short window from crushing the waveform
    /// to a line; the cap is what stops a tall one from stretching it into a smear (issue #77).
    static let laneMinimumHeight: Double = 168
    static let laneMaximumHeight: Double = 340

    /// The playhead clock's face. Named because the reserved-width reference below has to be
    /// rendered in exactly it, and a face that drifted from the one the clock draws would reserve
    /// the wrong width silently.
    static let clockFont = Font.system(.largeTitle, design: .monospaced)

    /// **The transport reserves the width of its widest readout instead of sizing to the Recording
    /// in front of it** (issue #85). It is the same move the bar already made for `Reset`, which is
    /// kept in the layout when there is nothing to reset so the row does not reflow the moment a
    /// Trim is set — and the same one #78 made for the sidebar's fixed-width glyph rail and the
    /// Export dock's four same-height phases.
    ///
    /// Two things were wrong without it. The bar **reflowed under the pointer**: arrowing down the
    /// Library moved `Reset` by the width of the difference between `0:07` and `20:00`, and playing
    /// a long Recording moved it again the moment the clock crossed `10:00` and gained a digit. And
    /// the window's width floor became **content-dependent** — the number below could not be one
    /// number while the row it protects changed width with the file.
    ///
    /// The references are strings, not point values, so the widths stay in the font: a face change
    /// moves them and nothing has to be re-measured by hand.
    ///
    /// `Format.time(_, precise: true)` is `m:ss.ff` below an hour and `h:mm:ss` at or above one, so
    /// it is eight glyphs at its widest either way (`59:59.99`, `99:59:59`) — and the face is
    /// monospaced, so any eight-glyph string reserves the same width.
    static let widestClock = "00:00.00"

    /// The Trim readout's two rows. `trimRangeText` is two `Format.time` figures around an en dash,
    /// so a Recording that ran into hours is the widest it gets. Past ten hours it grows a glyph and
    /// the reservation is one character short — a disclosed limit, not an oversight: reserving for
    /// a capture nobody will make would spend the bar's width on air.
    static let widestTrimRange = "9:59:59 – 9:59:59"
    static let widestTrimCaption = "Whole Recording"

    /// The transport, pinned to the bottom of the detail pane rather than sitting under the lane.
    /// Its position no longer depends on how much the pane above it holds — the reasoning that
    /// pinned the inspector's Export control (issue #76) — and the playhead clock lands where a
    /// clock belongs, as the largest type in the window.
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

            // Reserved rather than sized to the number in front of it: see `widestClock`.
            Text(Self.widestClock)
                .font(Self.clockFont).monospacedDigit()
                // The reservation only holds if the reference cannot itself be squeezed: a bare
                // `Text` is compressible, and an `HStack` short of room shrinks it and then
                // truncates the overlay inside the width it was shrunk to.
                .fixedSize()
                .hidden()
                .overlay(alignment: .leading) {
                    Text(Format.time(model.player.position, precise: true))
                        .font(Self.clockFont).monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(isStillArriving ? AnyShapeStyle(.tertiary)
                                                         : AnyShapeStyle(.primary))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Playhead")
                .accessibilityValue(Format.time(model.player.position, precise: true))

            Spacer()

            // PROTOTYPE (#98), shared by all three variants. The reason this slot was empty was
            // that the *listing's* length is stale — but the engine knows the master's real
            // duration and publishes it at 4 Hz, so while this Recording is the one capturing
            // there is an honest figure to state after all. It takes the same reserved slot as
            // the Trim readout, so the bar does not reflow when the capture ends.
            if recorder.isCapturing(recording) {
                ZStack {
                    Text(Self.widestTrimRange).font(Metrics.readout)
                    Text(Self.widestTrimCaption).font(.caption2)
                }
                .fixedSize()
                .hidden()
                .overlay(alignment: .trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(recorder.elapsedText)
                            .font(Metrics.readout)
                            .lineLimit(1)
                        Text("Capturing")
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Captured so far")
                .accessibilityValue(recorder.elapsedText)
            }

            // Nothing is claimed about a Recording whose file is still being written: the lane
            // already says why, and a Trim over a length that has not been read yet is a
            // confident statement of a number nobody has (issue #80).
            if !isStillArriving {
                // Reserved the same way as the clock, and for the same reason. The two rows carry
                // different fonts, so the reference is a `ZStack` of both — it takes the width of
                // whichever is wider, which for a short Recording is the caption, not the figure.
                ZStack {
                    Text(Self.widestTrimRange).font(Metrics.readout)
                    Text(Self.widestTrimCaption).font(.caption2)
                }
                .fixedSize()
                .hidden()
                .overlay(alignment: .trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(recording.isTrimmed ? recording.trimRangeText
                                                 : Format.time(recording.duration))
                            .font(Metrics.readout)
                            .lineLimit(1)
                        Text(recording.isTrimmed ? "Trim" : "Whole Recording")
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
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
            // PROTOTYPE (#98), shared by all three variants. The em dash was right for the
            // *listing's* byte count, which is out of date the moment it is read — but a bare
            // `stat` of the growing file is current, and re-reading it as the clock ticks makes
            // the row say what the master actually weighs right now. Still an em dash for a file
            // that is merely arriving rather than being captured: nothing is watching that one.
            row("Master", masterText)
            // Seams were a separate line under the lane, present only for Recordings that have
            // any. That made the pane two different heights, and the lane above it took up the
            // slack — so arrowing down the Library resized the waveform on every keystroke. It is
            // a fact about the master like the four above it, so it is a row like them, and it is
            // always here (ADR-0010, ADR-0023).
            seamRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// PROTOTYPE (#98). Reading `recorder.elapsed` first is what makes this recompute: the
    /// `stat` itself is not observable, so the 4 Hz clock is what drives the row.
    private var masterText: String {
        if recorder.isCapturing(recording) {
            let live = recorder.elapsed
            _ = live
            return (Recording.byteCount(of: recording.url)?.formatted(.byteCount(style: .file))
                    ?? "—") + " and growing"
        }
        if isStillArriving { return "—" }
        return recording.openedByteCount?.formatted(.byteCount(style: .file)) ?? "—"
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

/// One line, 32 points: the name, the Recording's own silhouette, and a fixed-width trailing rail
/// of glyphs and duration. **The timestamp is gone** — the day is in the section header above and
/// the exact minute is in the brief two panes to the right, so the row spends its width on the
/// three things that tell two Recordings apart at a glance. The lane crowded because it was drawn
/// for thirty-nine rows at once and read for one; the fix was to remove, not to arrange (ADR-0025).
///
/// The silhouette runs behind the row but is **masked away from both ends** — it fades in past the
/// name and out again before the rail — so nothing is drawn under a glyph and nothing is truncated
/// to make room for it. Drawn as a `WaveformPath` (`Shape`), because a `Canvas` inside a `List` row
/// draws nothing on macOS 27 (issue #7). The mask keeps the waveform's drawn region at a fixed
/// *fraction* of the row, so two Recordings' silhouettes stay comparable — the only reason it is
/// here, given Sources repeat within a day.
private struct LibraryRow: View {
    var recording: Recording
    var model: EditorModel

    @FocusState private var isEditing: Bool
    @State private var draft = ""
    @State private var refusal: LibraryLocation.NameRefusal?
    /// PROTOTYPE (#98): the row asks whether it is the capturing one, as the lane, the transport
    /// and the inspector already do.
    @State private var recorder = RecordingController.shared

    private var isCapturing: Bool { recorder.isCapturing(recording) }

    private var isRenaming: Bool { model.renamingURL == recording.url }

    /// Whether this row is the selected one. A selected sidebar row is filled by macOS — with the
    /// accent at full saturation while the sidebar has focus, with a mid grey when it does not —
    /// and `.primary` content is inverted for you on both. What macOS does *not* do is touch
    /// content that names its own colour, which is most of this row, so every colour below has to
    /// survive **two** fills rather than one (ADR-0023).
    private var isSelected: Bool { model.selection?.url == recording.url }

    var body: some View {
        Group {
            if isRenaming { renameField } else { content }
        }
        .frame(height: Metrics.sidebarRowHeight)
        // Not drawn under the name field: the silhouette is a comparison aid for browsing, and
        // behind editable text it is just noise.
        //
        // It **survives selection**, where ADR-0023 dropped it. Dropping it left the row the user is
        // looking at as the one blank row in the column, with a lone scissors floating in the space
        // the shape used to fill. The fill was never the problem — the *colour* was: `.secondary` at
        // 50% is a mid grey, which is mud on the accent fill and nearly invisible on the grey one.
        // Selected, the shape takes `.primary` at a lower alpha instead, which macOS inverts for
        // both fills (ADR-0025).
        .background(alignment: .leading) {
            if !isRenaming, recording.isOpenable { silhouette }
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
        HStack(spacing: 8) {
            // The Source until the user names the Recording themselves, their name after
            // (ADR-0020) — otherwise a rename would change nothing the Library shows.
            //
            // `fixedSize()` with the `Spacer` below is what stops the name growing into the middle
            // of the row: the silhouette gets the space between them, rather than whatever the
            // longest Source name happens to leave over.
            Text(recording.displayName)
                .font(Metrics.name)
                .lineLimit(1)
                .foregroundStyle(recording.isOpenable ? AnyShapeStyle(.primary)
                                                      : AnyShapeStyle(.secondary))
                .fixedSize()

            Spacer(minLength: 12)

            if recording.isOpenable {
                // A **fixed-width slot**, so the durations line up down the column whether a
                // Recording is trimmed, has Seams, or neither. The glyphs are drawn at zero opacity
                // rather than omitted: an `if` here shifted the duration by the width of a glyph on
                // every row that differed, which is the ragged trailing lane #78 was filed about.
                // Hidden from accessibility when invisible, so VoiceOver does not read a glyph that
                // is not being shown.
                HStack(spacing: 3) {
                    // `Signal` is indigo, and a focused selection fill is the accent blue: indigo on
                    // blue, so the glyph vanished on exactly the row being looked at. It fares no
                    // better on the unfocused grey. Selected, it takes `.primary` — the behaviour
                    // Mail's VIP star and Finder's tag dots already have. ADR-0019's
                    // where-`Signal`-may-appear list is unchanged in substance: this is still the
                    // scissors' colour, it simply yields where contrast would be lost (ADR-0023).
                    Image(systemName: "scissors")
                        .foregroundStyle(isSelected ? AnyShapeStyle(.primary)
                                                    : AnyShapeStyle(Palette.signal))
                        .opacity(recording.isTrimmed ? 1 : 0)
                        .accessibilityHidden(!recording.isTrimmed)
                        .help(recording.isTrimmed ? "Trimmed" : "")

                    // A subtle trailing glyph on Recordings with surfaced Seams — the Library is
                    // where a user arrives weeks later, when the moment's telling is long gone
                    // (ADR-0010). Tertiary, not tinted: it is *no data here*, not a warning.
                    Image(systemName: "rectangle.dashed")
                        .foregroundStyle(isSelected ? AnyShapeStyle(.secondary)
                                                    : AnyShapeStyle(.tertiary))
                        .opacity(recording.isSurfacedForSeams ? 1 : 0)
                        .accessibilityHidden(!recording.isSurfacedForSeams)
                        .help(recording.isSurfacedForSeams
                              ? "Contains Seams — silence padded in where audio was interrupted" : "")
                }
                .font(.caption2)
                .frame(width: 26, alignment: .trailing)

                // PROTOTYPE (#98), shared by all three variants. `recording.duration` is the
                // frame count read when the file was listed, and the folder is **not re-listed
                // while a master grows** — a `DispatchSource` on the directory does not fire for
                // an append — so a capturing row sat at its adoption reading (near `0:00`) until
                // the app was next activated. The engine's own clock is the honest number, and it
                // keeps the column a column of durations.
                Text(isCapturing ? recorder.elapsedText : Format.time(recording.duration))
                    .font(Metrics.metadata).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            } else {
                // A `public.audio`-typed file the decoder can't open (ADR-0015): listed so it
                // doesn't vanish, but marked so the user knows why it won't play — no duration, no
                // silhouette. The extension stays even though the timestamp went: without it a
                // `.wma` and a `.mid` rendered as byte-identical rows and the Library could not tell
                // the user which was which (issue #73, finding 33).
                Text("\(recording.url.pathExtension.uppercased()) · Can't open")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .help("An audio file AppTape can't decode. Select it to remove it.")
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

    /// Behind the row, in the window the name and the trailing rail leave between them.
    ///
    /// On a **selected** row it takes `.primary` at a lower alpha, which macOS renders white on a
    /// focused selection and dark on an unfocused one — so one rule covers both fills. The alpha is
    /// what keeps it a ground: at full strength `.primary` is the name's own colour and the shape
    /// would compete with the text it sits behind (ADR-0025).
    private var silhouette: some View {
        WaveformPath(columns: recording.envelope.columns(
            over: 0...max(recording.duration, 0.001), count: 120))
            .fill(isSelected ? AnyShapeStyle(.primary.opacity(0.30))
                             : AnyShapeStyle(.secondary.opacity(0.5)))
            .frame(height: 15)
            // Opened up from 0.42/0.56/0.80/0.90 now the timestamp has gone: the shape starts where
            // the name ends rather than where the name plus a timestamp ended, and stops before the
            // fixed rail rather than before a ragged one.
            .mask {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.00),
                    .init(color: .clear, location: 0.40),
                    .init(color: .black, location: 0.52),
                    .init(color: .black, location: 0.78),
                    .init(color: .clear, location: 0.88),
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
