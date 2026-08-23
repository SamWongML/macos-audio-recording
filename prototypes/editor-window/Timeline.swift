//  PROTOTYPE — throwaway. The scrubbable timeline and the Trim range selector.
//
//  These are the two surfaces issue #4 found no official component for: SwiftUI's Slider
//  only ever takes a single Binding<V> (checked again against the macOS 27 interface —
//  four initialiser shapes, none of them range-valued), and no RangeSlider type exists.
//  So this is hand-drawn, and this file is the honest measure of what that costs.

import AVFoundation
import SwiftUI

/// The ↑ / ↓ axis of the prototype. Orthogonal to layout: every variant can wear any of them.
enum Precision: String, CaseIterable, Identifiable {
    case whole, zoom, loupe
    var id: Self { self }
    var title: String {
        switch self {
        case .whole: "Whole — no zoom"
        case .zoom:  "Zoom — viewport + overview"
        case .loupe: "Loupe — magnify while dragging"
        }
    }
    var blurb: String {
        switch self {
        case .whole: "The Recording always fits the width. One pixel is duration ÷ width."
        case .zoom:  "⌘+ / ⌘− or pinch to zoom, scroll to pan. An overview strip shows the viewport."
        case .loupe: "Still whole-width, but dragging a handle opens a ±2 s magnifier at raw detail."
        }
    }
}

@MainActor @Observable
final class TimelineState {
    /// The visible range under `.zoom`. Ignored by the other treatments.
    var visible: ClosedRange<Double> = 0...1
    var focusedHandle: Handle? = nil
    var draggingHandle: Handle? = nil
    var loupeCentre: Double = 0
    /// True between the first onChanged and onEnded of one drag.
    var gestureActive = false
    /// Switcher-driven: pins the loupe open so it can be judged without a mouse held down.
    var loupePinned = false

    enum Handle: Hashable { case start, end }

    func reset(duration: Double) {
        visible = 0...max(duration, 0.001)
        focusedHandle = nil
        draggingHandle = nil
    }

    func zoom(by factor: Double, around anchor: Double, duration: Double) {
        let span = (visible.upperBound - visible.lowerBound) / factor
        let clamped = min(max(span, 0.05), duration)
        let ratio = duration <= 0 ? 0 : (anchor - visible.lowerBound) / (visible.upperBound - visible.lowerBound)
        var lower = anchor - clamped * ratio
        lower = min(max(0, lower), max(0, duration - clamped))
        visible = lower...(lower + clamped)
    }

    func pan(by seconds: Double, duration: Double) {
        let span = visible.upperBound - visible.lowerBound
        var lower = visible.lowerBound + seconds
        lower = min(max(0, lower), max(0, duration - span))
        visible = lower...(lower + span)
    }
}

// MARK: - The timeline

struct TrimTimeline: View {
    var recording: Recording
    var envelope: Envelope
    var player: Player
    var precision: Precision
    var state: TimelineState
    /// Some variants want the waveform to carry the whole window; others want a strip.
    var showsRuler = true
    var handlesEnabled = true

    private var visible: ClosedRange<Double> {
        precision == .zoom ? state.visible : 0...max(recording.duration, 0.001)
    }

