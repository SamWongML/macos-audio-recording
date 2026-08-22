//  PROTOTYPE — throwaway. Variant G: the indicator the research actually recommends.
//
//  G exists to argue with F. F paints the whole row with a live scrolling waveform, which
//  is what was asked for; the waveform-in-list-rows research argues the opposite —
//  `Image(systemName:variableValue:)` redrawn a few times a second, with no perpetual
//  animation in the list at all, and motion reserved for state changes. Both are built so
//  the choice is made by looking rather than by reading.

import SwiftUI

/// The recommended indicator: a static, value-driven symbol fill.
///
/// `speaker.wave.3` is the HIG's own worked example for variable rendering — "you could
/// use variable color with the speaker.wave.3 symbol to communicate three different
/// ranges of sound... by mapping the layers that represent the curved wave paths to
/// different ranges of decibel values". Nothing animates: `variableValue` is a static
/// state selection, so it needs no Reduce Motion gate, and redrawing it at 12 Hz costs
/// nothing next to a per-frame `TimelineView`.
struct SpeakerLevel: View {
    var level: Float
    var isPlaying: Bool

    var body: some View {
        Image(systemName: "speaker.wave.3", variableValue: Double(min(max(level, 0), 1)))
            .font(.body)
            .foregroundStyle(isPlaying ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            .symbolRenderingMode(.hierarchical)
            .contentTransition(.symbolEffect(.replace))
    }
}

/// Variant G — quiet rows, value-driven indicator, action revealed on hover, **and no
/// Core Audio taps at all**.
///
/// This is the deliberate counterweight to F and H. The research's sharpest caution is to
/// never open a tap per row just to populate the list: that surfaces the permission prompt
/// before the person has asked to record anything. So G degrades to the two-state fill the
/// research recommends for the no-grant case — silent or producing sound — driven purely
/// by `kAudioProcessPropertyIsRunningOutput`, which costs no permission whatsoever.
///
/// Flipping between G and H is therefore a real product choice, not a style choice: G is
/// what the picker can show for free, H is what it can show if it spends the grant.
///
/// `.onHover` is the only hover primitive macOS has: `HoverEffect` and
/// `listRowHoverEffect` are both explicitly `@available(macOS, unavailable)`. Swapping a
/// passive glyph for an action control on hover is a long-standing macOS convention
/// (Music's track-number-becomes-play-button), though not a named HIG pattern.
struct VariantG: View {
    static let title = "Variable symbol + hover"
    @Bindable var model: SourceModel
    @State private var hovered: String?
    @State private var showsOthers = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Playing Audio").font(.headline)
                Spacer()
                Text("no permission needed")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVStack(spacing: 1) {
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
    }

    @ViewBuilder
    private func row(_ source: Source) -> some View {
        let isSelected = source.id == model.selectedID
        let isHovered = hovered == source.id
        HStack(spacing: 10) {
            AppIcon(source: source, size: 26)
            Text(source.name)
            Spacer(minLength: 20)

            // The trailing accessory sits in the macOS 20-28pt control band either way,
            // so the swap does not move the row's layout.
            ZStack {
                if isHovered {
                    Button {
                    } label: {
                        Image(systemName: "record.circle")
                            .font(.title3)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Record \(source.name)")
                } else {
                    // Two states, not a continuous level: without a tap there is no
                    // amplitude to show, and pretending otherwise would be a lie.
                    SpeakerLevel(level: source.isPlaying ? 1 : 0,
                                 isPlaying: source.isPlaying)
                }
            }
            .frame(width: 24, height: 24)
            .symbolEffectsRemoved(reduceMotion)
        }
        .padding(.horizontal, 11)
        .frame(height: 38)
        // Standard materials in the content layer — no glass on a passive readout, and no
        // per-row glass container, both of which the HIG argues against.
        .background(isSelected ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear),
                    in: .rect(cornerRadius: 7))
        .contentShape(.rect)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { hovered = hovering ? source.id : nil }
        }
        .onTapGesture { model.selectedID = source.id }
    }
}
