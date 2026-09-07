//
//  TrimTimeline.swift
//  AppTape
//

import SwiftUI

/// The scrubbable timeline and the Trim range selector — the two surfaces issue #4 found no
/// official component for (SwiftUI's `Slider` only ever takes a single `Binding<V>`, and no
/// `RangeSlider` type exists on macOS 27). So this is hand-drawn, and this file is the honest
/// cost of that: hit-testing, two handles, a playhead, and the ±2 s loupe.
///
/// The Recording always fits the width — one pixel is `duration ÷ width` (the "whole" precision
/// treatment from issue #7). Accuracy comes from the **loupe**: dragging a handle opens a ±2 s
/// magnifier at raw sample detail, read straight off the master, that exists only while the
/// finger is down. There is no zoom mode; issue #21 owns the keyboard path.
struct TrimTimeline: View {
    var recording: Recording
    var envelope: Envelope
    var player: AudioPlayer
    /// Persist the Trim once, at gesture-end — never per drag frame (issue #7, ADR-0006).
    var onTrimCommitted: () -> Void

    /// The Recording being captured right now, if any. Read here, as `ExportInspector` already
    /// does, both to decide whether the lane has anything dependable to draw (ADR-0021) and so the
    /// empty lane can say *why* it is empty rather than just being blank.
    @State private var recorder = RecordingController.shared

    /// The loupe's material is the editor's one vibrant surface in the detail pane (issue #73,
    /// finding 15). Reduce Motion is handled by `.motion(_:value:)`, not read here.
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    private var reduceTransparency: Bool { systemReduceTransparency || SweepFlags.reduceTransparency }

    @State private var draggingHandle: Handle?
    @State private var loupeCentre: Double = 0
    @State private var gestureActive = false

    enum Handle { case start, end }

    private var visible: ClosedRange<Double> { 0...max(recording.duration, 0.001) }

    /// Whether the lane has anything dependable to draw. The Recording always fits the width, so a
    /// reading of a file still being written is drawn as though it were the whole Recording — which
    /// is how a fraction of a second became a solid slab across the lane (issue #80, ADR-0021).
    private var isStillArriving: Bool { recorder.isStillArriving(recording) }

    /// What the lane says in place of that picture. A capture in progress is named as such; a file
    /// merely arriving in the Library has no better word than that it holds no audio yet.
    private var arrivingTelling: String {
        recorder.isCapturing(recording) ? "Still capturing" : "No audio yet"
    }

    var body: some View {
        VStack(spacing: Metrics.xs) {
            // The ruler sits **above** the lane, which is where every peer that has one puts it
            // (Fission's restored upper timeline ruler, Sound Studio's per-pane ruler, Logic's
            // Audio Track Editor) — and it is what makes the lane read as a timeline rather than a
            // picture. It used to be a `showsRuler` parameter the editor always passed `false`;
            // ADR-0023 turned it on, and nothing has asked for it off since, so there is no
            // parameter to pass any more.
            ruler
            GeometryReader { geo in
                lane(width: max(geo.size.width, 1), height: geo.size.height)
            }
        }
    }

    // MARK: - Lane

