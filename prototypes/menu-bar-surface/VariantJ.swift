//  PROTOTYPE — throwaway. Variant J: recording is a mode, and it takes the whole panel.

import SwiftUI

/// Variant J — **the panel commits.**
///
/// The bet against I: while a Recording is running, a list of nine other apps you are not
/// recording is noise. The one thing that matters is that capture is alive and how long
/// it has been running, so the panel throws the list away and shows that at a size you
/// can read from across a desk: Source identity, a large elapsed clock, the live signal
/// full-width, and one Stop.
///
/// Start is still one click on a row (issue #6). Stop is one click on Stop. What this
/// costs is that the stop target is not where the start target was, and the panel now has
/// two shapes that can be caught mid-transition.
struct VariantJ: View {
    static let title = "Recording takes over the panel"
    @Bindable var model: SourceModel

    private var session: Session { .shared }
    private var monitor: LevelMonitor { .shared }

    var body: some View {
        Group {
            if let source = session.recording {
                RecordingDeck(source: source)
            } else {
                idle
            }
        }
        .frame(width: 320)
        .onAppear { monitor.sync(with: model.sources) }
        .onChange(of: model.sources) { _, sources in monitor.sync(with: sources) }
    }

    private var idle: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Playing Audio", showsLock: monitor.looksUnpermitted)
            Divider()
            ScrollView {
                LazyVStack(spacing: 2) {
                    if model.playing.isEmpty {
                        NothingPlaying()
                    } else {
                        ForEach(model.playing) { source in
                            IdleRow(source: source) { session.start(source) }
                        }
                    }
                }
                .padding(6)
            }
            .frame(height: 274)
            Divider()
            LibraryFooter()
        }
    }
}

/// The idle row, identical to H. Extracted so J's two shapes do not share a body — the
/// whole point of the variant is that they are different views, not one view with
/// branches inside it.
private struct IdleRow: View {
    var source: Source
    var start: () -> Void
    @State private var hovered = false
    private let laneWidth: CGFloat = 34
    private var monitor: LevelMonitor { .shared }

    var body: some View {
        Button(action: start) {
            HStack(spacing: 10) {
                AppIcon(source: source, size: 28)
                Text(source.name).foregroundStyle(.primary)
                Spacer(minLength: 8)
                ZStack {
                    if hovered { Circle().fill(.primary.opacity(0.12)) }
                    RecordGlyph(isRecording: false)
                }
                .frame(width: 26, height: 26)
            }
            .padding(.leading, 11)
            .padding(.trailing, (laneWidth - 26) / 2)
            .frame(height: 46)
            .background {
                WaveformBackground(samples: monitor.waveforms[source.bundleID] ?? [],
                                   isSelected: false,
                                   trailingInset: laneWidth)
            }
            .clipShape(.rect(cornerRadius: 9))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovered = $0 }
    }
}

/// The recording mode. No list, no Library, no way to start a second Recording — the
/// panel is about the Recording that is running and nothing else.
private struct RecordingDeck: View {
    var source: Source
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var session: Session { .shared }
    private var monitor: LevelMonitor { .shared }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "record.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, options: .repeating)
                    .symbolEffectsRemoved(reduceMotion)
                Text("Recording").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    AppIcon(source: source, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(source.name).font(.title3.weight(.medium))
                        Text("System audio").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                // The clock is the hero. `.largeTitle` monospaced-digit is roughly the
                // largest a 320pt panel can carry without the layout feeling like a
                // stopwatch app, which is the size this variant is arguing for.
                ElapsedText(text: session.elapsedText, font: .system(size: 42, weight: .light))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Full width, because there is no list to inset around any more.
                WaveformBackground(samples: monitor.waveforms[source.bundleID] ?? [],
                                   isSelected: true)
                    .frame(height: 46)
                    .clipShape(.rect(cornerRadius: 8))

                Button {
                    session.stop()
                    EditorPresenter.shared.open()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
    }
}
