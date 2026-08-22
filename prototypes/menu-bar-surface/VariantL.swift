//  PROTOTYPE — throwaway. Variant L: the Library is half the panel, not a footer link.

import SwiftUI

/// Variant L — **two decks: Record on top, Library underneath.**
///
/// The bet against I, J and K, all of which treat older Recordings as a link out: this is
/// a recorder whose *whole point* is the loop record → trim → export, and in the other
/// three that loop leaves the menu bar on the first hop. L keeps both halves on screen, so
/// a Recording visibly lands in the Library the moment you stop, and reopening yesterday's
/// is one click from the same surface that started it.
///
/// While recording, the top deck collapses to a single strip — the recording Source, the
/// clock, the signal, and stop — and the Library stays put underneath. So the panel keeps
/// both jobs at once, which is exactly what J argues it should not do.
///
/// What this costs is height, and a panel that is busier at rest than any of the others.
struct VariantL: View {
    static let title = "Two decks — Record and Library"
    @Bindable var model: SourceModel

    private var session: Session { .shared }
    private var monitor: LevelMonitor { .shared }

    var body: some View {
        VStack(spacing: 0) {
            if let source = session.recording {
                RecordingStrip(source: source)
            } else {
                recordDeck
            }

            Divider()
            libraryDeck
        }
        .frame(width: 320)
        .onAppear {
            monitor.sync(with: model.sources)
            session.seedLibrary()
        }
        .onChange(of: model.sources) { _, sources in monitor.sync(with: sources) }
    }

    private var recordDeck: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Playing Audio", showsLock: monitor.looksUnpermitted)
            Divider()
            ScrollView {
                LazyVStack(spacing: 2) {
                    if model.playing.isEmpty {
                        NothingPlaying()
                    } else {
                        ForEach(model.playing) { source in
                            DeckRow(source: source) { session.start(source) }
                        }
                    }
                }
                .padding(6)
            }
            .frame(height: 168)
        }
    }

    private var libraryDeck: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recordings").font(.headline)
                Spacer()
                Text("\(session.library.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            ScrollView {
                LazyVStack(spacing: 1) {
                    if session.library.isEmpty {
                        Text("Nothing recorded yet")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 26)
                    } else {
                        ForEach(session.library) { LibraryRow(recording: $0) }
                    }
                }
                .padding(6)
            }
            .frame(height: 132)
        }
    }
}

private struct DeckRow: View {
    var source: Source
    var start: () -> Void
    @State private var hovered = false
    private let laneWidth: CGFloat = 34
    private var monitor: LevelMonitor { .shared }

    var body: some View {
        Button(action: start) {
            HStack(spacing: 10) {
                AppIcon(source: source, size: 24)
                Text(source.name).foregroundStyle(.primary)
                Spacer(minLength: 8)
                ZStack {
                    if hovered { Circle().fill(.primary.opacity(0.12)) }
                    RecordGlyph(isRecording: false, size: 15)
                }
                .frame(width: 24, height: 24)
            }
            .padding(.leading, 11)
            .padding(.trailing, (laneWidth - 24) / 2)
            .frame(height: 40)
            .background {
                WaveformBackground(samples: monitor.waveforms[source.bundleID] ?? [],
                                   isSelected: false,
                                   trailingInset: laneWidth)
            }
            .clipShape(.rect(cornerRadius: 8))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovered = $0 }
    }
}

/// The collapsed record deck. Everything J's full-panel deck carries, at strip height,
/// because the Library below has to stay visible.
private struct RecordingStrip: View {
    var source: Source
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var session: Session { .shared }
    private var monitor: LevelMonitor { .shared }

    var body: some View {
        HStack(spacing: 11) {
            AppIcon(source: source, size: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.name).font(.callout.weight(.medium)).lineLimit(1)
                ElapsedText(text: session.elapsedText, font: .title3)
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 6)

            Button {
                session.stop()
                EditorPresenter.shared.open()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 15))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.glass)
            .help("Stop and open the editor")
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background {
            ZStack {
                Color.red.opacity(0.10)
                WaveformBackground(samples: monitor.waveforms[source.bundleID] ?? [],
                                   isSelected: true,
                                   trailingInset: 52)
            }
        }
    }
}

struct LibraryRow: View {
    var recording: SavedRecording
    @State private var hovered = false
    private var session: Session { .shared }

    var body: some View {
        Button {
            session.editing = recording
            EditorPresenter.shared.open()
        } label: {
            HStack(spacing: 10) {
                Group {
                    if let icon = recording.icon {
                        Image(nsImage: icon).resizable()
                    } else {
                        Image(systemName: "waveform").resizable().scaledToFit().foregroundStyle(.secondary)
                    }
                }
                .frame(width: 20, height: 20)

                Text(recording.sourceName).lineLimit(1)

                Spacer(minLength: 6)

                Text(recording.endedAt, format: .relative(presentation: .numeric))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                Text(recording.duration.clockText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(hovered ? AnyShapeStyle(.selection.opacity(0.5)) : AnyShapeStyle(.clear),
                        in: .rect(cornerRadius: 7))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovered = $0 }
    }
}
