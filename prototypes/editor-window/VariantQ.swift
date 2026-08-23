//  PROTOTYPE — Variant Q: O's inspector with N's sidebar.
//
//  Asked for after O won on its inspector and lost on its Library: a toolbar popover is fine
//  at four Recordings and useless at twenty-eight. So the Library becomes a real sidebar and
//  the window has three columns.
//
//  The design question that raises — a leading sidebar toggle and a trailing inspector
//  toggle reading as two mirrored twins — is researched in
//  `docs/research/sidebar-and-inspector.md` on branch `research/sidebar-inspector`.
//  The `PaneControls` axis below is that research's three answers, so they can be compared
//  rather than argued about.

import SwiftUI

/// How the window lets you show and hide its two panes.
enum PaneControls: String, CaseIterable, Identifiable {
    /// The recommendation. The sidebar is the only toggleable pane, so there is exactly one
    /// pane control in the window — the system's own, on the leading edge where the HIG's
    /// Toolbars page puts it. Nothing to mirror, because there is no second control.
    case permanentInspector
    /// The runner-up, and Xcode 27's actual shape: both panes toggle, at opposite edges, but
    /// the two controls are deliberately *not* the same kind of thing. Here the trailing one
    /// is not a pane glyph at all — it is a labelled Export button, which is what the panel
    /// actually is.
    case asymmetricPair
    /// Neither pane gets a toolbar button; both live on View-menu items and their shortcuts.
    /// The HIG names a toolbar button and a menu command as alternatives, not a pair.
    case menuOnly

    var id: Self { self }
    var title: String {
        switch self {
        case .permanentInspector: "Permanent inspector"
        case .asymmetricPair: "Asymmetric pair"
        case .menuOnly: "Menu only"
        }
    }
    var blurb: String {
        switch self {
        case .permanentInspector:
            "One pane control, the system's, on the leading edge. Export never hides, so the size estimate is always live while you trim."
        case .asymmetricPair:
            "Both panes toggle. The trailing control is a labelled Export button, not a mirrored pane glyph."
        case .menuOnly:
            "No pane buttons at all. View ▸ Show Sidebar (⌃⌘S) and View ▸ Show Inspector."
        }
    }
}

struct VariantQ: View {
    var editor: Editor
    @State private var query = ""

    private var days: [RecordingDay] {
        Library.grouped(editor.recordings.filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
        })
    }

    var body: some View {
        NavigationSplitView(columnVisibility: Bindable(editor).sidebarVisibility) {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: selectionBinding) {
            ForEach(days) { day in
                Section(day.title) {
                    ForEach(day.recordings) { recording in
                        LibraryRowQ(recording: recording)
                            .tag(recording.url)
                    }
                }
            }
        }
        .modifier(RemoveSidebarToggle(active: editor.paneControls == .menuOnly))
        .searchable(text: $query, placement: .sidebar, prompt: "Recordings")
        .navigationSplitViewColumnWidth(min: 232, ideal: 268, max: 360)
        .safeAreaInset(edge: .bottom) {
            // Nothing critical lives down here: the HIG's Sidebars page warns that people
            // relocate windows in ways that hide the bottom edge.
            HStack {
                Text("^[\(editor.recordings.count) Recording](inflect: true)")
                Spacer()
                Button("Reveal", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Library.folder])
                }
                .buttonStyle(.borderless)
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(.bar)
        }
    }

    private var selectionBinding: Binding<URL?> {
        Binding(get: { editor.selection?.url },
                set: { url in editor.select(url.flatMap(editor.recording(for:))) })
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let recording = editor.selection {
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
            .toolbar { paneToolbar }
            .inspector(isPresented: inspectorBinding) {
                ExportInspector(recording: recording, settings: editor.settings)
                    .inspectorColumnWidth(min: 248, ideal: 276, max: 340)
            }
        } else {
            ContentUnavailableView("No Recording selected", systemImage: "waveform")
        }
    }

    /// Under `.permanentInspector` the panel is not hideable at all — its estimated size has
    /// to stay live while a Trim handle moves, which is the whole reason it sits beside the
    /// waveform instead of behind a button.
    private var inspectorBinding: Binding<Bool> {
        editor.paneControls == .permanentInspector
            ? .constant(true)
            : Bindable(editor).showsInspector
    }

    @ToolbarContentBuilder
    private var paneToolbar: some ToolbarContent {
        switch editor.paneControls {
        case .permanentInspector:
            // Deliberately empty. The leading edge already carries the sidebar toggle that
            // NavigationSplitView installs for free, and that is the only pane in the window
            // that hides.
            ToolbarItem(placement: .primaryAction) { EmptyView() }
        case .asymmetricPair:
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation { editor.showsInspector.toggle() }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                // Icon-only, the two ends render as identical circular glass capsules and the
                // "don't mirror them" advice is unreachable — plain SwiftUI toolbar items give
                // no way to reproduce Xcode's shape difference. A visible label is the one
                // differentiator left.
                .labelStyle(.titleAndIcon)
                .help(editor.showsInspector ? "Hide the Export panel" : "Show the Export panel")
            }
        case .menuOnly:
            ToolbarItem(placement: .primaryAction) { EmptyView() }
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
}