    var body: some View {
        VStack(spacing: 6) {
            if precision == .zoom { overview.frame(height: 26) }
            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                lane(width: width, height: geo.size.height)
            }
            if showsRuler { ruler }
        }
    }

    // MARK: waveform lane

    private func lane(width: Double, height: Double) -> some View {
        let span = visible.upperBound - visible.lowerBound
        func x(_ t: Double) -> Double { (t - visible.lowerBound) / span * width }
        func time(_ px: Double) -> Double {
            min(max(0, visible.lowerBound + px / width * span), recording.duration)
        }

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.35))

            WaveformShape(columns: envelope.columns(over: visible, count: Int(width)),
                          peakStyle: AnyShapeStyle(.tint.opacity(0.45)),
                          bodyStyle: AnyShapeStyle(.tint))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // Trimmed-away audio stays visible but inert. Trim never removes anything
            // (ADR-0003), and the picture should say so.
            Rectangle().fill(.background.opacity(0.62))
                .frame(width: max(0, x(recording.trim.lowerBound)))
            Rectangle().fill(.background.opacity(0.62))
                .frame(width: max(0, width - x(recording.trim.upperBound)))
                .offset(x: x(recording.trim.upperBound))

            if handlesEnabled {
                handle(.start, at: x(recording.trim.lowerBound), height: height)
                handle(.end, at: x(recording.trim.upperBound), height: height)
            } else {
                marker(at: x(recording.trim.lowerBound), height: height)
                marker(at: x(recording.trim.upperBound), height: height)
            }

            playhead(at: x(player.position), height: height)

            if precision == .loupe, state.draggingHandle != nil || state.loupePinned {
                loupe(width: width)
            }
        }
        .contentShape(Rectangle())
        .gesture(scrub(time: time))
        .modifier(ZoomGestures(enabled: precision == .zoom, state: state,
                               duration: recording.duration, visible: visible, width: width))
    }

    /// One decision per drag, taken from `startLocation`.
    ///
    /// The first pass keyed off `translation == .zero` to mean "this is the first event",
    /// and it was wrong: the first onChanged usually already carries a pixel or two of
    /// travel, so grabbing a handle silently turned into a scrub instead.
    private func scrub(time: @escaping (Double) -> Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !state.gestureActive {
                    state.gestureActive = true
                    let grabbed = handlesEnabled ? nearestHandle(to: time(value.startLocation.x)) : nil
                    state.draggingHandle = grabbed
                    if let grabbed { state.focusedHandle = grabbed }
                }
                let t = time(value.location.x)
                if let handle = state.draggingHandle {
                    move(handle, to: t)
                    state.loupeCentre = t
                } else {
                    player.seek(to: t)
                }
            }
            .onEnded { _ in
                state.gestureActive = false
                state.draggingHandle = nil
            }
    }

    /// Hit test in *time*, converted from a fixed 9 pt grab area — so the grab is the same
    /// physical size at every zoom level, which is the whole reason zoom helps.
    private func nearestHandle(to t: Double) -> TimelineState.Handle? {
        let span = visible.upperBound - visible.lowerBound
        let tolerance = span * 0.02
        let dStart = abs(t - recording.trim.lowerBound)
        let dEnd = abs(t - recording.trim.upperBound)
        guard min(dStart, dEnd) < tolerance else { return nil }
        return dStart < dEnd ? .start : .end
    }

    private func move(_ handle: TimelineState.Handle, to t: Double) {
        switch handle {
        case .start: recording.trim.setStart(t)
        case .end: recording.trim.setEnd(t)
        }
    }

    // MARK: decorations

    private func handle(_ which: TimelineState.Handle, at x: Double, height: Double) -> some View {
        let active = state.draggingHandle == which || state.focusedHandle == which
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

    private func marker(at x: Double, height: Double) -> some View {
        Rectangle().fill(.tint).frame(width: 2, height: height).offset(x: x - 1)
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

    // MARK: overview strip (zoom only)

    private var overview: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let d = max(recording.duration, 0.001)
            ZStack(alignment: .leading) {
                WaveformShape(columns: envelope.columns(over: 0...d, count: Int(w)),
                              peakStyle: AnyShapeStyle(.secondary.opacity(0.35)),
                              bodyStyle: AnyShapeStyle(.secondary.opacity(0.6)))
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(.tint, lineWidth: 1.5)
                    .background(RoundedRectangle(cornerRadius: 3).fill(.tint.opacity(0.12)))
                    .frame(width: max(3, (visible.upperBound - visible.lowerBound) / d * w))
                    .offset(x: visible.lowerBound / d * w)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let span = visible.upperBound - visible.lowerBound
                let centre = value.location.x / w * d
                state.visible = min(max(0, centre - span / 2), max(0, d - span)) ... 
                                min(max(0, centre - span / 2), max(0, d - span)) + span
            })
        }
    }

    // MARK: loupe

    /// Raw frames around the handle being dragged, read straight off the master. No mode to
    /// enter and no navigation to learn — it exists only while your finger is down.
    ///
    /// Its scale is fixed by contract (see `EnvelopeLoader.loupeWindow`): the box always
    /// shows exactly `span` seconds, so the crosshair down the middle is always exactly the
    /// time in the label, and dragging a handle always moves the picture at the same rate.
    /// Near the head or the tail the file simply runs out, and that is drawn as an edge.
    private func loupe(width: Double) -> some View {
        let span = 4.0
        let boxWidth = 212.0
        // While dragging it follows the handle; pinned open from the switcher it follows the
        // playhead, so it can be judged with no mouse held down.
        let centre = state.draggingHandle == nil ? player.position : state.loupeCentre
        let window = EnvelopeLoader.loupeWindow(url: recording.url, centre: centre,
                                                span: span, columns: 220)
        // Normalised to its own window. Unscaled it was a flat line exactly where it
        // matters most — the quiet gap between two phrases, which is where an edit lands.
        let columns = Envelope.normalised(window.columns)
        let bounds = window.insideFraction

        let x = min(max(boxWidth / 2, (centre - visible.lowerBound)
                        / (visible.upperBound - visible.lowerBound) * width),
                    width - boxWidth / 2)

        return VStack(spacing: 3) {
            ZStack {
                // Everything outside the file, so the head and the tail look like an end
                // rather than like two seconds of silence.
                HStack(spacing: 0) {
                    Rectangle().fill(.black.opacity(0.28))
                        .frame(width: boxWidth * bounds.lowerBound)
                    Spacer(minLength: 0)
                    Rectangle().fill(.black.opacity(0.28))
                        .frame(width: boxWidth * (1 - bounds.upperBound))
                }

                // Masked to the part of the window that is actually in the file. Without
                // this, the zero columns off either end draw as a flat hairline, which reads
                // as two seconds of silence rather than as the end of the Recording.
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

                // A hairline exactly where the Recording begins or ends.
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

                // The crosshair is the contract made visible: it sits at the box's centre,
                // and the box's centre is `centre`.
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
        // Inside the lane, not above it: floated above, it was clipped by the window on a
        // layout that puts the waveform near the top.
        .offset(x: x - (boxWidth / 2 + 7), y: 10)
        .allowsHitTesting(false)
    }

    // MARK: ruler

    private var ruler: some View {
        HStack {
            Text(Format.time(visible.lowerBound))
            Spacer()
            if recording.isTrimmed {
                Text("Trim \(Format.time(recording.trim.lowerBound)) – \(Format.time(recording.trim.upperBound))")
                    .foregroundStyle(.tint)
            }
            Spacer()
            Text(Format.time(visible.upperBound))
        }
        .font(.caption).monospacedDigit()
        .foregroundStyle(.secondary)
    }
}

// MARK: - The keyboard path

/// Every keyboard route into the timeline lives here rather than on `.onKeyPress`, because
/// `.onKeyPress` needs the view to hold focus and a plain `.focusable()` custom view on
/// macOS only enters the Tab loop under Full Keyboard Access. Measured, not assumed: the
/// first pass put zoom on `.onKeyPress` and no key ever arrived. #21 owns whether an
/// app-level monitor is an acceptable answer for assistive use, or only a prototype's.
@MainActor
enum TimelineKeys {
    /// Returns true if the event was consumed.
    static func handle(_ event: NSEvent, editor: Editor) -> Bool {
        guard let recording = editor.selection else { return false }
        let state = editor.timeline
        let flags = event.modifierFlags

        if flags.contains(.command), editor.precision == .zoom {
            let centre = (state.visible.lowerBound + state.visible.upperBound) / 2
            switch event.charactersIgnoringModifiers {
            case "=", "+": state.zoom(by: 2, around: centre, duration: recording.duration); return true
            case "-", "_": state.zoom(by: 0.5, around: centre, duration: recording.duration); return true
            default: break
            }
        }
        guard !flags.contains(.command), !flags.contains(.option) else { return false }

        switch event.charactersIgnoringModifiers {
        case "[": state.focusedHandle = .start; return true
        case "]": state.focusedHandle = .end; return true
        default: break
        }

        // Arrows only bite once a handle is selected, so they stay available to the sidebar
        // and to any ordinary control until you have actually aimed at something.
        guard let handle = state.focusedHandle else { return false }
        let step = flags.contains(.shift) ? 1.0 : 0.01
        switch Int(event.keyCode) {
        case 123: nudge(recording, handle, by: -step); return true
        case 124: nudge(recording, handle, by: +step); return true
        default: return false
        }
    }

    private static func nudge(_ recording: Recording, _ handle: TimelineState.Handle, by delta: Double) {
        switch handle {
        case .start: recording.trim.nudgeStart(by: delta)
        case .end: recording.trim.nudgeEnd(by: delta)
        }
    }
}

// MARK: - Zoom gestures

private struct ZoomGestures: ViewModifier {
    var enabled: Bool
    var state: TimelineState
    var duration: Double
    var visible: ClosedRange<Double>
    var width: Double

    func body(content: Content) -> some View {
        guard enabled else { return AnyView(content) }
        return AnyView(content
            .gesture(MagnifyGesture().onChanged { value in
                state.zoom(by: 1 + (value.magnification - 1) * 0.25,
                           around: (visible.lowerBound + visible.upperBound) / 2,
                           duration: duration)
            })
            .onScrollWheel { delta in
                state.pan(by: delta / width * (visible.upperBound - visible.lowerBound), duration: duration)
            }
            )
    }
}

extension View {
    /// No SwiftUI scroll-wheel hook exists on macOS, so this is an NSView monitor.
    func onScrollWheel(_ handler: @escaping (Double) -> Void) -> some View {
        background(ScrollWheelCatcher(handler: handler))
    }
}

private struct ScrollWheelCatcher: NSViewRepresentable {
    var handler: (Double) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.handler = handler
        return view
    }
    func updateNSView(_ view: CatcherView, context: Context) { view.handler = handler }

    final class CatcherView: NSView {
        var handler: ((Double) -> Void)?
        override func scrollWheel(with event: NSEvent) {
            let dx = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.scrollingDeltaY
            handler?(-dx)
        }
    }
}

// MARK: - Formatting

enum Format {
    static func time(_ seconds: Double, precise: Bool = false) -> String {
        let s = max(0, seconds)
        let h = Int(s) / 3600, m = (Int(s) % 3600) / 60, sec = Int(s) % 60
        let frac = Int((s - s.rounded(.down)) * 100)
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return precise ? String(format: "%d:%02d.%02d", m, sec, frac)
                       : String(format: "%d:%02d", m, sec)
    }

    static func bytes(_ count: Int64) -> String {
        count.formatted(.byteCount(style: .file))
    }
}
