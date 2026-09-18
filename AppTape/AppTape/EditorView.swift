import AppKit
import SwiftUI

/// The editor window: the Library as a leading sidebar, the waveform and Trim in the middle,
struct EditorView: View {
    /// The editor's one coordinator: store, selection, playback, and the two Export objects.
    var model: EditorModel
    /// What capture is doing.
    var capture: any CaptureState
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool
    /// Whether the Library list holds the window's keyboard focus. Written as well as read:
    /// picking a row is what puts focus here.
    @FocusState private var isSidebarFocused: Bool
    /// Reduce Motion rides the token set's `.motion(_:value:)` helper rather than being read here.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// The Recordings the sidebar is actually showing.
    private var matches: [Recording] {
        model.store.recordings.filter {
            query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.name.localizedCaseInsensitiveContains(query)
        }
    }

    private var days: [RecordingDay] { RecordingDay.group(matches) }

    /// Whether the Library holds anything at all — *not* whether the query matched.
    private var hasRecordings: Bool { !model.store.recordings.isEmpty }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            // The hidden window-toolbar background is unconditional (the spec asks for it on the
            // title bar, not only when a Recording is shown), so it rides the detail wrapper —
            detail
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Sidebar (the Library)

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
        // The two selection fills are macOS's, and both are correct: the accent while this list
        // is the key window's first responder, a mid grey when it is not.
        .focused($isSidebarFocused)
        // AppKit chooses the window's first key view exactly once, and at the shipped size it
        // chooses before this list exists.
        .onAppear {
            if !isSearchFocused { isSidebarFocused = true }
        }
        .overlay {
            if matches.isEmpty && !query.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, placement: .sidebar, prompt: "Recordings")
        .searchFocused($isSearchFocused)
        .onKeyPress(.return) {
            // Return renames the selected row, as it does in a Finder list.
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
            // Nothing critical lives down here: the HIG's Sidebars page warns that people relocate
            // windows in ways that hide the bottom edge.
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
            // Reduce Transparency: the vibrant `.bar` becomes an opaque window background.
            // `PanelView` has always done.
            .background(
                reduceTransparency
                    ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                    : AnyShapeStyle(.bar))
        }
    }

    /// Picking a row moves keyboard focus into the list, which `List` does not do for you: without
    private var selectionBinding: Binding<URL?> {
        Binding(
            get: { model.selection?.url },
            set: { url in
                model.select(url.flatMap(model.recording(for:)))
                isSidebarFocused = true
            })
    }

    // MARK: - Detail (waveform, Trim, transport) + permanent inspector

    /// The trailing pane is an ordinary column of the detail view, not a SwiftUI `.inspector`.
    private var detail: some View {
        HStack(spacing: 0) {
            detailContent
                .frame(maxWidth: .infinity)

            inspectorColumn
                .frame(width: Self.inspectorWidth)
                .frame(maxHeight: .infinity)
                .background {
                    // `ignoresSafeArea` on the *background*, not on the column: the ladder keeps
                    // its inset from the title bar, only the paint goes under it.
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
            // The Library's own name for the Recording, not the filename.
            Group {
                if recording.isOpenable {
                    editorDetail(recording)
                } else {
                    cantOpenDetail(recording)
                }
            }
            .navigationTitle(recording.displayName)
            .navigationSubtitle(recording.windowSubtitle)
        } else if model.selectionUnavailable {
            ContentUnavailableView(
                "Recording unavailable", systemImage: "waveform",
                description: Text("The selected file is no longer in the Library."))
        } else {
            ContentUnavailableView {
                Label(
                    hasRecordings ? "No Recording selected" : "No Recordings",
                    systemImage: "waveform")
            } description: {
                Text(
                    hasRecordings
                        ? "Choose one in the Library to play it, set its Trim, and Export it."
                        : "Record from the AppTape icon in the menu bar.")
            }
        }
    }

    /// The Export ladder, or nothing.
    @ViewBuilder
    private var inspectorColumn: some View {
        if let recording = model.selection, recording.isOpenable {
            ExportInspector(
                recording: recording,
                capture: capture,
                preference: model.preference,
                coordinator: model.coordinator,
                correction: model.correction,
                player: model.player)
        } else {
            Color.clear
        }
    }

    /// A `public.audio`-typed file the decoder can't open.
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

    /// Top to bottom: the ruled lane, the brief, then air, with the transport in the bottom
    /// safe area.
    @ViewBuilder
    private func editorDetail(_ recording: Recording) -> some View {
        VStack(spacing: 0) {
            TrimTimeline(
                recording: recording,
                envelope: recording.envelope,
                player: model.player,
                capture: capture,
                onTrimCommitted: { recording.persistTrim() }
            )
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

    /// The trailing pane's width — one number, because the pane neither hides nor resizes.
    static let inspectorWidth: Double = 276

    /// How much black is laid over the trailing column's `.controlBackgroundColor` so the column
    /// steps away from the detail pane in both appearances.
    static let inspectorColumnScrim: Double = 0.05

    /// The lane's height, floor and cap. The floor keeps a short window from crushing the waveform
    /// to a line; the cap is what stops a tall one from stretching it into a smear.
    static let laneMinimumHeight: Double = 168
    static let laneMaximumHeight: Double = 340

    /// The playhead clock's face.
    static let clockFont = Font.system(.largeTitle, design: .monospaced)

    /// The transport reserves the width of its widest readout rather than sizing to the Recording.
    /// in front of it.
    static let widestClock = "00:00.00"

    /// The Trim readout's two rows.
    static let widestTrimRange = "9:59:59 – 9:59:59"
    static let widestTrimCaption = "Whole Recording"

    /// The transport, pinned to the bottom of the detail pane rather than sitting under the lane.
    private func transport(_ recording: Recording) -> some View {
        // A Recording whose audio is still arriving has no dependable length and nothing to play:
        // the lane says so, and the transport must not contradict it.
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
                .fixedSize()
                .hidden()
                .overlay(alignment: .leading) {
                    Text(Format.time(model.player.position, precise: true))
                        .font(Self.clockFont).monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(
                            isStillArriving
                                ? AnyShapeStyle(.tertiary)
                                : AnyShapeStyle(.primary))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Playhead")
                .accessibilityValue(Format.time(model.player.position, precise: true))

            Spacer()

            if !isStillArriving || capture.isCapturing(recording) {
                let capturing = capture.isCapturing(recording)
                // Reserved the same way as the clock, and for the same reason.
                ZStack {
                    Text(Self.widestTrimRange).font(Metrics.readout)
                    Text(Self.widestTrimCaption).font(.caption2)
                }
                .fixedSize()
                .hidden()
                .overlay(alignment: .trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        // `Format.time`, not `RecordingController.elapsedText`.
                        Text(
                            capturing
                                ? Format.time(capture.elapsed)
                                : recording.isTrimmed
                                    ? recording.trimRangeText
                                    : Format.time(recording.duration)
                        )
                        .font(Metrics.readout)
                        .lineLimit(1)
                        Text(
                            capturing
                                ? "Capturing"
                                : recording.isTrimmed ? "Trim" : "Whole Recording"
                        )
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    capturing
                        ? "Captured so far"
                        : recording.isTrimmed ? "Trim" : "Length"
                )
                .accessibilityValue(
                    capturing
                        ? Format.time(capture.elapsed)
                        : recording.isTrimmed
                            ? recording.trimRangeText
                            : Format.time(recording.duration))

                // Reset keeps its place beside the figure it undoes.
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
                .disabled(capturing || !recording.isTrimmed)
                .opacity(!capturing && recording.isTrimmed ? 1 : 0.25)
            }
        }
        .padding(.horizontal, Metrics.xl)
        .padding(.vertical, Metrics.md)
    }
}

// MARK: - The brief

/// What this master is and where it came from — the space below the lane.
private struct RecordingSummary: View {
    var recording: Recording
    /// Accepted from the window: the growing master's figure, and whether there is one to state.
    var capture: any CaptureState

    private var isStillArriving: Bool { capture.isStillArriving(recording) }

    var body: some View {
        Grid(
            alignment: .leadingFirstTextBaseline,
            horizontalSpacing: Metrics.lg,
            verticalSpacing: Metrics.sm
        ) {
            row("Source", recording.source)
            row("Captured", recording.recordedAt?.formatted(date: .long, time: .shortened) ?? "—")
            row("Format", formatText)
            // A file still being written has a byte count that is already out of date.
            row("Master", masterText)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    /// `48 kHz · Stereo · 32-bit float`. The captured master is Float32; an adopted file
    /// states its own depth, so "float" is claimed only where it is true.
    private var formatText: String {
        let format = recording.sourceFormat
        let rate = (format.sampleRate / 1000).formatted(.number.precision(.fractionLength(0...1)))
        let channels =
            switch format.channelCount {
            case 1: "Mono"
            case 2: "Stereo"
            default: "\(format.channelCount) channels"
            }
        let depth = format.bitsPerChannel == 32 ? "32-bit float" : "\(format.bitsPerChannel)-bit"
        return "\(rate) kHz · \(channels) · \(depth)"
    }
}

// MARK: - The sidebar row

/// One line, 32 points: the name, the Recording's own waveform, and a fixed-width trailing rail
/// of glyphs and duration.
private struct LibraryRow: View {
    var recording: Recording
    var model: EditorModel

    @FocusState private var isEditing: Bool
    @State private var draft = ""
    @State private var blocker: LibraryLocation.NameValidationError?
    /// Accepted from the window, as the lane, the transport and the inspector already do.
    var capture: any CaptureState

    private var isRenaming: Bool { model.renamingURL == recording.url }

    private var isCapturing: Bool { capture.isCapturing(recording) }
    private var isStillArriving: Bool { capture.isStillArriving(recording) }

    private var isSelected: Bool { model.selection?.url == recording.url }

    var body: some View {
        Group {
            if isRenaming { renameField } else { content }
        }
        .frame(height: Metrics.sidebarRowHeight)
        // Not drawn under the name field: the row waveform is a comparison aid for browsing, and
        // behind editable text it is just noise.
        .background(alignment: .leading) {
            if !isRenaming, recording.isOpenable, !isStillArriving { rowWaveform }
        }
        // The row is what asks for its own waveform: the store lists the folder without reading it.
        .onAppear { EnvelopeLoader.load(recording) }
        .contextMenu {
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
            // The Source until the user names the Recording themselves, their name after —
            // otherwise a rename would change nothing the Library shows.
            Text(recording.displayName)
                .font(Metrics.name)
                .lineLimit(1)
                .foregroundStyle(
                    recording.isOpenable
                        ? AnyShapeStyle(.primary)
                        : AnyShapeStyle(.secondary)
                )
                .fixedSize()

            Spacer(minLength: 12)

            if recording.isOpenable {
                // A fixed-width slot, so the durations line up down the column whether a
                // Recording is trimmed, has Dropouts, or neither.
                HStack(spacing: 3) {
                    // `Signal` is indigo, and a focused selection fill is the accent blue: indigo
                    // on blue, so the glyph vanished on exactly the row being looked at.
                    Image(systemName: "scissors")
                        .foregroundStyle(
                            isSelected
                                ? AnyShapeStyle(.primary)
                                : AnyShapeStyle(Palette.signal)
                        )
                        .opacity(recording.isTrimmed ? 1 : 0)
                        .accessibilityHidden(!recording.isTrimmed)
                        .help(recording.isTrimmed ? "Trimmed" : "")

                    // A subtle trailing glyph on Recordings with surfaced Dropouts — the Library
                    // is where a user arrives weeks later, long after the moment.
                    Image(systemName: "rectangle.dashed")
                        .foregroundStyle(
                            isSelected
                                ? AnyShapeStyle(.secondary)
                                : AnyShapeStyle(.tertiary)
                        )
                        .opacity(recording.isSurfacedForDropouts ? 1 : 0)
                        .accessibilityHidden(!recording.isSurfacedForDropouts)
                        .help(
                            recording.isSurfacedForDropouts
                                ? "Contains Dropouts — silence padded in where audio was interrupted" : "")
                }
                .font(.caption2)
                .frame(width: 26, alignment: .trailing)

                Text(Format.time(isCapturing ? capture.elapsed : recording.duration))
                    .font(Metrics.metadata).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            } else {
                // A `public.audio`-typed file the decoder can't open: listed so it doesn't vanish,
                // but marked so the user knows why it won't play.
                Text("\(recording.url.pathExtension.uppercased()) · Can't open")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .help("An audio file AppTape can't decode. Select it to remove it.")
            }
        }
    }

    /// The name field, in the row rather than a sheet — a rename is a file rename.
    private var renameField: some View {
        TextField("Name", text: $draft)
            .textFieldStyle(.plain)
            .focused($isEditing)
            .onSubmit { commit(keepingFocus: true) }
            .onExitCommand { model.endRename() }
            .onAppear {
                draft = recording.name  // the base name: the extension is never the user's to edit
                isEditing = true
            }
            .onChange(of: draft) { blocker = nil }
            .onChange(of: isEditing) { _, focused in
                // Focus left the field — another row, or the window.
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
        WaveformPath(
            columns: recording.envelope.columns(
                over: TimelineGeometry.wholeRange(duration: recording.duration), count: 120)
        )
        .fill(
            isSelected
                ? AnyShapeStyle(.primary.opacity(0.30))
                : AnyShapeStyle(.secondary.opacity(0.5))
        )
        .frame(height: 15)
        .mask {
            LinearGradient(
                stops: [
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
    /// The Library sidebar's selected Recording, published only while the sidebar has focus.
    @Entry var librarySidebarRecording: URL?
}

// `#if DEBUG`, as `PreviewFixtures.swift` is: a preview body is compiled in Release too, so a
// fixture that does not ship has to be guarded where it is used as well as where it is defined.
#if DEBUG

    /// The whole editor, over a Library that does not exist.
    #Preview("Editor · empty") {
        EditorView(model: .preview(recordings: []), capture: PreviewCapture.settled)
    }

    /// The two states of the brief's `Master` row: a settled Recording states the length it was read
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
