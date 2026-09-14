import SwiftUI

/// The scrubbable timeline and the Trim range selector — the two surfaces found no official
/// component for (SwiftUI's `Slider` only ever takes a single `Binding<V>`, and no `RangeSlider`
/// type exists on macOS 27).
struct TrimTimeline: View {
    var recording: Recording
    var envelope: Envelope
    var player: AudioPlayer
    /// What capture is doing, accepted like the three above it.
    var capture: any CaptureState
    /// Persist the Trim once, at gesture-end — never per drag frame.
    var onTrimCommitted: () -> Void

    /// The loupe's material is the editor's one vibrant surface in the detail pane. Reduce Motion
    /// is handled by `.motion(_:value:)`, not read here.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// The playhead's two opacity stops are per-appearance, so both are read here.
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @State private var draggingHandle: Handle?
    @State private var loupeCentre: Double = 0
    @State private var gestureActive = false

    enum Handle { case start, end }

    /// The lane's mapping between points and seconds, over whatever width this pass measured.
    private func geometry(width: Double) -> TimelineGeometry {
        TimelineGeometry(width: width, duration: recording.duration)
    }

    /// Whether the lane has anything dependable to draw.
    private var isStillArriving: Bool { capture.isStillArriving(recording) }

    /// What the lane says in place of that picture. A capture in progress is named as such; a file
    /// merely arriving in the Library has no better word than that it holds no audio yet.
    private var arrivingMessage: String {
        capture.isCapturing(recording) ? "Still capturing" : "No audio yet"
    }

