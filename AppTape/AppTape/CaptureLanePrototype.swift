//
//  CaptureLanePrototype.swift
//  AppTape
//
//  ⚠️ PROTOTYPE — issue #98. Throwaway code, on branch `prototype/editor-during-capture`.
//  It does not merge to main; the winning variant is rewritten properly and the rest is left
//  here as the primary source.
//
//  THE QUESTION: what do the lane, the transport, the sidebar row and the brief show while
//  audio is still arriving?
//
//  Three lane variants, switchable from a floating bar at the bottom of the detail pane. What
//  does **not** vary — the shared base under all three — is that every *number* goes live:
//  the transport's readout, the sidebar row's duration slot and the brief's `Master` row read
//  the engine's own figures instead of the last folder listing. That half was settled before
//  the prototype was built (see the issue); only the lane is in question.
//

import SwiftUI

// MARK: - The variants

enum CaptureLaneVariant: String, CaseIterable, Identifiable {
    /// A. Today's honest telling: the lane says `Still capturing` and draws nothing.
    case honest
    /// B. The panel's live level meter, moved into the lane. Constant scale, ~2.4 s rolling
    ///    window, only the newest column is new. A *monitor*, not a waveform.
    case monitor
    /// C. A growing whole-capture picture, fitted to the lane the way a real Recording is —
    ///    so it rescales continuously as the capture runs. Stands in for the incremental
    ///    envelope the ticket describes: it accumulates `LevelMeter` fills at 20 Hz rather
    ///    than reducing the master's frames, which is not sample-accurate but draws the same
    ///    shape at lane resolution, which is what the design question turns on.
    case growing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .honest: "A · Still capturing (today)"
        case .monitor: "B · Live level monitor"
        case .growing: "C · Growing whole-capture picture"
        }
    }
}

// MARK: - Prototype state

/// Holds the chosen variant and, for variant C, the accumulating column history.
///
/// Its own 20 Hz timer rather than a hook into `RecordingController`: the prototype must not
/// reshape the thing it is asking a question about, and `currentLevel` is already published at
/// exactly this cadence for the panel to read.
@MainActor
@Observable
final class CaptureLanePrototypeState {
    static let shared = CaptureLanePrototypeState()

    var variant: CaptureLaneVariant = .honest

    /// Every level fill since this capture's first sound, oldest first. Unbounded on purpose —
    /// the whole point of variant C is what happens to the picture as it fills up.
    private(set) var accumulated: [Double] = []

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var wasCapturing = false

    private init() {
        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sample() {
        let recorder = RecordingController.shared
        let capturing = recorder.isRecording && recorder.hasFirstSound
        if capturing && !wasCapturing { accumulated.removeAll() }
        wasCapturing = capturing
        guard capturing else { return }
        // **Back to linear before accumulating.** `currentLevel` is `LevelMeter`'s dB fill, which
        // is right for a meter and wrong for a waveform: a −6 dBFS peak reads 0.9 of full height
        // on the dB ramp and 0.5 on the linear scale `Envelope` actually draws. Accumulating the
        // dB figure made variant C saturate into a solid band within two minutes — the prototype's
        // artefact, not the design's. Inverting `LevelMeter.fill` recovers the linear peak.
        let db = recorder.currentLevel * -LevelMeter.floorDB + LevelMeter.floorDB
        accumulated.append(recorder.currentLevel > 0 ? pow(10, db / 20) : 0)
    }

    func cycle(_ step: Int) {
        let all = CaptureLaneVariant.allCases
        let i = all.firstIndex(of: variant) ?? 0
        variant = all[((i + step) % all.count + all.count) % all.count]
    }
}

// MARK: - The lane, per variant

/// What `TrimTimeline` draws in place of the waveform while audio is still arriving.
struct CaptureLanePrototype: View {
    /// `Still capturing` or `No audio yet` — the lane's existing telling, passed in so the
    /// non-capturing arriving case (a file merely being copied in) is unchanged in every variant.
    var telling: String
    /// Whether *this* Recording is the one being captured. Only then is there anything live.
    var isCapturing: Bool

    @State private var proto = CaptureLanePrototypeState.shared
    @State private var recorder = RecordingController.shared

    var body: some View {
        switch proto.variant {
        case .honest:
            stillCapturing
        case .monitor:
            if isCapturing { monitorLane } else { stillCapturing }
        case .growing:
            if isCapturing { growingLane } else { stillCapturing }
        }
    }