    private func lane(width: Double, height: Double) -> some View {
        let span = visible.upperBound - visible.lowerBound
        func x(_ t: Double) -> Double { (t - visible.lowerBound) / span * width }
        func time(_ px: Double) -> Double {
            min(max(0, visible.lowerBound + px / width * span), recording.duration)
        }

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.35))

            if isStillArriving {
                // Nothing dependable to draw over: no waveform, no Trim, no playhead. A Trim over
                // near-zero frames puts both handles at zero and stretches a fraction of a second
                // across the full width, which is what read as a solid slab (issue #80).
                //
                // Deliberately *not* a `Signal` token: ADR-0019 puts the accent on content, and the
                // whole point here is that there is no content yet. This is chrome telling you so.
                Text(arrivingTelling)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: width, height: height)
            } else {
                waveform(x: x, width: width)

                // Seams draw as hatched bands over the waveform, each with a ~3 pt minimum width so a
                // Seam that is sub-pixel on an always-fits-the-width timeline is still visible (ADR-0010).
                seamBands(x: x, height: height)

                handle(.start, at: x(recording.trim.lowerBound), height: height)
                handle(.end, at: x(recording.trim.upperBound), height: height)

                playhead(at: x(player.position), height: height)

                if draggingHandle != nil { loupe(width: width) }
            }
        }
        .contentShape(Rectangle())
        .gesture(scrub(time: time))
        // There is nothing to scrub or Trim while the audio is still arriving, and a drag would set
        // a Trim against a length that is about to change.
        .disabled(isStillArriving)
        // The lane exposed exactly two elements to accessibility — the two chevron `Image`s inside
        // the handles, read out as "Compact Right Chevron" — and nothing at all for the waveform,
        // the playhead or the Trim (issue #73, finding 14). The decorations are hidden and three
        // real elements are published in their place: the lane, and one adjustable element per
        // handle. This is the *reading* half; the full keyboard editing path is issue #21's.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Waveform")
        .accessibilityValue(laneAccessibilityValue)
    }

    /// What the lane says when VoiceOver lands on it: how long the Recording is and what the Trim
    /// currently keeps, in words, since none of that is otherwise readable without a mouse.
    private var laneAccessibilityValue: String {
        if isStillArriving { return arrivingTelling }
        let whole = "\(Format.time(recording.duration)) long"
        return recording.isTrimmed
            ? "\(whole), trimmed to \(recording.trimRangeText)"
            : "\(whole), whole Recording"
    }

    /// The lane's audio, drawn twice: **colourless everywhere, in colour inside the Trim**.
    ///
    /// Trim never removes anything (ADR-0003) and the picture has to say so. It used to say it with
    /// `Rectangle().fill(.background.opacity(0.62))` over the trimmed-away ends — an alpha overlay
    /// that is dark grey over dark grey in Dark Mode, where the two sides of the boundary differed
    /// only in the waveform's saturation and the lane background not at all (issue #73, finding 8).
    /// ADR-0019 rejected raising that opacity in favour of this: what changes outside the Trim is
    /// **colour, not brightness**, which states *still there, just not Exported* directly, needs no
    /// per-appearance magic number, and survives Increase Contrast as an alpha overlay does not.
    /// It also leaves the Trim as the only indigo on the lane, which is the point of the ADR.
    ///
    /// **The lane must cut, never cross-fade, when the selection changes** — the first entry on
    /// ADR-0028's forbid-list, and a correctness matter rather than a taste one. Interpolating one
    /// Recording's peaks into another's animates a relationship between two files that does not
    /// exist; it is the same class of untruth as the 0.5 px silence floor issue #76 deleted. Note
    /// what this costs: no `.motion` may be attached at or above this view keyed on the selection.
    /// The Trim's own redraw is exempt because it is direct manipulation — the grayscale mask
    /// tracks the drag continuously, which is why it needs no animation of its own.
    private func waveform(x: @escaping (Double) -> Double, width: Double) -> some View {
        let shape = WaveformShape(columns: envelope.columns(over: visible, count: Int(width)),
                                  peakStyle: AnyShapeStyle(Palette.signal),
                                  bodyStyle: AnyShapeStyle(Palette.signalMuted))
        let keptStart = x(recording.trim.lowerBound)
        let keptWidth = max(0, x(recording.trim.upperBound) - keptStart)
        return ZStack(alignment: .topLeading) {
            shape.grayscale(1)
            shape.mask(alignment: .topLeading) {
                Rectangle().frame(width: keptWidth).offset(x: keptStart)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// One decision per drag, taken from `startLocation`. Keying off `translation == .zero` was
    /// wrong: the first `onChanged` of a `minimumDistance: 0` drag usually already carries a
    /// pixel or two of travel, so grabbing a handle silently turned into a scrub (issue #7).
    private func scrub(time: @escaping (Double) -> Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !gestureActive {
                    gestureActive = true
                    draggingHandle = nearestHandle(to: time(value.startLocation.x))
                }
                let t = time(value.location.x)
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

    /// Hit-test in *time*, from a fixed fraction of the visible span, so the grab area is a
    /// consistent physical size.
    private func nearestHandle(to t: Double) -> Handle? {
        let span = visible.upperBound - visible.lowerBound
        let tolerance = span * 0.02
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

    // MARK: - Seams

    /// The hatched bands for the lane-visible Seams (rebuild-class; the tiny overrun Seams live in
    /// the editor summary, not here — ADR-0010). Each carries a ~3 pt floor so it never vanishes.
    @ViewBuilder
    private func seamBands(x: @escaping (Double) -> Double, height: Double) -> some View {
        let rate = recording.sampleRate
        ForEach(Array(recording.laneSeams.enumerated()), id: \.offset) { _, seam in
            let x0 = x(seam.startSeconds(sampleRate: rate))
            let x1 = x(Double(seam.start + seam.frames) / rate)
            SeamBand()
                .frame(width: max(3, x1 - x0), height: height)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .offset(x: x0)
                .allowsHitTesting(false)
        }
    }

    /// Seam bands inside the loupe, at **true width** (no minimum) — the loupe exists to show raw
    /// detail, so a Seam is drawn exactly as wide as it is against the ±2 s window (ADR-0010).
    private func loupeSeams(centre: Double, span: Double, boxWidth: Double, boxHeight: Double) -> some View {
        let rate = recording.sampleRate
        let lo = centre - span / 2
        return ForEach(Array(recording.seams.enumerated()), id: \.offset) { _, seam in
            let s0 = seam.startSeconds(sampleRate: rate)
            let s1 = Double(seam.start + seam.frames) / rate
            // Fraction of the box each edge lands on, clamped to the visible window.
            let f0 = max(0, min(1, (s0 - lo) / span))
            let f1 = max(0, min(1, (s1 - lo) / span))
            if f1 > f0 {
                SeamBand(spacing: 4)
                    .frame(width: boxWidth * (f1 - f0), height: boxHeight)
                    .offset(x: boxWidth * f0 - boxWidth / 2 + boxWidth * (f1 - f0) / 2)
            }
        }
    }

    // MARK: - Decorations

    /// How far one accessibility nudge moves a handle: a fixed fraction of the Recording, so the
    /// gesture takes the same number of steps end-to-end whatever the length. It is the same
    /// always-fits-the-width reasoning the hit-test tolerance uses.
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
                    // These two were the only things the whole lane published (finding 14).
                    .accessibilityHidden(true)
            }
            .offset(x: x - (active ? 2.5 : 1.5))
            .shadow(radius: active ? 3 : 0)
            // The handle answering the cursor: `motionQuick`, AppTape's direct-manipulation stop
            // and the value this token was seeded from. Through the helper, not `.animation`
            // directly, so Reduce Motion degrades to a cross-fade rather than travelling
            // (ADR-0028, ADR-0019, issue #73 finding 15).
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

    private func playhead(at x: Double, height: Double) -> some View {
        Rectangle()
            .fill(Palette.signal)
            .frame(width: 1.5, height: height)
            .overlay(alignment: .top) {
                Circle().fill(Palette.signal).frame(width: 7, height: 7).offset(y: -3)
            }
            .offset(x: x - 0.75)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: - Loupe

    /// Raw frames around the handle being dragged, read straight off the master. Its scale is
    /// fixed by contract (see `EnvelopeLoader.loupeWindow`): the box always shows exactly `span`
    /// seconds, so the crosshair down the middle is always exactly the time in the label, and
    /// dragging a handle always moves the picture at the same rate. Near the head or the tail the
    /// file runs out, and that is drawn as an edge rather than passing for silence.
    private func loupe(width: Double) -> some View {
        let span = 4.0
        let boxWidth = 212.0
        let centre = loupeCentre
        let window = EnvelopeLoader.loupeWindow(url: recording.url, centre: centre,
                                                span: span, columns: 220)
        // Normalised to its own window: unscaled it was a flat line exactly where it matters —
        // the quiet gap between two phrases, which is where an edit lands.
        let columns = Envelope.normalised(window.columns)
        let bounds = window.insideFraction

        let x = min(max(boxWidth / 2, (centre - visible.lowerBound)
                        / (visible.upperBound - visible.lowerBound) * width),
                    width - boxWidth / 2)

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

                // Seams at true width inside the loupe, drawn over the waveform silence they pad.
                loupeSeams(centre: centre, span: span, boxWidth: boxWidth, boxHeight: 54)

                // The crosshair is the contract made visible: it sits at the box's centre, and
                // the box's centre is `centre`.
                Rectangle().fill(.primary).frame(width: 1.5)
            }
            .frame(width: boxWidth, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack(spacing: 5) {
                Text(Format.time(centre, precise: true))
                    .font(.system(.caption, design: .monospaced))
                    .monospacedDigit()
                Text("±\(Int(span / 2))s")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(7)
        // Reduce Transparency swaps the vibrant material for an opaque window background, as
        // `PanelView` already did — the editor honoured neither accessibility setting (issue #73,
        // finding 15).
        .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                                       : AnyShapeStyle(.regularMaterial),
                    in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.separator))
        .shadow(radius: 10, y: 3)
        // Inside the lane, not above it: floated above, it was clipped by the window on a layout
        // that puts the waveform near the top (issue #7).
        .offset(x: x - (boxWidth / 2 + 7), y: 10)
        .allowsHitTesting(false)
        // It exists only while a handle is under the hand; the handle's own value says the time.
        .accessibilityHidden(true)
    }

    // MARK: - Ruler

    /// **A pure time axis: ticks at a round interval with `mm:ss` labels, and nothing else.**
    ///
    /// It carried the Trim too, as a span bar with `0:00 – 0:06` printed under it. Two marks for
    /// one fact, stacked, directly above a lane that *already* draws the same range as two handles
    /// and a desaturated remainder — three statements of the Trim inside sixty vertical points.
    /// The bar and the readout both went; the numeric range now lives once, in the bottom bar,
    /// beside the control that resets it. This is also what the peers do: Fission, Sound Studio and
    /// Logic all keep the ruler as time and put the selection's figures in a status area.
    private var ruler: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let span = visible.upperBound - visible.lowerBound
            // A closure, not a `func`: a `ViewBuilder` closure cannot contain a declaration.
            let x: (Double) -> Double = { ($0 - visible.lowerBound) / span * width }

            ZStack(alignment: .topLeading) {
                // **No ticks while the audio is still arriving** (ADR-0031). The ruler's times are
                // a function of `recording.duration`, which for a growing master is whatever the
                // last folder listing read — so a two-minute capture drew `0:00 0:01 0:02 0:03`
                // over a lane with no waveform in it, a timeline for a length nobody has. The
                // alternative, ticking against the live figure, is worse: the ruler would rescale
                // continuously, which is the ambient motion ADR-0028 forbids. The ruler simply has
                // nothing to say until there is a Recording to lay out.
                ForEach(Self.tickTimes(duration: isStillArriving ? 0 : recording.duration,
                                       width: width), id: \.self) { t in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Format.time(t))
                            .font(.caption2).monospacedDigit()
                            .foregroundStyle(.secondary)
                            .fixedSize()
                        Rectangle().fill(.quaternary).frame(width: 1, height: 4)
                    }
                    // The last label is pulled in so it cannot run off the trailing edge.
                    .offset(x: min(x(t), width - 30))
                }
            }
        }
        .frame(height: Self.rulerHeight)
        // The lane publishes the Trim in words (`laneAccessibilityValue`) and the bottom bar
        // publishes the range; the ticks are decoration.
        .accessibilityHidden(true)
    }

    /// Height of the ruler row: one line of tick labels plus the tick marks under them.
    static let rulerHeight: Double = 24

    /// Tick times at a round interval — 1/2/5/10/15/30/60 s and up — chosen so no two labels come
    /// within 64 pt of each other. The Recording always fits the width and there is no zoom, so
    /// this is a function of duration and width alone.
    ///
    /// **No duration means no ticks, not one tick at zero** (ADR-0031). A lone `0:00` under an
    /// empty lane is a ruler insisting there is a timeline here; there isn't one until the file
    /// stops growing.
    static func tickTimes(duration: Double, width: Double) -> [Double] {
        guard duration > 0 else { return [] }
        let step = tickInterval(duration: duration, width: width)
        return stride(from: 0.0, through: duration, by: step).map { $0 }
    }

    static func tickInterval(duration: Double, width: Double) -> Double {
        let candidates: [Double] = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600]
        let minimumSpacing = 64.0
        let safeDuration = max(duration, 0.001)
        return candidates.first { $0 / safeDuration * width >= minimumSpacing } ?? candidates.last!
    }
}