    var body: some View {
        VStack(spacing: Metrics.xs) {
            // The ruler sits above the lane, which is where every peer that has one puts it
            // (Fission's restored upper timeline ruler, Sound Studio's per-pane ruler, Logic's
            ruler
            GeometryReader { geo in
                lane(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    // MARK: - Lane

    private func lane(width: Double, height: Double) -> some View {
        let geometry = self.geometry(width: width)

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.35))

            if isStillArriving {
                // Nothing dependable to draw over: no waveform, no Trim, no playhead.
                Text(arrivingMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: width, height: height)
            } else {
                waveform(geometry)

                // Dropouts draw as hatched bands over the waveform, each carrying
                // `minimumDropoutWidth` so one that is sub-pixel on an always-fits-the-width lane
                // stays visible.
                dropoutBands(geometry, height: height)

                handle(.start, at: geometry.x(atTime: recording.trim.lowerBound), height: height)
                handle(.end, at: geometry.x(atTime: recording.trim.upperBound), height: height)

                playhead(at: geometry.x(atTime: player.position), height: height)

                if draggingHandle != nil { loupe(geometry) }
            }
        }
        .contentShape(Rectangle())
        .gesture(scrub(geometry))
        // There is nothing to scrub or Trim while the audio is still arriving, and a drag would set
        // a Trim against a length that is about to change.
        .disabled(isStillArriving)
        // The lane exposed exactly two elements to accessibility — the two chevron `Image`s
        // inside the handles, read out as "Compact Right Chevron" — and nothing at all for the
        // waveform,
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Waveform")
        .accessibilityValue(laneAccessibilityValue)
    }

    /// What the lane says when VoiceOver lands on it: how long the Recording is and what the Trim
    /// currently keeps, in words, since none of that is otherwise readable without a mouse.
    private var laneAccessibilityValue: String {
        if isStillArriving { return arrivingMessage }
        let whole = "\(Format.time(recording.duration)) long"
        return recording.isTrimmed
            ? "\(whole), trimmed to \(recording.trimRangeText)"
            : "\(whole), whole Recording"
    }

    /// The lane's audio, drawn twice: colourless everywhere, in colour inside the Trim.
    private func waveform(_ geometry: TimelineGeometry) -> some View {
        let columns = envelope.columns(over: geometry.visibleRange, count: geometry.columnCount)
        let shape = WaveformShape(columns: columns,
                                  peakStyle: AnyShapeStyle(Palette.signal),
                                  bodyStyle: AnyShapeStyle(Palette.signalMuted))
        let quiet = WaveformShape(columns: columns,
                                  peakStyle: AnyShapeStyle(Palette.signalQuiet),
                                  bodyStyle: AnyShapeStyle(Palette.signalMutedQuiet))
        let keptStart = geometry.x(atTime: recording.trim.lowerBound)
        let keptWidth = geometry.points(from: recording.trim.lowerBound,
                                        to: recording.trim.upperBound, minimum: 0)
        return ZStack(alignment: .topLeading) {
            quiet
            shape.mask(alignment: .topLeading) {
                Rectangle().frame(width: keptWidth).offset(x: keptStart)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// One decision per drag, taken from `startLocation`.
    private func scrub(_ geometry: TimelineGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !gestureActive {
                    gestureActive = true
                    draggingHandle = nearestHandle(to: geometry.time(atX: value.startLocation.x),
                                                   within: geometry.grabTolerance)
                }
                let t = geometry.time(atX: value.location.x)
                if let handle = draggingHandle {
                    move(handle, to: t)
                    loupeCentre = t
                } else {
                    player.seek(to: t)
                }
            }
            .onEnded { _ in
                let didMoveHandle = draggingHandle != nil
                gestureActive = false
                draggingHandle = nil
                // The Trim xattr is written once, here — not on every frame of the drag.
                if didMoveHandle { onTrimCommitted() }
            }
    }

    /// Hit-test in *time*. The tolerance is the lane's, not this view's: a fixed fraction of the
    /// width, so the grab area is a consistent physical size whatever the Recording's length.
    private func nearestHandle(to t: Double, within tolerance: Double) -> Handle? {
        let dStart = abs(t - recording.trim.lowerBound)
        let dEnd = abs(t - recording.trim.upperBound)
        guard min(dStart, dEnd) < tolerance else { return nil }
        return dStart < dEnd ? .start : .end
    }

    private func move(_ handle: Handle, to t: Double) {
        switch handle {
        case .start: recording.trim.setStart(t)
        case .end: recording.trim.setEnd(t)
        }
    }

    // MARK: - Dropouts

    /// The narrowest a Dropout band may draw in the lane, so one that is sub-pixel on an
    /// always-fits-the-width timeline is still visible.
    static let minimumDropoutWidth: Double = 3

    /// The hatched bands for the lane-visible Dropouts (rebuild-class; the tiny overrun Dropouts live in
    /// the editor summary, not here —). Each carries the floor above so it never vanishes.
    @ViewBuilder
    private func dropoutBands(_ geometry: TimelineGeometry, height: Double) -> some View {
        let rate = recording.sampleRate
        ForEach(Array(recording.laneDropouts.enumerated()), id: \.offset) { _, dropout in
            let start = dropout.startSeconds(sampleRate: rate)
            let end = dropout.endSeconds(sampleRate: rate)
            DropoutBand()
                .frame(width: geometry.points(from: start, to: end,
                                              minimum: Self.minimumDropoutWidth),
                       height: height)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .offset(x: geometry.x(atTime: start))
                .allowsHitTesting(false)
        }
    }

    /// Dropout bands inside the loupe, at true width (no minimum) — the loupe exists to show raw
    /// detail, so a Dropout is drawn exactly as wide as it is against the ±2 s window.
    private func loupeDropouts(centre: Double, span: Double, boxWidth: Double, boxHeight: Double) -> some View {
        let rate = recording.sampleRate
        let lo = centre - span / 2
        return ForEach(Array(recording.dropouts.enumerated()), id: \.offset) { _, dropout in
            let start = dropout.startSeconds(sampleRate: rate)
            let end = dropout.endSeconds(sampleRate: rate)
            // Fraction of the box each edge lands on, clamped to the visible window.
            let f0 = max(0, min(1, (start - lo) / span))
            let f1 = max(0, min(1, (end - lo) / span))
            if f1 > f0 {
                DropoutBand(spacing: 4)
                    .frame(width: boxWidth * (f1 - f0), height: boxHeight)
                    .offset(x: boxWidth * f0 - boxWidth / 2 + boxWidth * (f1 - f0) / 2)
            }
        }
    }

    // MARK: - Decorations

    /// How far one accessibility nudge moves a handle: a fixed fraction of the Recording, so the
    /// gesture takes the same number of steps end-to-end whatever the length.
    private var accessibilityStep: Double { max(0.1, recording.duration / 100) }

    private func handle(_ which: Handle, at x: Double, height: Double) -> some View {
        let active = draggingHandle == which
        let time = which == .start ? recording.trim.lowerBound : recording.trim.upperBound
        return Capsule()
            .fill(active ? AnyShapeStyle(Palette.signal) : AnyShapeStyle(.secondary))
            .frame(width: active ? 5 : 3, height: height)
            .overlay(alignment: which == .start ? .leading : .trailing) {
                Image(systemName: which == .start ? "chevron.compact.right" : "chevron.compact.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.background)
                    .padding(which == .start ? .leading : .trailing, 1)
                    .accessibilityHidden(true)
            }
            .offset(x: x - (active ? 2.5 : 1.5))
            // The one custom shadow in the app, and amends to permit it here rather than deleting
            // it. It predates the token set and does real work: it lifts the
            .shadow(radius: active ? 3 : 0)
            // The handle answering the cursor: `motionQuick`, AppTape's direct-manipulation stop
            // and the value this token was seeded from.
            .motion(Metrics.motionQuick, value: active)
            .accessibilityElement()
            .accessibilityLabel(which == .start ? "Trim start" : "Trim end")
            .accessibilityValue(Format.time(time, precise: true))
            .accessibilityAdjustableAction { direction in
                let delta = direction == .increment ? accessibilityStep : -accessibilityStep
                move(which, to: time + delta)
                onTrimCommitted()
            }
    }

    /// The playhead's ink: the true ink of the appearance, at a measured opacity — not
    /// `Color.primary`, and the difference is the whole margin.
    private var playheadInk: Color {
        let isDark = colorScheme == .dark
        let subdued = isDark && colorSchemeContrast == .standard
        return (isDark ? Color.white : Color.black).opacity(subdued ? 0.75 : 1)
    }

    private func playhead(at x: Double, height: Double) -> some View {
        let ink = playheadInk
        return Rectangle()
            .fill(ink)
            .frame(width: 1.5, height: height)
            .overlay(alignment: .top) {
                // The disc follows the line rather than substituting for it.
                Circle().fill(ink).frame(width: 7, height: 7).offset(y: -3)
            }
            .offset(x: x - 0.75)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: - Loupe

    /// Raw frames around the handle being dragged, read straight off the master.
    private func loupe(_ geometry: TimelineGeometry) -> some View {
        let span = Self.loupeSpan
        let boxWidth = Self.loupeBoxWidth
        let centre = loupeCentre
        let window = EnvelopeLoader.loupeWindow(url: recording.url, centre: centre,
                                                span: span, columns: Self.loupeColumns)
        // Normalised to its own window: unscaled it was a flat line exactly where it matters —
        // the quiet gap between two phrases, which is where an edit lands.
        let columns = Envelope.normalised(window.columns)
        let bounds = window.insideFraction

        // The box follows the handle without overhanging either end of the lane, and on a lane too
        // narrow to hold it, centres instead.
        let x = geometry.centredBoxX(at: centre, boxWidth: boxWidth)

        return VStack(spacing: 3) {
            ZStack {
                HStack(spacing: 0) {
                    Rectangle().fill(.black.opacity(0.28))
                        .frame(width: boxWidth * bounds.lowerBound)
                    Spacer(minLength: 0)
                    Rectangle().fill(.black.opacity(0.28))
                        .frame(width: boxWidth * (1 - bounds.upperBound))
                }

                WaveformShape(columns: columns,
                              peakStyle: AnyShapeStyle(Palette.signal),
                              bodyStyle: AnyShapeStyle(Palette.signalMuted))
                    .mask {
                        HStack(spacing: 0) {
                            Color.clear.frame(width: boxWidth * bounds.lowerBound)
                            Color.black.frame(width: boxWidth * (bounds.upperBound - bounds.lowerBound))
                            Color.clear
                        }
                    }

                HStack(spacing: 0) {
                    if bounds.lowerBound > 0 {
                        Spacer(minLength: 0).frame(width: boxWidth * bounds.lowerBound - 1)
                        Rectangle().fill(.separator).frame(width: 1)
                    }
                    Spacer(minLength: 0)
                    if bounds.upperBound < 1 {
                        Rectangle().fill(.separator).frame(width: 1)
                        Spacer(minLength: 0).frame(width: boxWidth * (1 - bounds.upperBound) - 1)
                    }
                }

                // Dropouts at true width inside the loupe, drawn over the waveform silence they pad.
                loupeDropouts(centre: centre, span: span, boxWidth: boxWidth,
                           boxHeight: Self.loupeBoxHeight)

                // The crosshair is the contract made visible: it sits at the box's centre, and the
                // box's centre is `centre`.
                Rectangle().fill(.primary).frame(width: 1.5)
            }
            .frame(width: boxWidth, height: Self.loupeBoxHeight)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack(spacing: 5) {
                Text(Format.time(centre, precise: true))
                    .font(.system(.caption, design: .monospaced))
                    .monospacedDigit()
                // A flat label colour at a stated opacity, not a hierarchical preset row. Over the
                // loupe's vibrant material in Dark, `.tertiary` resolved to within four luminance
                Text("±\(Int(span / 2))s")
                    .font(.caption2)
                    .foregroundStyle(Color.primary.opacity(0.7))
            }
        }
        .padding(Self.loupePadding)
        // Reduce Transparency swaps the vibrant material for an opaque window background, as
        // `PanelView` already did — the editor honoured neither accessibility setting (finding
        // 15).
        .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                                       : AnyShapeStyle(.regularMaterial),
                    in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.separator))
        .shadow(radius: 10, y: 3)
        // Inside the lane, not above it: floated above, it was clipped by the window on a layout
        // that puts the waveform near the top.
        .offset(x: x - (boxWidth / 2 + Self.loupePadding), y: 10)
        .allowsHitTesting(false)
        // It exists only while a handle is under the hand; the handle's own value says the time.
        .accessibilityHidden(true)
    }

    // MARK: - Ruler

    /// A pure time axis: ticks at a round interval with `mm:ss` labels, and nothing else.
    private var ruler: some View {
        GeometryReader { geo in
            let geometry = self.geometry(width: geo.size.width)

            ZStack(alignment: .topLeading) {
                // No ticks while the audio is still arriving.
                ForEach(isStillArriving ? [] : geometry.ticks, id: \.self) { t in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Format.time(t))
                            .font(.caption2).monospacedDigit()
                            .foregroundStyle(.secondary)
                            .fixedSize()
                        Rectangle().fill(.quaternary).frame(width: 1, height: 4)
                    }
                    // The last label is pulled in so it cannot run off the trailing edge.
                    .offset(x: geometry.labelX(at: t, reserving: Self.tickLabelWidth))
                }
            }
        }
        .frame(height: Self.rulerHeight)
        // The lane publishes the Trim in words (`laneAccessibilityValue`) and the bottom bar
        // publishes the range; the ticks are decoration.
        .accessibilityHidden(true)
    }

    /// Height of the ruler row: one line of tick labels plus the tick marks under them.
    private static let rulerHeight: Double = 24

    /// How much room a `mm:ss` tick label needs, so the last one is pulled in rather than clipped.
    private static let tickLabelWidth: Double = 30

    // MARK: - The loupe's own scale

    /// The window the loupe shows, in seconds — the ±2 s of the file header. Stated once here and
    /// read by the box, the Dropout bands and the caption, which each used to say it for themselves.
    private static let loupeSpan: Double = 4

    /// The box, in points.
    private static let loupeBoxWidth: Double = 212
    private static let loupeBoxHeight: Double = 54
    private static let loupeColumns: Int = 220

    /// The inset around the box, which the box's own offset has to undo.
    private static let loupePadding: Double = 7
}

// MARK: - Previews

// `#if DEBUG`, as `PreviewFixtures.swift` is: a preview body is compiled in Release too, so a
// fixture that does not ship has to be guarded where it is used as well as where it is defined.
#if DEBUG

/// The lane's three states, which is the whole reason `capture` is accepted rather than reached for
///.

#Preview("Lane · settled") {
    TrimTimeline(recording: .stub(),
                 envelope: .preview(),
                 player: AudioPlayer(),
                 capture: PreviewCapture.settled,
                 onTrimCommitted: {})
        .frame(width: 760, height: 300)
        .padding(Metrics.xl)
}

