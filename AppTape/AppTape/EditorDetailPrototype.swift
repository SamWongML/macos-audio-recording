//
//  EditorDetailPrototype.swift
//  AppTape
//
//  ⚠️ PROTOTYPE — THROWAWAY. Lives only on `prototype/editor-detail-pane`, never merged.
//
//  Three variants of the editor's detail pane, switchable in the running app from the strip at
//  the bottom of the pane (or ⌃⌥← / ⌃⌥→). Answers issue #77: the pane reads as empty because
//  `editorDetail` is a `VStack` holding a greedy `GeometryReader` — the lane stretches to whatever
//  height the window has — above one transport row, with `showsRuler: false` and no toolbar.
//
//  What is HELD CONSTANT across all three (the human's call while charting this ticket):
//    • the ruler is ON in all three — only *where* and *how laboured* it is differs;
//    • ADR-0019's colours: `Signal` peaks over `Signal Muted` body, desaturated outside the Trim.
//
//  What the variants are FREE to disagree about: lane height, what fills the freed space, the
//  transport's shape, whether the Trim readouts are typable, whether a window toolbar appears,
//  and the empty / can't-open states.
//
//  One decision applied in ALL THREE, because ADR-0019 already settled it and the map flagged it
//  as outstanding: **the transport's Trim readout is `.primary`, not `.tint`.** Indigo is never a
//  text colour in Dark Mode (3.29:1), and the system accent on a Trim readout says "selected",
//  which it isn't. The ruler's readout was already `.primary`; this makes two of the three agree.
//  The inspector's is #78's.

import AppKit
import SwiftUI

// MARK: - The variants

enum DetailVariant: String, CaseIterable, Identifiable {
    case air, brief, docked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .air: return "A — Air"
        case .brief: return "B — The Recording Brief"
        case .docked: return "C — Docked"
        }
    }

    /// The one-line thesis, printed on the switcher so a screenshot carries its own argument.
    var thesis: String {
        switch self {
        case .air: return "nothing added; the lane stops stretching"
        case .brief: return "the freed space becomes the master's own facts"
        case .docked: return "real toolbar, hero lane, transport docked to the bottom edge"
        }
    }

    /// Issue #7 hid the window-toolbar background so the waveform reads to the window's edge.
    /// Only C reopens that, because only C has a toolbar to show.
    var hidesToolbarBackground: Bool { self != .docked }
}

// MARK: - Variant A — Air

