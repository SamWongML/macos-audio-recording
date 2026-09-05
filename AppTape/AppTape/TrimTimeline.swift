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
    var showsRuler = true

    /// The Recording being captured right now, if any — the one case in which a Recording the
    /// editor can select genuinely has no audio yet (ADR-0021). Read here, as `ExportInspector`
    /// already does, so the empty lane can say *why* it is empty rather than just being blank.
    @State private var recorder = RecordingController.shared

    @State private var draggingHandle: Handle?
    @State private var loupeCentre: Double = 0
    @State private var gestureActive = false

    enum Handle { case start, end }

    private var visible: ClosedRange<Double> { 0...max(recording.duration, 0.001) }

    /// What an empty lane says. A Recording with no frames is one whose file is still being
    /// written — a master mid-capture, or a file still arriving in the Library — so the lane says
    /// that instead of drawing a picture of nothing (ADR-0021). Before this, a zero-length
    /// Recording drew its whole-width trimmed-away dimmer as a solid slab (issue #80).
    private var emptyTelling: String {
        recorder.isCapturing(recording) ? "Still capturing" : "No audio yet"
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                lane(width: max(geo.size.width, 1), height: geo.size.height)
            }
            if showsRuler { ruler }
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

            if recording.isEmpty {
                // Nothing to draw over: no waveform, no Trim, no playhead — a Trim over zero frames
                // has both handles at zero, which drew the trimmed-away dimmer across the whole lane
                // and read as a solid slab (issue #80).
                Text(emptyTelling)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: width, height: height)
            } else {
                WaveformShape(columns: envelope.columns(over: visible, count: Int(width)),
                              peakStyle: AnyShapeStyle(.tint.opacity(0.45)),
                              bodyStyle: AnyShapeStyle(.tint))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                // Seams draw as hatched bands over the waveform, each with a ~3 pt minimum width so a
                // Seam that is sub-pixel on an always-fits-the-width timeline is still visible (ADR-0010).
                seamBands(x: x, height: height)

                // Trimmed-away audio stays visible but dimmed. Trim never removes anything
                // (ADR-0003), and the picture should say so.
                Rectangle().fill(.background.opacity(0.62))
                    .frame(width: max(0, x(recording.trim.lowerBound)))
                Rectangle().fill(.background.opacity(0.62))
                    .frame(width: max(0, width - x(recording.trim.upperBound)))
                    .offset(x: x(recording.trim.upperBound))

                handle(.start, at: x(recording.trim.lowerBound), height: height)
                handle(.end, at: x(recording.trim.upperBound), height: height)

                playhead(at: x(player.position), height: height)

                if draggingHandle != nil { loupe(width: width) }
            }
        }
        .contentShape(Rectangle())
        .gesture(scrub(time: time))
        // There is nothing to scrub or Trim on a Recording with no frames, and a drag would move
        // handles that have nowhere to go.
        .disabled(recording.isEmpty)
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

    private func handle(_ which: Handle, at x: Double, height: Double) -> some View {
        let active = draggingHandle == which
        return Capsule()
            .fill(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .frame(width: active ? 5 : 3, height: height)
            .overlay(alignment: which == .start ? .leading : .trailing) {
                Image(systemName: which == .start ? "chevron.compact.right" : "chevron.compact.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.background)
                    .padding(which == .start ? .leading : .trailing, 1)
            }
            .offset(x: x - (active ? 2.5 : 1.5))
            .shadow(radius: active ? 3 : 0)
            .animation(.easeOut(duration: 0.12), value: active)
    }

    private func playhead(at x: Double, height: Double) -> some View {
        Rectangle()
            .fill(.primary)
            .frame(width: 1.5, height: height)
            .overlay(alignment: .top) {
                Circle().fill(.primary).frame(width: 7, height: 7).offset(y: -3)
            }
            .offset(x: x - 0.75)
            .allowsHitTesting(false)
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
                              peakStyle: AnyShapeStyle(.tint.opacity(0.5)),
                              bodyStyle: AnyShapeStyle(.tint))
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.separator))
        .shadow(radius: 10, y: 3)
        // Inside the lane, not above it: floated above, it was clipped by the window on a layout
        // that puts the waveform near the top (issue #7).
        .offset(x: x - (boxWidth / 2 + 7), y: 10)
        .allowsHitTesting(false)
    }

    // MARK: - Ruler

    private var ruler: some View {
        HStack {
            Text(Format.time(visible.lowerBound))
            Spacer()
            if recording.isTrimmed {
                Text("Trim \(recording.trimRangeText)")
                    .foregroundStyle(.tint)
            }
            Spacer()
            Text(Format.time(visible.upperBound))
        }
        .font(.caption).monospacedDigit()
        .foregroundStyle(.secondary)
    }
}
