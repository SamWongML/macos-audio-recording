//  PROTOTYPE — throwaway app shell for issue #7. Not production code.
//
//  Two axes, because layout and trim precision are independent questions:
//    ⌥← / ⌥→   variant   M Document · N Library split · O Inspector · P Tape deck ·
//                        Q Inspector + sidebar
//    ⌥↑ / ⌥↓   precision Whole · Zoom · Loupe
//  and inside the timeline: ⌘= / ⌘− zoom, [ / ] select the In / Out handle, ← / → nudge it
//  (⇧ for one second a step).
//
//  Modified arrows on purpose — the timeline itself uses plain ← / → to nudge a Trim handle.
//  ⌥ and not ⌃: ⌃← / ⌃→ / ⌃↑ / ⌃↓ are Mission Control's Spaces shortcuts, and the system
//  eats them before an app-local NSEvent monitor ever sees them. Measured, not guessed —
//  the first pass used ⌃ and the whole desktop slid sideways instead.

import AppKit
import SwiftUI

@main
struct EditorWindowPrototypeApp: App {
    @State private var editor = Editor()

    init() { Diag.note("app init"); Diag.start() }

    var body: some Scene {
        Window("Prototype switcher", id: "switcher") {
            Switcher(editor: editor)
        }
        .windowLevel(.floating)
        .windowResizability(.contentSize)
        .defaultPosition(.bottomTrailing)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.presented)

        // N, O and P: one window, forever.
        Window("AppTape", id: "editor") {
            SingleWindowHost(editor: editor)
        }
        .defaultSize(width: 1140, height: 620)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commands { EditorCommands(editor: editor) }

        // M: one window per Recording.
        WindowGroup(id: "doc", for: URL.self) { $url in
            DocumentHost(editor: editor, url: url)
        }
        .defaultSize(width: 820, height: 400)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

    }
}

// MARK: - Hosts

private struct SingleWindowHost: View {
    var editor: Editor

    var body: some View {
        Group {
            switch editor.variant {
            case .n: VariantN(editor: editor)
            case .o: VariantO(editor: editor)
            case .p: VariantP(editor: editor)
            case .q: VariantQ(editor: editor)
            case .m: ContentUnavailableView("M uses document windows", systemImage: "macwindow")
            }
        }
        .tint(.orange)
    }
}

private struct DocumentHost: View {
    var editor: Editor
    var url: URL?

    var body: some View {
        Group {
            if let url, let recording = editor.recording(for: url) {
                VariantM(editor: editor, recording: recording)
                    .onAppear { editor.select(recording) }
            } else {
                ContentUnavailableView("Recording not in the Library", systemImage: "questionmark.folder")
            }
        }
        .tint(.orange)
    }
}

// MARK: - Commands

private struct EditorCommands: Commands {
    var editor: Editor
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // SidebarCommands is macOS 11; InspectorCommands did not arrive until macOS 14 —
        // the same asymmetry that runs through the rest of this API.
        CommandGroup(replacing: .newItem) {
            Button("Open Recording…") { open() }
                .keyboardShortcut("o", modifiers: .command)
            Button("Reveal Library in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([Library.folder])
            }
        }
    }

    /// M's answer to "where is the Library": the system's, pointed at the folder.
    private func open() {
        let panel = NSOpenPanel()
        panel.directoryURL = Library.folder
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        editor.loadLibrary()
        openWindow(id: "doc", value: url)
    }
}

// MARK: - Switcher

/// Deliberately ugly and deliberately in its own floating window, so nothing about it can be
/// mistaken for the design under judgement.
private struct Switcher: View {
    var editor: Editor
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var openDocuments: Set<URL> = []
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(title: "Variant", back: "⌥←", forward: "⌥→",
                label: "\(editor.variant.letter)  \(editor.variant.title)") { step in
                cycle(&editor.variant, by: step)
            }

