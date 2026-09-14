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
    /// What capture is doing, accepted like the three above it (ADR-0045). The lane asks two things
    /// of it: whether it has anything dependable to draw (ADR-0021), and — so the empty lane can say
    /// *why* it is empty rather than just being blank — whether this is the Recording being captured.
    var capture: any CaptureState
    /// Persist the Trim once, at gesture-end — never per drag frame (issue #7, ADR-0006).
    var onTrimCommitted: () -> Void

    /// The loupe's material is the editor's one vibrant surface in the detail pane (issue #73,
    /// finding 15). Reduce Motion is handled by `.motion(_:value:)`, not read here.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// The playhead's two opacity stops are per-appearance, so both are read here (ADR-0033).
    /// `colorSchemeContrast` is readable but not settable — `.environment(_:_:)` does not compile
    /// for it — so the Increase Contrast branch below is reasoned, not measured (issue #103).
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @State private var draggingHandle: Handle?
    @State private var loupeCentre: Double = 0
    @State private var gestureActive = false

    enum Handle { case start, end }

    /// The lane's mapping between points and seconds, over whatever width this pass measured.
    /// It replaces a `visible` range whose lower bound was provably `0` at all seven sites that
    /// subtracted it — ADR-0023 closed the zoom question, and the code never caught up (ADR-0047).
    private func geometry(width: Double) -> TimelineGeometry {
        TimelineGeometry(width: width, duration: recording.duration)
    }

    /// Whether the lane has anything dependable to draw. The Recording always fits the width, so a
    /// reading of a file still being written is drawn as though it were the whole Recording — which
    /// is how a fraction of a second became a solid slab across the lane (issue #80, ADR-0021).
    private var isStillArriving: Bool { capture.isStillArriving(recording) }

    /// What the lane says in place of that picture. A capture in progress is named as such; a file
    /// merely arriving in the Library has no better word than that it holds no audio yet.
    private var arrivingMessage: String {
        capture.isCapturing(recording) ? "Still capturing" : "No audio yet"
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
                // Nothing dependable to draw over: no waveform, no Trim, no playhead. A Trim over
                // near-zero frames puts both handles at zero and stretches a fraction of a second
                // across the full width, which is what read as a solid slab (issue #80).
                //
                // Deliberately *not* a `Signal` token: ADR-0019 puts the accent on content, and the
                // whole point here is that there is no content yet. This is chrome telling you so.
                Text(arrivingMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: width, height: height)
            } else {
                waveform(geometry)

                // Dropouts draw as hatched bands over the waveform, each carrying `minimumDropoutWidth`
                // so one that is sub-pixel on an always-fits-the-width lane stays visible (ADR-0010).
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
        if isStillArriving { return arrivingMessage }
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
    /// **The under-copy is `Palette.signalQuiet` / `signalMutedQuiet`, not `.grayscale(1)`, and
    /// ADR-0040 amends that "colour, not brightness" clause rather than repeating it.** The filter
    /// moved brightness ~13% in both appearances — the correct direction in Dark, the wrong one in
    /// Light, where the Trimmed-away half rendered *louder* than the kept half and the playhead
    /// measured 2.82 : 1 over its peaks. The stops are the two Dark greys the filter itself
    /// produced and the two Light greys that recede by the same proportions, so Dark is unchanged
    /// and Light now says what the comment above always claimed. The magic number ADR-0019 refused
    /// is still refused: these are named per-appearance stops in the asset catalogue, not an alpha
    /// tuned by eye, and they survive Increase Contrast for the reason `Palette` states.
    ///
    /// **The lane must cut, never cross-fade, when the selection changes** — the first entry on
    /// ADR-0028's forbid-list, and a correctness matter rather than a taste one. Interpolating one
    /// Recording's peaks into another's animates a relationship between two files that does not
    /// exist; it is the same class of untruth as the 0.5 px silence floor issue #76 deleted. Note
    /// what this costs: no `.motion` may be attached at or above this view keyed on the selection.
    /// The Trim's own redraw is exempt because it is direct manipulation — the grayscale mask
    /// tracks the drag continuously, which is why it needs no animation of its own.
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

    /// One decision per drag, taken from `startLocation`. Keying off `translation == .zero` was
    /// wrong: the first `onChanged` of a `minimumDistance: 0` drag usually already carries a
    /// pixel or two of travel, so grabbing a handle silently turned into a scrub (issue #7).
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
    /// always-fits-the-width timeline is still visible (ADR-0010). The loupe deliberately has no
    /// such floor — see `loupeDropouts`.
    static let minimumDropoutWidth: Double = 3

    /// The hatched bands for the lane-visible Dropouts (rebuild-class; the tiny overrun Dropouts live in
    /// the editor summary, not here — ADR-0010). Each carries the floor above so it never vanishes.
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

    /// Dropout bands inside the loupe, at **true width** (no minimum) — the loupe exists to show raw
    /// detail, so a Dropout is drawn exactly as wide as it is against the ±2 s window (ADR-0010).
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
            // **The one custom shadow in the app, and ADR-0033 amends ADR-0019 to permit it here
            // rather than deleting it.** It predates the token set and does real work: it lifts the
            // handle off the waveform for the one moment the handle is `Signal` over `Signal`. The
            // ADR's "nothing gets a custom shadow" is about inventing an elevation system; this is
            // a single mark separating itself from the field it is dragged across.
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

    /// The playhead's ink: **the true ink of the appearance, at a measured opacity** — not
    /// `Color.primary`, and the difference is the whole margin (ADR-0033).
    ///
    /// `Color.primary` is `labelColor`, which is **85% ink, not ink**. Built that way first and
    /// measured on the running app over loud continuous material, it reached only **3.13 : 1**
    /// against the `Signal` peaks in Dark and **2.93 : 1** in Light — both under the 3 : 1 floor,
    /// against predictions of 3.74 and 3.17 that assumed a full-strength black and white. This is
    /// ADR-0032 repeating one level down: `.primary` was still a name read off the palette.
    ///
    /// So the stops are white and black outright, and they are **asymmetric because the lane is**:
    ///
    /// - **Dark, 0.75.** Full strength measures 13.0 : 1 against the lane ground, which would make
    ///   the playhead the brightest thing in a lane whose premise is that the *audio* is the loud
    ///   thing. 0.75 buys that back (8.1 : 1) and still clears the binding fill — the peaks — at
    ///   4.05 : 1.
    /// - **Light, 1.0, and there is no other value.** The light `Signal` peaks render dark,
    ///   `(77, 75, 202)`, so black over them is **3.16 : 1 at full strength and nothing better
    ///   exists**: solving the three fills together admits only inks below L 0.003, and 0.9 alpha
    ///   already drops the peaks to 3.02. White is worse, not better — 6.6 : 1 on the peaks but
    ///   **1.10 : 1 on the near-white lane ground**.
    ///
    /// **Light therefore ships with 5% of margin and no more available.** If the light `Signal`
    /// stop ever darkens, the playhead fails and it is `Signal` that has to move, not this.
    ///
    /// Under Increase Contrast the Dark subordination is given back. That branch is **stated, not
    /// verified**: `NSAppearance(named: .accessibilityHighContrastDarkAqua)` does not move
    /// `effectiveAppearance`, so the setting cannot be forced on this machine (issue #103).
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
                // The disc follows the line rather than substituting for it. It sits above the
                // lane, where peaks (capped at 88% of half-height) never reach, so it never had
                // the line's problem — but a `Signal` disc on a `.primary` line would read as two
                // marks instead of one.
                Circle().fill(ink).frame(width: 7, height: 7).offset(y: -3)
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
        // narrow to hold it, centres instead. This was a hand-written `min(max(half, x), width -
        // half)` over an interval that is empty below `boxWidth` — so the loupe stopped tracking at
        // 212 pt and sat off the leading edge below 106 (ADR-0047).
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

                // The crosshair is the contract made visible: it sits at the box's centre, and
                // the box's centre is `centre`.
                Rectangle().fill(.primary).frame(width: 1.5)
            }
            .frame(width: boxWidth, height: Self.loupeBoxHeight)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack(spacing: 5) {
                Text(Format.time(centre, precise: true))
                    .font(.system(.caption, design: .monospaced))
                    .monospacedDigit()
                // **A flat label colour at a stated opacity, not a hierarchical rung.** Over the
                // loupe's vibrant material in Dark, `.tertiary` resolved to within four luminance
                // units of the material itself — the brightest glyph pixel measured (57,57,57) on a
                // (53,52,56) panel, **1.07 : 1** — so the caption was a smudge beside the figure,
                // while the same style was legible in Light and legible again under Reduce
                // Transparency, where the material goes opaque (issue #103, finding 1).
                //
                // The blend is the cause, not the colour. `.secondary` was measured on the running
                // app first and reached only **2.77 : 1**, still under the 4.5 : 1 floor for text
                // this size: the hierarchical rungs are *vibrancy* styles, and vibrancy over a dark
                // material is exactly what collapses here. `Color.primary` composites normally, so
                // the opacity does the subordinating that `.secondary` was hired for and the
                // contrast survives. The caption stays — it is the only statement of the loupe's
                // scale — but it is stated in a style that can be measured on the material rather
                // than read off the palette.
                Text("±\(Int(span / 2))s")
                    .font(.caption2)
                    .foregroundStyle(Color.primary.opacity(0.7))
            }
        }
        .padding(Self.loupePadding)
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
        .offset(x: x - (boxWidth / 2 + Self.loupePadding), y: 10)
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
            let geometry = self.geometry(width: geo.size.width)

            ZStack(alignment: .topLeading) {
                // **No ticks while the audio is still arriving** (ADR-0031). The ruler's times are
                // a function of `recording.duration`, which for a growing master is whatever the
                // last folder listing read — so a two-minute capture drew `0:00 0:01 0:02 0:03`
                // over a lane with no waveform in it, a timeline for a length nobody has. The
                // alternative, ticking against the live figure, is worse: the ruler would rescale
                // continuously, which is the ambient motion ADR-0028 forbids. The ruler simply has
                // nothing to say until there is a Recording to lay out.
                //
                // This used to be spelled `tickTimes(duration: isStillArriving ? 0 : …)` — the
                // policy stated by lying to the arithmetic about the length. The geometry answers
                // for a duration it is given; whether that duration is trustworthy yet is the
                // ruler's judgement, and it is made here.
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

    /// The box, in points. It is deliberately **not** `loupeColumns`: the window is bucketed on a
    /// fixed time grid of `loupeSpan / loupeColumns` and then drawn across this width, so the
    /// picture is very slightly oversampled and the centre column still lands exactly on `centre`.
    private static let loupeBoxWidth: Double = 212
    private static let loupeBoxHeight: Double = 54
    private static let loupeColumns: Int = 220

    /// The inset around the box, which the box's own offset has to undo.
    private static let loupePadding: Double = 7
}

// MARK: - Previews

// `#if DEBUG`, as `PreviewFixtures.swift` is: a preview body is compiled in Release too, so a fixture
// that does not ship has to be guarded where it is used as well as where it is defined.
#if DEBUG

/// The lane's three states, which is the whole reason `capture` is accepted rather than reached for
/// (ADR-0045). Before this, none of them could be rendered without a live tap: the second and third
/// require a Recording that is *being written*, which only Core Audio and a noisy Source produce.

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
/// growing and says why (ADR-0021, issue #80), and the transport offers no Play.
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
/// the leading edge entirely (ADR-0047).
///
/// The loupe itself is not in this picture, and cannot be: it shows only while `draggingHandle` is
/// set, which is `@State` with no dropout to set it from outside. That clamp is covered by
/// `TimelineGeometryTests` instead — which is the point of moving it out of the view. What this
/// does show is the rest of the lane at that width: the ruler's labels pulled inside the trailing
/// edge, and the handles still landing where the mapping says.
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
