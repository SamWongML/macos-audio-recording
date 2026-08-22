//  PROTOTYPE — throwaway. Variant F: the row's background IS the app's live waveform.

import SwiftUI

/// A real amplitude waveform, mirrored around the row's centre line and scrolling
/// right-to-left, drawn behind the row's content.
///
/// Legibility is the whole difficulty: this sits *under* a title and a subtitle, so it is
/// drawn low-opacity and masked to fade out under the text on the leading edge, leaving
/// the trailing two-thirds — where there is no text — carrying the signal.
struct WaveformBackground: View {
    var ring: LevelRing
    var isSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { _ in
            Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                let samples = ring.snapshot()
                guard !samples.isEmpty else { return }

                let midY = size.height / 2
                let step = size.width / CGFloat(samples.count - 1)
                var path = Path()

                // Top edge left-to-right, then the mirrored bottom edge back, so the two
                // meet in a single closed shape rather than two strokes.
                path.move(to: CGPoint(x: 0, y: midY))
                for (index, sample) in samples.enumerated() {
                    let amplitude = CGFloat(sample) * midY * 0.92
                    path.addLine(to: CGPoint(x: CGFloat(index) * step, y: midY - amplitude))
                }
                for (index, sample) in samples.enumerated().reversed() {
                    let amplitude = CGFloat(sample) * midY * 0.92
                    path.addLine(to: CGPoint(x: CGFloat(index) * step, y: midY + amplitude))
                }
                path.closeSubpath()

                context.fill(path, with: .linearGradient(
                    Gradient(colors: [.accentColor.opacity(0.05), .accentColor.opacity(0.55)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: 0)))
            }
            .opacity(isSelected ? 0.9 : 0.6)
            // Keep the waveform off the icon and the title.
            .mask(LinearGradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black.opacity(0.35), location: 0.28),
                .init(color: .black, location: 0.55),
                .init(color: .black, location: 1.0),
            ], startPoint: .leading, endPoint: .trailing))
        }
    }
}

/// Variant F — same "list is the panel" spine as B, but a playing row is *drawn* by its
/// own audio. Silence is the absence of a waveform, so the list needs no speaker glyphs,
/// no toggle, and no "Playing audio" caption: the row either has a signal or it doesn't.
struct VariantF: View {
    static let title = "Waveform rows (real audio)"
    @Bindable var model: SourceModel
    @State private var showsOthers = false
    @State private var hovered: String?

    private var monitor: LevelMonitor { .shared }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("Playing Audio").font(.headline)
                Spacer()
                if monitor.looksUnpermitted {
                    Label("No signal", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help("Taps are running but every sample is zero — System Audio Recording is probably not granted. There is no API to check.")
                }
                if !monitor.failures.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help(monitor.failures.map { "\($0.key): \($0.value)" }.joined(separator: "\n"))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVStack(spacing: 3) {
                    if model.playing.isEmpty {
                        NothingPlaying()
                    } else {
                        ForEach(model.playing) { source in row(source) }
                    }

                    DisclosureGroup(isExpanded: $showsOthers.animation(.snappy)) {
                        ForEach(model.sources.filter { !$0.isPlaying }) { source in row(source) }
                    } label: {
                        Text("^[\(model.sources.filter { !$0.isPlaying }.count) silent app](inflect: true)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                }
                .padding(6)
            }
            .frame(height: 280)
        }
        .frame(width: 320)
        .onAppear { monitor.sync(with: model.sources) }
        .onChange(of: model.sources) { _, sources in monitor.sync(with: sources) }
    }

    @ViewBuilder
    private func row(_ source: Source) -> some View {
        let isSelected = source.id == model.selectedID
        HStack(spacing: 10) {
            AppIcon(source: source, size: 28)
            Text(source.name)
            Spacer(minLength: 40)
            // Symbol-only, sized like a menu accessory rather than a web CTA. The record
            // affordance is still open — pending the record-affordance research — so this
            // is the smallest thing that could work, not a committed answer.
            Image(systemName: isSelected ? "record.circle.fill" : "record.circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.red : Color.secondary.opacity(hovered == source.id ? 0.9 : 0.35))
                .contentTransition(.symbolEffect(.replace))
        }
        .padding(.horizontal, 11)
        .frame(height: 46)
        .background {
            ZStack {
                if isSelected { Color.accentColor.opacity(0.14) }
                if let ring = monitor.ring(for: source.bundleID) {
                    WaveformBackground(ring: ring, isSelected: isSelected)
                }
            }
        }
        .clipShape(.rect(cornerRadius: 9))
        .contentShape(.rect)
        .onHover { hovered = $0 ? source.id : nil }
        .onTapGesture { withAnimation(.snappy(duration: 0.2)) { model.selectedID = source.id } }
    }
}
