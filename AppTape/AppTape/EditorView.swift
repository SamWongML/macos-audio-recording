import AppKit
import SwiftUI

/// The editor window: three columns — the Library as a leading sidebar, the waveform and Trim in
/// the middle, and a permanently-visible trailing Export inspector (variant Q with the
/// "permanent inspector" pane treatment). It has **exactly one pane control**, the system sidebar
/// toggle `NavigationSplitView` installs for free on the leading edge, so there is nothing to
/// mirror on the trailing edge; `SidebarCommands`/`InspectorCommands` are deliberately not
/// added (they left the app with zero windows — ), and the title bar drops its
/// toolbar background so the waveform reads to the window's edge.
struct EditorView: View {
    /// The editor's one coordinator, accepted rather than reached for: the store, the
    /// selection, playback, and the two Export objects the trailing column renders.
    var model: EditorModel
    /// What capture is doing. Accepted, not reached for, and this window is the one
    /// surface that passes it on: the transport reads it here, and the lane, the brief, the sidebar
    /// row and the Export dock are each handed it below.
    var capture: any CaptureState
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool
    /// Whether the Library list holds the window's keyboard focus. Written, not just read:
    /// picking a row is what puts focus here.
    @FocusState private var isSidebarFocused: Bool
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    /// The editor honours these itself; only `PanelView` used to. Reduce
    /// Motion rides the token set's `.motion(_:value:)` helper rather than being read here.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// The Recordings the sidebar is actually showing. Named, rather than filtered inline, because
    /// the footer counts it too: it used to count `store.recordings`, so a query matching nothing
    /// left an empty list under the words `44 Recordings`.
    private var matches: [Recording] {
        model.store.recordings.filter {
            query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.name.localizedCaseInsensitiveContains(query)
        }
    }

    private var days: [RecordingDay] { RecordingDay.group(matches) }