/// A Recording still being captured: the lane declines to draw a reading of a file that is still
/// growing and says why, and the transport offers no Play.
#Preview("Lane · capturing") {
    let recording = Recording.stub(seconds: 93)
    TrimTimeline(recording: recording,
                 envelope: .preview(),
                 player: AudioPlayer(),
                 capture: PreviewCapture.capturing(recording),
                 onTrimCommitted: {})
        .frame(width: 760, height: 300)
        .padding(Metrics.xl)
}

/// A lane narrower than the loupe's own box — the width class that was never rendered, and where
/// the loupe's clamp inverted: below 212 pt it stopped tracking the drag, and below 106 it sat off
/// the leading edge entirely.
#Preview("Lane · narrower than the loupe") {
    TrimTimeline(recording: .stub(seconds: 93),
                 envelope: .preview(),
                 player: AudioPlayer(),
                 capture: PreviewCapture.settled,
                 onTrimCommitted: {})
        .frame(width: 180, height: 300)
        .padding(Metrics.xl)
}

/// A Recording with no frames at all — adopted moments after the first sound created it, or one that
/// could not be opened. The other half of `isStillArriving`, and the half zero-frames alone was.
#Preview("Lane · no audio yet") {
    TrimTimeline(recording: .stub(seconds: 0),
                 envelope: Envelope(),
                 player: AudioPlayer(),
                 capture: PreviewCapture.settled,
                 onTrimCommitted: {})
        .frame(width: 760, height: 300)
        .padding(Metrics.xl)
}

#endif