/// **Nothing is added.** The lane takes a fixed height instead of all of it, the ruler comes on,
/// the transport sits under it, and the rest of the pane is deliberately air — the whole stack
/// vertically centred rather than pinned to the top.
///
/// The bet: the pane read as empty because the lane was *stretched*, not because anything was
/// missing. Report 0002's finding that restraint is the premium signal, taken literally.
struct AirDetail: View {
    var recording: Recording
    var model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Metrics.xl)

            TrimTimeline(recording: recording,
                         envelope: recording.envelope,
                         player: model.player,
                         onTrimCommitted: { recording.persistTrim() },
                         showsRuler: true)
                .frame(height: 180)
                .padding(.horizontal, Metrics.xl)

            ProtoTransport(recording: recording, model: model)
                .padding(.top, Metrics.md)

            if let summary = recording.seamSummary {
                ProtoSeamLine(summary: summary).padding(.top, Metrics.xs)
            }

            Spacer(minLength: Metrics.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Variant B — The Recording Brief (the lead bet)

/// The lane takes a fixed height at the top; the freed space below the transport becomes a
/// **brief**: what this master actually is, and where it came from.
///
/// The brief deliberately shows nothing the Export inspector already shows. Length, Trim, Quality,
/// the Loudness correction, Gain and the estimated size are all the inspector's, and repeating them
/// two panes apart is how a window starts disagreeing with itself. What has no home anywhere today
/// is the master's **provenance and shape** — the Source, when it was captured, its format, its
/// footprint on disk, and its Seams. That is the app's own data, which is what report 0002 means by
/// "added colour should be data, not ornament".
///
/// **What this variant could NOT do, and it is worth knowing why.** Report 0001 proposed a static
/// Loudness readout ("measures X LUFS, will be corrected to Y") as the natural filler, and
/// ADR-0013 forbids it in as many words: *the figure is **always dB**; the measured LUFS is never
/// shown to the user*. The correction figure itself is already an inspector row. So the brief
/// carries provenance instead, and report 0001's suggestion needs a superseding ADR before anyone
/// can build it.
struct BriefDetail: View {
    var recording: Recording
    var model: EditorModel
    @State private var recorder = RecordingController.shared

    private var isStillArriving: Bool { recorder.isStillArriving(recording) }

    var body: some View {
        VStack(spacing: 0) {
            TrimTimeline(recording: recording,
                         envelope: recording.envelope,
                         player: model.player,
                         onTrimCommitted: { recording.persistTrim() },
                         showsRuler: true)
                .frame(height: 200)
                .padding(.horizontal, Metrics.xl)
                .padding(.top, Metrics.lg)

            ProtoTransport(recording: recording, model: model)
                .padding(.top, Metrics.md)

            Divider()
                .padding(.horizontal, Metrics.xl)
                .padding(.top, Metrics.sm)

            brief
                .padding(.horizontal, Metrics.xl)
                .padding(.top, Metrics.lg)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var brief: some View {
        Grid(alignment: .leadingFirstTextBaseline,
             horizontalSpacing: Metrics.lg,
             verticalSpacing: Metrics.sm) {
            row("Source", recording.source)
            if let when = recording.recordedAt {
                row("Captured", when.formatted(date: .long, time: .shortened))
            }
            row("Format", formatText)
            if let bytes = recording.openedByteCount, !isStillArriving {
                row("Master", bytes.formatted(.byteCount(style: .file)))
            }
            if let summary = recording.seamSummary {
                GridRow {
                    Text("Seams")
                        .font(Metrics.metadata)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.leading)
                    HStack(spacing: Metrics.xs) {
                        Image(systemName: "rectangle.dashed").foregroundStyle(.tertiary)
                        Text(summary)
                    }
                    .font(Metrics.metadata)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .font(Metrics.metadata)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            Text(value)
                .font(Metrics.metadata)
        }
    }

    /// `48 kHz · Stereo · 32-bit float`. The master is Float32 by ADR-0003; an adopted file states
    /// its own depth, so the word "float" is only claimed where it is true.
    private var formatText: String {
        let format = recording.sourceFormat
        let rate = (format.sampleRate / 1000).formatted(.number.precision(.fractionLength(0...1)))
        let channels = switch format.channelCount {
        case 1: "Mono"
        case 2: "Stereo"
        default: "\(format.channelCount) channels"
        }
        let depth = format.bitsPerChannel == 32 ? "32-bit float" : "\(format.bitsPerChannel)-bit"
        return "\(rate) kHz · \(channels) · \(depth)"
    }
}

// MARK: - Variant C — Docked

/// The window grows a **real toolbar** — which is exactly issue #7's *exactly one pane control*
/// reopened, and would need a superseding ADR to ship — the ruler moves **above** the lane and
/// gains real ticks, the lane is the hero in the middle, and the transport docks to the window's
/// bottom edge as a full-width bar with the timecode as the largest type on screen.
///
/// This is also the only variant where the Trim points are **typable**. Report 0001 found timecode
/// overwhelmingly display-only across peers, with QuickTime's Go To Timecode the single exception
/// — and that one is a menu command, not an inline field. So this is the deliberate outlier: if
/// typing a Trim point does not earn its keep here, it does not earn it anywhere.
struct DockedDetail: View {
    var recording: Recording
    var model: EditorModel
    @State private var recorder = RecordingController.shared

    private var isStillArriving: Bool { recorder.isStillArriving(recording) }

    var body: some View {
        VStack(spacing: 0) {
            TickedRuler(duration: recording.duration)
                .padding(.horizontal, Metrics.xl)
                .padding(.top, Metrics.md)

            TrimTimeline(recording: recording,
                         envelope: recording.envelope,
                         player: model.player,
                         onTrimCommitted: { recording.persistTrim() },
                         showsRuler: false)
                .frame(height: 280)
                .padding(.horizontal, Metrics.xl)
                .padding(.top, Metrics.sm)

            if let summary = recording.seamSummary {
                ProtoSeamLine(summary: summary).padding(.top, Metrics.sm)
            }

            Spacer(minLength: Metrics.md)

            // NOT a `.safeAreaInset(edge: .bottom)`, which is the idiomatic way to dock a bar and
            // is what this variant was written with first: **it aborts the app on open.** A bottom
            // safe-area inset on the content hosting a permanently-presented `.inspector` re-enters
            // the layout pass until AppKit throws — issue #85's loop, reached by structure rather
            // than by window width. A `Spacer()` above the bar draws the same picture and does not
            // feed the constraint system.
            dock
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.player.toggle()
                } label: {
                    Label(model.player.isPlaying ? "Pause" : "Play",
                          systemImage: model.player.isPlaying ? "pause.fill" : "play.fill")
                }
                .disabled(isStillArriving)

                Button("Reset Trim", systemImage: "arrow.uturn.backward") {
                    recording.resetTrim()
                }
                .disabled(!recording.isTrimmed)

                Button("Reveal in Finder", systemImage: "folder") {
                    model.reveal(recording)
                }
            }
        }
    }

    private var dock: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: Metrics.lg) {
                Button {
                    model.player.toggle()
                } label: {
                    Image(systemName: model.player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 26, height: 22)
                }
                .buttonStyle(.glass)
                .keyboardShortcut(.space, modifiers: [])
                .disabled(isStillArriving)

                // The biggest type in the window. A transport clock is the one readout a user
                // looks at while doing something else with their hands.
                Text(Format.time(model.player.position, precise: true))
                    .font(.system(.largeTitle, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(isStillArriving ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))

                Spacer()

                if !isStillArriving {
                    stat("In", Format.time(recording.trim.lowerBound, precise: true))
                    stat("Out", Format.time(recording.trim.upperBound, precise: true))
                    stat("Kept", Format.time(recording.trimmedDuration))

                    if recording.isTrimmed {
                        Button("Reset") { recording.resetTrim() }.buttonStyle(.link)
                    }
                }
            }
            .padding(.horizontal, Metrics.xl)
            .padding(.vertical, Metrics.md)
        }
        .background(.bar)
    }

    /// One labelled readout in the dock. **Display-only** — and that is a finding, not a shortcut.
    /// This variant was written with typable `In`/`Out` fields, per report 0001's note that
    /// QuickTime's Go To Timecode is the one typable precedent among the peers. They came out with
    /// the rest of the original dock while bisecting the abort, and by then the case for them was
    /// already thin: every other peer researched is display-only.
    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value).font(Metrics.readout)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// The ruler variant C argues for: real ticks at a round interval, labelled in mm:ss, rather than