    /// Whether the Library holds anything at all — *not* whether the query matched. The detail's
    /// empty state asks this; `matches` is the sidebar's business.
    private var hasRecordings: Bool { !model.store.recordings.isEmpty }

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
            // window rather than hold a stale one.
            dismissWindow(id: AppTapeApp.editorWindowID)
        }
        .editorActivationPolicy(cancelling: model.coordinator)
    }

    // MARK: - Sidebar (the Library)

    /// **No animation scope here, deliberately**. A Recording arriving in the Library
    /// does not slide in: the Library is a view of a folder, and a row animating its own
    /// arrival claims the app did something when the folder merely changed. The same reasoning
    /// covers a row leaving on a Move to Trash and a row re-sorting after a rename.
    private var sidebar: some View {
        List(selection: selectionBinding) {
            ForEach(days) { day in
                Section(day.title) {
                    ForEach(day.recordings) { recording in
                        LibraryRow(recording: recording, model: model, capture: capture)
                            .tag(recording.url)
                    }
                }
            }
        }
        // The two selection fills are **macOS's, and both are correct**: the accent while this
        // list is the key window's first responder, a mid grey when it is not. What
        // was wrong was the focus, not the fill — see `selectionBinding`.
        .focused($isSidebarFocused)
        // **AppKit chooses the window's first key view exactly once, and at the shipped size it
        // chooses before this list exists**. `-[NSWindow
        .onAppear {
            if !isSearchFocused { isSidebarFocused = true }
        }
        // **The query's silence is the sidebar's to explain; the Library's is not**.
        // Issue #73's finding 16 put a `No Recordings` state here, and it was true, but it made
        .overlay {
            if matches.isEmpty && !query.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, placement: .sidebar, prompt: "Recordings")
        .searchFocused($isSearchFocused)
        .onKeyPress(.return) {
            // Return renames the selected row, as it does in a Finder list. Ignored while the
            // search field has focus, where Return means "search", and while a rename is already
            // open, where Return belongs to the field's own submit.
            guard !isSearchFocused, model.renamingURL == nil, let selection = model.selection
            else { return .ignored }
            model.beginRename(selection)
            return .handled
        }
        // Published only while the sidebar itself has focus: this is what gates File ▸ Move to
        // Trash, so ⌘⌫ cannot fire out of the search field or a Trim drag.
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
            // editor was honouring neither of the two.
            .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                                           : AnyShapeStyle(.bar))
        }
    }

    /// Picking a row **moves the keyboard focus into the list**, which macOS would do for you in
    /// an `NSTableView` and SwiftUI's `List` does not: with the sidebar search field focused, a
    /// click selected the row but left first responder in the field, so the row the user was
    /// looking straight at wore the unemphasized grey and ↑/↓ and Return still belonged to the
    /// search. Nothing else in the window released the field — not the
    /// waveform, not the inspector — only Tab or Escape.
    private var selectionBinding: Binding<URL?> {
        Binding(get: { model.selection?.url },
                set: { url in
                    model.select(url.flatMap(model.recording(for:)))
                    isSidebarFocused = true
                })
    }

    // MARK: - Detail (waveform, Trim, transport) + permanent inspector

    /// The trailing pane is an **ordinary column of the detail view, not a SwiftUI `.inspector`**
    ///.
    private var detail: some View {
        HStack(spacing: 0) {
            detailContent
                .frame(maxWidth: .infinity)

            // **No hairline.** The `Divider` that used to be here started below the title bar and
            // ran to the window's bottom edge, and that asymmetry is what read as wrong. Research
            inspectorColumn
                .frame(width: Self.inspectorWidth)
                // Width only, before this. `ExportInspector` stretches so the fill covered the
                // column; `ContentUnavailableView` does not, so with nothing selected the fill
                .frame(maxHeight: .infinity)
                .background {
                    // `ignoresSafeArea` on the *background*, not on the column: the ladder keeps
                    // its inset from the title bar, only the paint goes under it. And a modifier
                    ZStack {
                        Color(nsColor: .controlBackgroundColor)
                        Color.black.opacity(Self.inspectorColumnScrim)
                    }
                    .ignoresSafeArea(edges: .top)
                }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if let recording = model.selection {
            // **The title lives here, above the branch, and that is the fix.** The Library's own
            // name for the Recording, not the filename. The title bar used to read
            Group {
                if recording.isOpenable {
                    editorDetail(recording)
                } else {
                    cantOpenDetail(recording)
                }
            }
            .navigationTitle(recording.displayName)
            .navigationSubtitle(recording.windowSubtitle)
        } else {
            // **The window's one sentence**. Report 0002 found no premium comparison app
            // with a bespoke empty state and Apple's own guidance is the only grounding there is:
            ContentUnavailableView {
                Label(hasRecordings ? "No Recording selected" : "No Recordings",
                      systemImage: "waveform")
            } description: {
                Text(hasRecordings
                     ? "Choose one in the Library to play it, set its Trim, and Export it."
                     : "Record from the AppTape icon in the menu bar.")
            }
        }
    }

    /// The Export ladder, or nothing. **The column never explains itself**: it used to
    /// carry a `Nothing to export` state whose two sentences each repeated the pane beside it —
    /// `Select a Recording in the Library` next to the detail's own `No Recording selected`, and
    /// `AppTape can't decode this file` next to `cantOpenDetail`'s. Every state that has no ladder
    /// already has the detail speaking, so nothing here goes unexplained. Showing a *disabled*
    /// ladder is still wrong for the original reason — it invites a click that can never work.
    @ViewBuilder
    private var inspectorColumn: some View {
        if let recording = model.selection, recording.isOpenable {
            ExportInspector(recording: recording,
                            capture: capture,
                            preference: model.preference,
                            coordinator: model.coordinator,
                            correction: model.correction,
                            player: model.player)
        } else {
            Color.clear
        }
    }

    /// A `public.audio`-typed file the decoder can't open. It is adopted and listed so it
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
    }

    /// Top to bottom: the ruled lane, the **brief**, then air, with the transport in the bottom
    /// safe area.
    @ViewBuilder
    private func editorDetail(_ recording: Recording) -> some View {
        VStack(spacing: 0) {
            TrimTimeline(recording: recording,
                         envelope: recording.envelope,
                         player: model.player,
                         capture: capture,
                         onTrimCommitted: { recording.persistTrim() })
                .frame(minHeight: Self.laneMinimumHeight, maxHeight: Self.laneMaximumHeight)
                .padding(.horizontal, Metrics.xl)
                .padding(.top, Metrics.lg)

            RecordingSummary(recording: recording, capture: capture)
                .padding(.horizontal, Metrics.xl)
                .padding(.top, Metrics.xl)

            Spacer(minLength: Metrics.lg)

            // A plain last child behind the `Spacer`, laid out by hand — only its *appearance*
            // follows the bottom-bar guidance.
            transport(recording)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The trailing pane's width — one number, because the pane neither hides nor resizes. 276 was
    /// the ideal the resizable version defaulted to and the width every screenshot was judged at.
    static let inspectorWidth: Double = 276

    /// How much black is laid over the trailing column's `.controlBackgroundColor` so the column
    /// steps away from the detail pane in **both** appearances. Tuned by measuring the boundary on
    /// screen, not chosen from the palette — see the comment in `detail`.
    static let inspectorColumnScrim: Double = 0.05

    /// The lane's height, floor and cap. The floor keeps a short window from crushing the waveform
    /// to a line; the cap is what stops a tall one from stretching it into a smear.
    static let laneMinimumHeight: Double = 168
    static let laneMaximumHeight: Double = 340

    /// The playhead clock's face. Named because the reserved-width reference below has to be
    /// rendered in exactly it, and a face that drifted from the one the clock draws would reserve
    /// the wrong width silently.
    static let clockFont = Font.system(.largeTitle, design: .monospaced)

    /// **The transport reserves the width of its widest readout instead of sizing to the Recording
    /// in front of it**. It is the same move the bar already made for `Reset`, which is
    /// kept in the layout when there is nothing to reset so the row does not reflow the moment a
    /// Trim is set — and the same one #78 made for the sidebar's fixed-width glyph rail and the
    /// Export dock's four same-height phases.
    static let widestClock = "00:00.00"

    /// The Trim readout's two rows. `trimRangeText` is two `Format.time` figures around an en dash,
    /// so a Recording that ran into hours is the widest it gets. Past ten hours it grows a glyph and
    /// the reservation is one character short — a disclosed limit, not an oversight: reserving for
    /// a capture nobody will make would spend the bar's width on air.
    static let widestTrimRange = "9:59:59 – 9:59:59"
    static let widestTrimCaption = "Whole Recording"

    /// The transport, pinned to the bottom of the detail pane rather than sitting under the lane.
    /// Its position no longer depends on how much the pane above it holds — the reasoning that
    /// pinned the inspector's Export control — and the playhead clock lands where a
    /// clock belongs, as the largest type in the window.
    private func transport(_ recording: Recording) -> some View {
        // A Recording whose audio is still arriving has no dependable length and nothing to play
        //: the lane says so, and the transport must not contradict it.
        let isStillArriving = capture.isStillArriving(recording)
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
            // The space shortcut goes inert with the button.
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

            // **The trailing group is one group, whatever it is saying**.
            //
            if !isStillArriving || capture.isCapturing(recording) {
                let capturing = capture.isCapturing(recording)
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
                        // `Format.time`, **not** `RecordingController.elapsedText`. The menu bar's
                        // clock is `mm:ss` zero-padded (`00:27`) and every figure in the editor is
                        Text(capturing ? Format.time(capture.elapsed)
                                       : recording.isTrimmed ? recording.trimRangeText
                                                             : Format.time(recording.duration))
                            .font(Metrics.readout)
                            .lineLimit(1)
                        Text(capturing ? "Capturing"
                                       : recording.isTrimmed ? "Trim" : "Whole Recording")
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(capturing ? "Captured so far"
                                              : recording.isTrimmed ? "Trim" : "Length")
                .accessibilityValue(capturing ? Format.time(capture.elapsed)
                                              : recording.isTrimmed ? recording.trimRangeText
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
                // Kept in the layout when there is nothing to reset — which now includes the whole
                // capture, when there is no Trim to reset yet — so the bar does not reflow the
                // moment a Trim is set or cleared, nor the moment the capture ends.
                .disabled(capturing || !recording.isTrimmed)
                .opacity(!capturing && recording.isTrimmed ? 1 : 0.25)
            }
        }
        .padding(.horizontal, Metrics.xl)
        .padding(.vertical, Metrics.md)
    }
}

// MARK: - The brief

/// What this master **is**, and where it came from — the space below the lane, filled with the
/// app's own data rather than with chrome.
private struct RecordingSummary: View {
    var recording: Recording
    /// Accepted from the window. The brief asks it for the growing master's figure and
    /// for whether there is a dependable one to state at all.
    var capture: any CaptureState

    private var isStillArriving: Bool { capture.isStillArriving(recording) }

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline,
             horizontalSpacing: Metrics.lg,
             verticalSpacing: Metrics.sm) {
            row("Source", recording.source)
            row("Captured", recording.recordedAt?.formatted(date: .long, time: .shortened) ?? "—")
            row("Format", formatText)
            // A file still being written has a byte count that is already out of date, and
            // is the whole record of what that costs. An em dash rather than a stale
            row("Master", masterText)
            // Dropouts were a separate line under the lane, present only for Recordings that have
            // any. That made the pane two different heights, and the lane above it took up the
            dropoutRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The master's size, current while it is being written.
    private var masterText: String {
        if capture.isCapturing(recording) {
            let size = capture.masterByteCount?.formatted(.byteCount(style: .file))
            return size.map { "\($0) and growing" } ?? "—"
        }
        if isStillArriving { return "—" }
        return recording.openedByteCount?.formatted(.byteCount(style: .file)) ?? "—"
    }

    private var dropoutRow: some View {
        GridRow {
            Text("Dropouts")
                .font(Metrics.metadata)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            Group {
                if let summary = recording.dropoutSummary {
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
        .accessibilityLabel("Dropouts")
        .accessibilityValue(recording.dropoutSummary.map { String(localized: $0) } ?? "None")
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
        // label and had no `AXValueDescription` at all.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    /// `48 kHz · Stereo · 32-bit float`. The captured master is Float32; an adopted file
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
/// for thirty-nine rows at once and read for one; the fix was to remove, not to arrange.
private struct LibraryRow: View {
    var recording: Recording
    var model: EditorModel

    @FocusState private var isEditing: Bool
    @State private var draft = ""
    @State private var blocker: LibraryLocation.NameValidationError?
    /// The row asks whether it is the one capturing, as the lane, the transport and the inspector
    /// already do — accepted from the window, like `model` above it.
    var capture: any CaptureState

    private var isRenaming: Bool { model.renamingURL == recording.url }

    private var isCapturing: Bool { capture.isCapturing(recording) }
    private var isStillArriving: Bool { capture.isStillArriving(recording) }

    /// Whether this row is the selected one. A selected sidebar row is filled by macOS — with the
    /// accent at full saturation while the sidebar has focus, with a mid grey when it does not —
    /// and `.primary` content is inverted for you on both. What macOS does *not* do is touch
    /// content that names its own colour, which is most of this row, so every colour below has to
    /// survive **two** fills rather than one.
    private var isSelected: Bool { model.selection?.url == recording.url }

    var body: some View {
        Group {
            if isRenaming { renameField } else { content }
        }
        .frame(height: Metrics.sidebarRowHeight)
        // Not drawn under the name field: the silhouette is a comparison aid for browsing, and
        // behind editable text it is just noise.
        .background(alignment: .leading) {
            if !isRenaming, recording.isOpenable, !isStillArriving { rowWaveform }
        }
        .contextMenu {
            // Exactly three. `Duplicate` is out of scope: a master is 1.4 GB/hour
            //, and a second Trim over one master has nowhere to live under.
            RenameButton()
            Button("Reveal in Finder") { model.reveal(recording) }
            Divider()
            // No confirm sheet — the Trash is the confirmation.
            Button("Move to Trash", role: .destructive) { model.trash(recording) }
        }
        // Feeds `RenameButton` above, and is why the menu item needs no action of its own.
        .renameAction { model.beginRename(recording) }
    }

    private var content: some View {
        HStack(spacing: 8) {
            // The Source until the user names the Recording themselves, their name after
            // — otherwise a rename would change nothing the Library shows.
            Text(recording.displayName)
                .font(Metrics.name)
                .lineLimit(1)
                .foregroundStyle(recording.isOpenable ? AnyShapeStyle(.primary)
                                                      : AnyShapeStyle(.secondary))
                .fixedSize()

            Spacer(minLength: 12)

            if recording.isOpenable {
                // A **fixed-width slot**, so the durations line up down the column whether a
                // Recording is trimmed, has Dropouts, or neither. The glyphs are drawn at zero opacity
                HStack(spacing: 3) {
                    // `Signal` is indigo, and a focused selection fill is the accent blue: indigo on
                    // blue, so the glyph vanished on exactly the row being looked at. It fares no
                    Image(systemName: "scissors")
                        .foregroundStyle(isSelected ? AnyShapeStyle(.primary)
                                                    : AnyShapeStyle(Palette.signal))
                        .opacity(recording.isTrimmed ? 1 : 0)
                        .accessibilityHidden(!recording.isTrimmed)
                        .help(recording.isTrimmed ? "Trimmed" : "")

                    // A subtle trailing glyph on Recordings with surfaced Dropouts — the Library is
                    // where a user arrives weeks later, when the moment's telling is long gone
                    //. Tertiary, not tinted: it is *no data here*, not a warning.
                    Image(systemName: "rectangle.dashed")
                        .foregroundStyle(isSelected ? AnyShapeStyle(.secondary)
                                                    : AnyShapeStyle(.tertiary))
                        .opacity(recording.isSurfacedForDropouts ? 1 : 0)
                        .accessibilityHidden(!recording.isSurfacedForDropouts)
                        .help(recording.isSurfacedForDropouts
                              ? "Contains Dropouts — silence padded in where audio was interrupted" : "")
                }
                .font(.caption2)
                .frame(width: 26, alignment: .trailing)

                // **The capturing row counts up**. `recording.duration` is the frame
                // count read when the file was last listed, and the folder is not re-listed while
                Text(Format.time(isCapturing ? capture.elapsed : recording.duration))
                    .font(Metrics.metadata).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            } else {
                // A `public.audio`-typed file the decoder can't open: listed so it
                // doesn't vanish, but marked so the user knows why it won't play — no duration, no
                Text("\(recording.url.pathExtension.uppercased()) · Can't open")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .help("An audio file AppTape can't decode. Select it to remove it.")
            }
        }
    }

    /// The name field, in the row rather than in a sheet — a rename is a file rename,
    /// and Finder is the idiom the user already has for it. It takes focus as it appears, commits
    /// on Return, reverts on Escape, and on a name the Library refuses it stays open with what was
    /// typed still in it, saying why.
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
            .onChange(of: draft) { blocker = nil }
            .onChange(of: isEditing) { _, focused in
                // Focus left the field — another row, or the window. Finder commits here; a name
                // it would refuse is abandoned instead, because there is no longer a field to hold
                // open and a popover over a row the user has left is noise.
                if !focused, isRenaming { commit(keepingFocus: false) }
            }
            .popover(isPresented: blockerPresented, arrowEdge: .trailing) {
                Text(blocker?.message ?? "")
                    .font(.callout)
                    // Wraps rather than truncates: the reason is the whole point of the popover,
                    // and a name long enough to collide is long enough to overflow one line.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 240, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
    }

    private var blockerPresented: Binding<Bool> {
        Binding(get: { blocker != nil }, set: { if !$0 { blocker = nil } })
    }

    private func commit(keepingFocus: Bool) {
        switch model.rename(recording, to: draft) {
        case .unchanged, .rename:
            model.endRename()
        case .refused(let why):
            guard keepingFocus else { model.endRename(); return }
            blocker = why
            isEditing = true
        }
    }

    /// Behind the row, in the window the name and the trailing rail leave between them.
    private var rowWaveform: some View {
        WaveformPath(columns: recording.envelope.columns(
            over: TimelineGeometry.wholeRange(duration: recording.duration), count: 120))
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
    /// gates File ▸ Move to Trash on it: Rename and Reveal are harmless from anywhere,
    /// but ⌘⌫ moves a file to the Trash, and firing that out of a search field the user is typing
    /// into is the one outcome worth spending a focus value on.
    @Entry var librarySidebarRecording: URL?
}

// `#if DEBUG`, as `PreviewFixtures.swift` is: a preview body is compiled in Release too, so a fixture
// that does not ship has to be guarded where it is used as well as where it is defined.
#if DEBUG

/// The whole editor, over a Library that does not exist. It used to be `EditorView`, which bound to
/// `EditorModel.shared` and `RecordingController.shared` and therefore listed whatever was in the real
/// Library folder and opened Core Audio to do it.
#Preview("Editor · empty") {
    EditorView(model: .preview(recordings: []), capture: PreviewCapture.settled)
}

/// The two states of the brief's `Master` row that is about, neither of which could be seen
/// before the brief accepted its capture state: a settled Recording states the length it was read at,
/// and the one being written states what it weighs right now.
#Preview("Brief · settled") {
    RecordingSummary(recording: .stub(), capture: PreviewCapture.settled)
        .frame(width: 420)
        .padding(Metrics.xl)
}

#Preview("Brief · capturing") {
    let recording = Recording.stub(seconds: 93)
    return RecordingSummary(recording: recording, capture: PreviewCapture.capturing(recording))
        .frame(width: 420)
        .padding(Metrics.xl)
}

#endif