    /// Variant A, and the fallback for a file that is arriving but not being captured.
    private var stillCapturing: some View {
        Text(telling)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Variant B. The panel's rolling window, at the lane's size. Constant seconds-per-pixel:
    /// the columns translate leftward at a fixed rate and nothing already drawn changes shape.
    private var monitorLane: some View {
        ZStack {
            PrototypeMeterShape(fills: recorder.meterColumns)
                .fill(Palette.signal)
                .padding(.horizontal, 8)
                .padding(.vertical, 12)

            VStack {
                Spacer()
                Text("Still capturing · last \(Self.monitorWindowText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// ~2.4 s at 48 columns and 20 Hz — stated in the lane so the picture cannot be mistaken
    /// for the whole Recording.
    private static let monitorWindowText =
        "\(String(format: "%.1f", Double(RecordingController.meterColumnCount) / 20)) s"

    /// Variant C. Everything since the first sound, fitted across the lane — so the picture
    /// compresses as the capture runs, exactly as a real Recording's does, and every drawn
    /// pixel moves on every tick.
    private var growingLane: some View {
        ZStack {
            PrototypeMeterShape(fills: proto.accumulated)
                .fill(Palette.signal)
                .padding(.horizontal, 8)
                .padding(.vertical, 12)

            VStack {
                Spacer()
                Text("Still capturing · \(Format.time(recorder.elapsed)) so far")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Mirrored bars from 0...1 fills, oldest at the leading edge — the same drawing the panel's
/// row uses, copied rather than shared because `LevelMeterShape` is private to `PanelView` and
/// a prototype has no business widening it.
///
/// A `Shape`, not a `Canvas`: a `Canvas` draws nothing inside a lazy `List` row on macOS 27
/// (issue #7), and keeping one drawing for both lets the sidebar reuse it too.
struct PrototypeMeterShape: Shape {
    var fills: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !fills.isEmpty, rect.width > 0 else { return path }

        // **Reduced to the lane's width before drawing, the way the real envelope is.**
        // `Envelope.columns(over:count:)` asks for exactly the lane's own width in columns, so a
        // real incremental envelope would never draw more bars than there is room for. Drawing
        // one bar per accumulated sample instead turned variant C into a solid slab inside two
        // minutes — which would have been rejecting the design for the prototype's own artefact.
        let fills = Self.reduce(fills, to: Int(rect.width / 3))
        let slot = rect.width / CGFloat(fills.count)
        let barWidth = Swift.max(0.75, slot * 0.6)
        let mid = rect.midY
        let maxHalf = rect.height / 2

        for (i, fill) in fills.enumerated() {
            let half = Swift.max(0.5, CGFloat(Swift.min(1, Swift.max(0, fill))) * maxHalf)
            let x = rect.minX + slot * CGFloat(i) + (slot - barWidth) / 2
            let bar = CGRect(x: x, y: mid - half, width: barWidth, height: half * 2)
            path.addRoundedRect(in: bar,
                                cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2))
        }
        return path
    }

    /// Peak-reduce `fills` to at most `count` columns. Max, not mean, because a meter's job is to
    /// show the transient — averaging a bucket is what turns speech into a flat band.
    private static func reduce(_ fills: [Double], to count: Int) -> [Double] {
        guard count > 0, fills.count > count else { return fills }
        return (0..<count).map { i in
            let lo = fills.count * i / count
            let hi = Swift.max(lo + 1, fills.count * (i + 1) / count)
            return fills[lo..<Swift.min(hi, fills.count)].max() ?? 0
        }
    }
}

// MARK: - The switcher

/// The floating variant switcher: prev / name / next, plus ⌥← and ⌥→ (plain arrows belong to
/// the sidebar's selection). Deliberately unlike anything else in the window so it cannot be
/// mistaken for the design being judged, and compiled out of Release so a stray merge cannot
/// ship it.
struct CaptureLaneSwitcher: View {
    @State private var proto = CaptureLanePrototypeState.shared

    var body: some View {
        #if DEBUG
        HStack(spacing: 10) {
            Button { proto.cycle(-1) } label: { Image(systemName: "chevron.left") }
                .keyboardShortcut(.leftArrow, modifiers: .option)

            Text(proto.variant.title)
                .font(.caption).monospaced()
                .frame(width: 230)

            Button { proto.cycle(1) } label: { Image(systemName: "chevron.right") }
                .keyboardShortcut(.rightArrow, modifiers: .option)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.85), in: Capsule())
        .foregroundStyle(.white)
        .shadow(radius: 8)
        #endif
    }
}
