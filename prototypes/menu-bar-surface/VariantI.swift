//  PROTOTYPE — throwaway. Variant I: recording changes nothing about the panel's shape.

import SwiftUI

/// Variant I — **the panel has no modes.**
///
/// The bet: issue #6 settled that the row *is* the record control, and the strongest
/// reading of that is that stopping should be the same gesture in the same pixel. So the
/// panel keeps exactly the structure it had while idle — the app list, and a Library
/// footer that is always there — and recording is nothing but a row *state*: the glyph
/// flips, an elapsed readout appears in the row, and the other rows go quiet because only
/// one Source can be recorded at a time.
///
/// What this costs: elapsed time and level are as small as a list row can make them, and
/// the panel never announces "you are recording" in a way you can see from across a desk.
/// Variant J is the counterweight.
struct VariantI: View {
    static let title = "No modes — recording is a row state"
    @Bindable var model: SourceModel
    @State private var hovered: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var session: Session { .shared }
    private var monitor: LevelMonitor { .shared }
    private let laneWidth: CGFloat = 34

    /// While recording, the recording Source is pinned to the top and everything else is
    /// still listed — sorting it away would be a structural change, which is the one
    /// thing this variant refuses to do.
    private var rows: [Source] {
        guard let recording = session.recording else { return model.playing }
        var rest = model.playing.filter { $0.bundleID != recording.bundleID }
        rest.insert(recording, at: 0)
        return rest
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: session.isRecording ? "Recording" : "Playing Audio",
                        showsLock: monitor.looksUnpermitted)
            Divider()

            ScrollView {
                LazyVStack(spacing: 2) {
                    if rows.isEmpty {
                        NothingPlaying()
                    } else {
                        ForEach(rows) { row($0) }
                    }
                }
                .padding(6)
            }
            .frame(height: 274)

            Divider()
            LibraryFooter()
        }
        .frame(width: 320)
        .onAppear { monitor.sync(with: model.sources) }
        .onChange(of: model.sources) { _, sources in monitor.sync(with: sources) }
    }

    @ViewBuilder
    private func row(_ source: Source) -> some View {
        let isRecording = session.recording?.bundleID == source.bundleID
        // Only one Source can be recorded at once (out of scope on the map), so while a
        // Recording runs every *other* row is inert. Dimming without disabling would be a
        // lie — the row still looks like a control.
        let isInert = session.isRecording && !isRecording

        Button {
            session.toggle(source)
        } label: {
            HStack(spacing: 10) {
                AppIcon(source: source, size: 28)
                Text(source.name).foregroundStyle(.primary)
                Spacer(minLength: 8)

                if isRecording {
                    ElapsedText(text: session.elapsedText, font: .callout)
                        .foregroundStyle(.red)
                        .transition(.opacity)
                }

                ZStack {
                    if hovered == source.id && !isInert {
                        Circle().fill(.primary.opacity(0.12))
                    }
                    RecordGlyph(isRecording: isRecording)
                }
                .frame(width: 26, height: 26)
            }
            .padding(.leading, 11)
            .padding(.trailing, (laneWidth - 26) / 2)
            .frame(height: 46)
            .background {
                ZStack {
                    if isRecording { Color.red.opacity(0.10) }
                    WaveformBackground(samples: monitor.waveforms[source.bundleID] ?? [],
                                       isSelected: isRecording,
                                       trailingInset: laneWidth)
                }
            }
            .clipShape(.rect(cornerRadius: 9))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .disabled(isInert)
        .opacity(isInert ? 0.4 : 1)
        .onHover { hovered = $0 ? source.id : nil }
    }
}

// MARK: - Pieces shared by more than one variant

/// The `circle` → pulsing `record.circle.fill` swap settled in issue #6. Not up for
/// judgement here; it is factored out so all four variants inherit the same one and the
/// differences between them stay structural.
struct RecordGlyph: View {
    var isRecording: Bool
    var size: CGFloat = 17
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: isRecording ? "record.circle.fill" : "circle")
            .font(.system(size: size))
            .foregroundStyle(isRecording ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.pulse, options: .repeating, isActive: isRecording)
            .symbolEffectsRemoved(reduceMotion)
    }
}

struct PanelHeader: View {
    var title: String
    var showsLock: Bool

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            if showsLock {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help("Taps are running but every sample is zero — System Audio Recording is probably not granted. There is no API to check.")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// The route to older Recordings. Variants I and J share it; K reuses it inside its
/// right-click panel; L rejects it outright in favour of a second deck.
struct LibraryFooter: View {
    private var session: Session { .shared }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if let latest = session.library.first {
                    session.editing = latest
                    EditorPresenter.shared.open()
                }
            } label: {
                Label("Recordings", systemImage: "list.bullet")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .disabled(session.library.isEmpty)
            .foregroundStyle(session.library.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))

            Spacer()

            if !session.library.isEmpty {
                Text("\(session.library.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