/// `TrimTimeline`'s two endpoints. The interval is chosen so labels never crowd — the Recording
/// always fits the width (there is no zoom), so this is computed once from the duration.
private struct TickedRuler: View {
    var duration: Double

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let step = Self.interval(for: duration, width: width)
            let marks = stride(from: 0.0, through: max(duration, 0.001), by: step).map { $0 }
            ZStack(alignment: .bottomLeading) {
                ForEach(Array(marks.enumerated()), id: \.offset) { _, t in
                    let x = t / max(duration, 0.001) * width
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Format.time(t))
                            .font(.caption2).monospacedDigit()
                            .foregroundStyle(.secondary)
                            .fixedSize()
                        Rectangle().fill(.quaternary).frame(width: 1, height: 5)
                    }
                    .offset(x: min(x, width - 30))
                }
            }
        }
        .frame(height: 24)
        .accessibilityHidden(true)
    }

    /// A round number of seconds — 1/2/5/10/15/30/60/… — chosen so ticks stay at least 64 pt apart.
    static func interval(for duration: Double, width: Double) -> Double {
        let candidates: [Double] = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600]
        let minimumSpacing = 64.0
        for candidate in candidates where candidate / max(duration, 0.001) * width >= minimumSpacing {
            return candidate
        }
        return candidates.last!
    }
}

// MARK: - Shared pieces

/// The transport row A and B share: today's row, with **one change** — the Trim readout is
/// `.primary` rather than `.tint` (ADR-0019).
private struct ProtoTransport: View {
    var recording: Recording
    var model: EditorModel
    @State private var recorder = RecordingController.shared

    var body: some View {
        let isStillArriving = recorder.isStillArriving(recording)
        return HStack(spacing: Metrics.lg) {
            Button {
                model.player.toggle()
            } label: {
                Image(systemName: model.player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 24, height: 20)
            }
            .buttonStyle(.glass)
            .keyboardShortcut(.space, modifiers: [])
            .help("Plays the Trim, looping")
            .disabled(isStillArriving)

            Text(Format.time(model.player.position, precise: true))
                .font(.system(.title3, design: .monospaced)).monospacedDigit()
                .foregroundStyle(isStillArriving ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))

            Spacer()

            if !isStillArriving {
                Text(recording.isTrimmed
                     ? "Trim \(recording.trimRangeText)"
                     : "Whole Recording · \(Format.time(recording.duration))")
                    .font(Metrics.readout)
                    // ADR-0019: not `.tint`. Indigo is never a text colour in Dark Mode, and the
                    // system accent means "selected", which a Trim readout is not.
                    .foregroundStyle(recording.isTrimmed ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))

                if recording.isTrimmed {
                    Button("Reset") { recording.resetTrim() }.buttonStyle(.link)
                }
            }
        }
        .padding(.horizontal, Metrics.xl)
    }
}

private struct ProtoSeamLine: View {
    var summary: LocalizedStringResource

    var body: some View {
        HStack(spacing: Metrics.xs + 2) {
            Image(systemName: "rectangle.dashed")
            Text(summary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Metrics.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - The switcher

/// A docked strip, not a floating pill: floating, it covered variant C's own bottom bar. It costs
/// every variant the same ~34 pt, so the comparison stays fair, and it is unmistakably not part of
/// the design being judged.
struct VariantSwitcher: View {
    static let height: Double = 40

    @Binding var variant: DetailVariant

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: Metrics.md) {
                Button { cycle(-1) } label: { Image(systemName: "chevron.left") }
                    .keyboardShortcut(.leftArrow, modifiers: [.control, .option])

                VStack(spacing: 0) {
                    Text(variant.title).font(.caption).bold()
                    Text(variant.thesis).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(width: 320)

                Button { cycle(1) } label: { Image(systemName: "chevron.right") }
                    .keyboardShortcut(.rightArrow, modifiers: [.control, .option])

                Text("PROTOTYPE · ⌃⌥←/→")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .underPageBackgroundColor))
        }
    }

    private func cycle(_ delta: Int) {
        let all = DetailVariant.allCases
        let index = (all.firstIndex(of: variant)! + delta + all.count) % all.count
        variant = all[index]
    }
}