            Text(editor.variant.claim)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 330, alignment: .leading)

            Divider()

            row(title: "Precision", back: "⌥↑", forward: "⌥↓",
                label: editor.precision.title) { step in
                cycle(&editor.precision, by: step)
            }

            Text(editor.precision.blurb)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 330, alignment: .leading)

            Divider()

            Picker("Recording", selection: Binding(
                get: { editor.selection?.url },
                set: { url in
                    guard let recording = url.flatMap(editor.recording(for:)) else { return }
                    editor.select(recording)
                    if editor.variant.usesDocumentWindows { showDocument(recording.url) }
                })) {
                ForEach(editor.recordings) { recording in
                    Text("\(recording.source) · \(Format.time(recording.duration))")
                        .tag(Optional(recording.url))
                }
            }
            .frame(width: 330)

            if editor.variant == .q {
                Picker("Pane controls", selection: Binding(
                    get: { editor.paneControls }, set: { editor.paneControls = $0 })) {
                    ForEach(PaneControls.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 330)
                Text(editor.paneControls.blurb)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 330, alignment: .leading)
            }

            if editor.precision == .loupe {
                Toggle("Pin the loupe open (it normally lives only while you drag)",
                       isOn: Binding(get: { editor.timeline.loupePinned },
                                     set: { editor.timeline.loupePinned = $0 }))
                    .font(.caption)
                    .frame(width: 330, alignment: .leading)
            }

            if let message = editor.settings.lastMessage {
                Text(message).font(.caption2).foregroundStyle(.tertiary)
                    .frame(width: 330, alignment: .leading).lineLimit(3)
            }

            Text("Playing here means: \(playScopeText)")
                .font(.caption2).foregroundStyle(.tertiary)
            Text("In the timeline: ⌘= / ⌘− zoom · [ or ] picks a handle · ← / → nudges it (⇧ = 1 s)")
                .font(.caption2).foregroundStyle(.tertiary)
                .frame(width: 330, alignment: .leading)
        }
        .padding(14)
        .task { await bootstrap() }
        .onChange(of: editor.variant) { _, _ in applyVariant() }
        .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) } }
    }

    private var playScopeText: String {
        switch editor.variant.playScope {
        case .whole: "the whole Recording, Trim shown but ignored"
        case .trimLooping: "the Trim only, looping"
        case .fromPlayhead: "from the playhead to the end"
        }
    }

    private func row(title: String, back: String, forward: String, label: String,
                     step: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 62, alignment: .leading)
            Button(back) { step(-1) }.buttonStyle(.bordered)
            Text(label).font(.headline).frame(width: 190, alignment: .leading)
            Button(forward) { step(1) }.buttonStyle(.bordered)
        }
    }

    private func cycle<T: CaseIterable & Equatable>(_ value: inout T, by step: Int)
    where T.AllCases: RandomAccessCollection, T.AllCases.Index == Int {
        let all = T.allCases
        guard let i = all.firstIndex(of: value) else { return }
        value = all[(i + step + all.count) % all.count]
    }

    private func bootstrap() async {
        do { try Fixtures.ensureLibrary() } catch { Diag.note("fixtures failed: \(error)") }
        editor.loadLibrary()
        Diag.note("library \(editor.recordings.count) Recordings at \(Library.folder.path)")
        applyVariant()
        installKeyMonitor()
    }

    private func applyVariant() {
        if editor.variant.usesDocumentWindows {
            dismissWindow(id: "editor")
            if let url = editor.selection?.url { showDocument(url) }
        } else {
            for url in openDocuments { dismissWindow(id: "doc", value: url) }
            openDocuments.removeAll()
            openWindow(id: "editor")
        }
    }

    private func showDocument(_ url: URL) {
        openWindow(id: "doc", value: url)
        openDocuments.insert(url)
    }

    /// A local monitor rather than .keyboardShortcut, so the axes work whichever window is key.
    private func installKeyMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // The timeline's own keys go first: zoom, handle selection, nudge.
            if TimelineKeys.handle(event, editor: editor) { return nil }
            guard event.modifierFlags.contains(.option) else { return event }
            switch Int(event.keyCode) {
            case 123: cycle(&editor.variant, by: -1); return nil    // ⌥←
            case 124: cycle(&editor.variant, by: 1); return nil     // ⌥→
            case 126: cycle(&editor.precision, by: -1); return nil  // ⌥↑
            case 125: cycle(&editor.precision, by: 1); return nil   // ⌥↓
            default: return event
            }
        }
    }
}