/// `.toolbar(removing:)` only takes `ToolbarDefaultItemKind`, whose entire set is
/// `sidebarToggle`, `title` and `search` — there is no inspector member, because
/// `.inspector()` never adds a button to remove.
private struct RemoveSidebarToggle: ViewModifier {
    var active: Bool
    func body(content: Content) -> some View {
        if active { content.toolbar(removing: .sidebarToggle) } else { content }
    }
}

// MARK: - The sidebar row

/// One line, 32 points. The Recording's own silhouette runs behind the row, but it is
/// **masked away from both ends** — it fades in past the text and out again before the
/// duration — so nothing is ever drawn under a glyph and nothing has to be truncated to make
/// room for it.
///
/// Two earlier passes are worth recording, because each failed for a different reason:
///
/// - **Waveform behind the whole row**, the construction issue #6 settled for the menu bar
///   panel. That panel's rows are almost all waveform with one small glyph; a Library row
///   carries a Source, a time and a duration, and "Google Chrome 21:51 ✂" sitting on a loud
///   waveform is just noisy.
/// - **Waveform in a fixed 68-point lane**, N's shape. In a 268-point sidebar the lane plus
///   the duration plus the spacing left under 100 points for the text, and every Source
///   truncated: "QuickTim…", "Goo…", "Spoti…".
///
/// The mask keeps the waveform's drawn region at a fixed *fraction* of the row, so two
/// Recordings' silhouettes stay comparable — which is the only reason it is here, given that
/// Sources repeat several times a day.
private struct LibraryRowQ: View {
    var recording: Recording

    var body: some View {
        HStack(spacing: 7) {
            Text(recording.source)
                .lineLimit(1)

            Text(recording.recordedAt?.formatted(date: .omitted, time: .shortened) ?? "")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .layoutPriority(-1)

            Spacer(minLength: 0)

            if recording.isTrimmed {
                Image(systemName: "scissors")
                    .font(.caption2)
                    .foregroundStyle(.tint)
            }

            Text(Format.time(recording.duration))
                .font(.caption).monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(height: 32)
        .background(alignment: .leading) { silhouette }
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

// MARK: - The inspector

/// Unchanged from variant O except that it is now a type of its own, because two variants
/// use it. What it holds is #9's; the Level block is #25's and inert.
struct ExportInspector: View {
    var recording: Recording
    var settings: ExportSettings

    var body: some View {
        Form {
            Section("Quality Preset") {
                PresetPicker(recording: recording, settings: settings, style: .list)
                    .listRowInsets(EdgeInsets())
            }
            Section("Level") {
                LevelControlsStub(settings: settings)
            }
            Section {
                LabeledContent("Estimated size") {
                    Text(recording.estimateText(settings.preset))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                LabeledContent("Length") {
                    Text(Format.time(recording.trimmedDuration)).monospacedDigit()
                }
                Button("Export…") { settings.run(recording) }
                    .buttonStyle(.glassProminent)
                    .frame(maxWidth: .infinity)
                    .keyboardShortcut("e")
            }
        }
        .formStyle(.grouped)
        .animation(.default, value: recording.trimmedDuration)
    }
}
