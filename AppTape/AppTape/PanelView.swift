//
//  PanelView.swift
//  AppTape
//

import AppKit
import Combine
import SwiftUI

/// The hand-rolled panel's transport surface: the list *is* the panel and a row *is* the
/// record control — no button chrome (issue #6, variant H). The list shows the apps currently
/// playing audio, each painted behind by its own live waveform; pressing a row aims the tap at
/// that Source's helper processes and starts a Recording. The pressed row then *is* the running
/// Recording — a pulsing `record.circle.fill` in a reserved trailing lane, over a red row tint —
/// while the one-click stop and the `● MM:SS` clock live on the status item itself (issue #8,
/// ADR-0004). The panel stays open through a start so that transition is seen; it dismisses the
/// ordinary transient way (outside click, Escape, a right-click on the status item).
///
/// The per-row waveforms come from `SourceLevelMonitor`, which opens a Core Audio probe per
/// playing app — so the System Audio Recording prompt can appear when the panel is opened over
/// playing audio, before record is pressed. That is the prototype's chosen behaviour (issue #6),
/// deliberately traded against spec story #14. The monitor runs only while the panel is on screen.
///
/// It honours **Reduce Transparency** — an opaque background instead of the popover's vibrant
/// material — and **Reduce Motion**, which stills the record glyph's pulse (issue #59).
struct PanelView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = SourceModel()
    /// The live per-Source amplitude for the row waveforms. Owned here so it runs only while the
    /// panel is on screen and holds no taps at rest.
    @State private var monitor = SourceLevelMonitor()
    private var recorder: RecordingController { .shared }
    /// Rescans the world for the list's live ordering (playing first). Slow enough not to churn.
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    /// Drives the pressed row's bring-up glyph across the ~500 ms in-flight threshold — `sincePress`
    /// advances with wall-clock time, which no `@Observable` change reports, so the view is nudged.
    /// Only bumps while recording, so it never re-renders the idle panel.
    private let recTick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    @State private var recNudge = 0

    /// The Sources the list shows: those currently playing audio (issue #6, variant H). A Source
    /// that is running but silent is not listed — the header says so when none are playing.
    private var playing: [Source] { model.sources.filter(\.isPlaying) }

    /// The bundle ID being recorded, if any — excluded from the monitor (its level comes from the
    /// recording tap) and painted with the recording tint.
    private var recordingBundleID: String? { recorder.isRecording ? recorder.recordingSourceID : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            blockingBanner
            sourceList
            Divider()
            footer
        }
        .frame(width: 320)
        // Reduce Transparency (issue #59): swap the popover's vibrant material for an opaque
        // window background. At rest the fill is clear so the material shows through as before.
        .background(reduceTransparency ? Color(nsColor: .windowBackgroundColor) : Color.clear)
        .onAppear {
            // Capture the SwiftUI open-window action so a status-item stop-click can open the
            // editor from AppKit (EditorPresenter).
            EditorPresenter.shared.bind(openWindow)
            model.refresh()
            monitor.sync(with: model.sources, excluding: recordingBundleID)
        }
        .onDisappear { monitor.stopAll() }
        .onReceive(tick) { _ in
            model.refresh()
            monitor.sync(with: model.sources, excluding: recordingBundleID)
        }
        .onReceive(recTick) { _ in if recorder.isRecording { recNudge &+= 1 } }
        // An unrelated key handler, exactly the kind a real control adds: it silently takes
        // the popover's free Escape away (ADR-0011), which is why the app owns Escape in
        // MenuBarController. Kept to hold that guarantee honest as the panel grows.
        .onKeyPress(.space) { .ignored }
    }

    // MARK: - Header

    /// The list's title, swapping to "Recording" while a Recording runs (issue #6, variant H) —
    /// the running clock and the stop live on the status item (ADR-0004), not here. The lock
    /// appears when the probes are running but every sample is zero, the only signal that the
    /// System Audio Recording grant is missing (issue #3).
    @ViewBuilder private var header: some View {
        HStack {
            Text(recorder.isRecording ? "Recording" : "Playing Audio")
                .font(.headline)
            Spacer()
            if monitor.looksUnpermitted {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help("Probes are running but every sample is zero — System Audio Recording is "
                          + "probably not granted. There is no API to check.")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Blocking banner

    /// The panel's one blocking-message surface (ADR-0009). **At most one reason is ever set**: a
    /// refusal below the floor and a denial each clear the other, and a successful start clears both,
    /// so the two never compete here. What should happen *if* two blocking reasons ever did compete is
    /// ADR-0009's deferral to issue #22, not decided by this ordering — which only picks a branch when,
    /// by construction, just one arm can be taken.
    @ViewBuilder private var blockingBanner: some View {
        if let refusal = recorder.startRefusal {
            diskRefusalBanner(refusal)
        } else if recorder.permissionRecovery {
            recoveryBanner
        }
    }

    /// Shown when a start is refused below the 2 GB floor (ADR-0009). It names the free space and the
    /// floor, and its action opens Finder at the Library rather than a Settings pane — there being
    /// none to send the user to. Retry, as with the denial banner, is simply pressing record again.
    @ViewBuilder private func diskRefusalBanner(_ refusal: DiskGuardRefusal) -> some View {
        banner(title: refusal.title, message: refusal.message, action: "Show in Finder") {
            FaultNotifier.revealLibrary()
        }
    }

    /// Shown when a denied System Audio Recording grant was inferred (ADR-0008). It names
    /// "System Audio Recording Only" — not the pane's own broader heading — and the deep-link
    /// button lands on the audio-capture pane. Retry is not a button here: it is pressing record
    /// again, which is where the copy sends the user.
    @ViewBuilder private var recoveryBanner: some View {
        banner(title: PermissionRecovery.title, message: PermissionRecovery.message,
               action: "Open System Settings") {
            if let url = PermissionRecovery.settingsURL { NSWorkspace.shared.open(url) }
        }
    }

    /// The shared banner chrome for both blocking reasons: a bold title, secondary body, and one link
    /// action, over the panel's control-background fill.
    @ViewBuilder private func banner(title: String, message: String, action: String,
                                     perform: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.callout.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action, action: perform)
                .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        Divider()
    }

    // MARK: - Source list

    private var sourceList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if playing.isEmpty {
                    NothingPlaying()
                } else {
                    ForEach(playing) { source in
                        let isTarget = recorder.isRecording && recorder.recordingSourceID == source.bundleID
                        let glyph = RowRecordGlyph.state(
                            isRecordingTarget: isTarget,
                            sincePress: isTarget ? recorder.sincePress : nil,
                            hasFirstSound: recorder.hasFirstSound)
                        // The recording row's waveform comes from the recording tap's own meter, so no
                        // second tap is opened on it; every other playing row comes from the monitor.
                        let samples: [Float] = isTarget
                            ? recorder.meterColumns.map(Float.init)
                            : (monitor.waveforms[source.bundleID] ?? [])
                        SourceRow(source: source,
                                  icon: model.icon(for: source),
                                  glyph: glyph,
                                  samples: samples,
                                  isRecording: isTarget,
                                  reduceMotion: reduceMotion,
                                  onPick: { pick(source) })
                    }
                }
            }
            .padding(6)
        }
        .frame(height: 296)
    }

    /// While recording, the transport is busy: a press cannot start a second Recording (one
    /// Source at a time), so rows are inert until stop. On a start the panel stays open — the
    /// pressed row becomes the record control, showing bring-up then the live meter (issue #59);
    /// a start refused below the floor (ADR-0009) also stays open, for its banner.
    private func pick(_ source: Source) {
        guard !recorder.isRecording else { return }
        // Hand the recording tap sole ownership of this Source's audio: drop the monitor's probe on
        // it so two taps never contend, then start.
        monitor.sync(with: model.sources, excluding: source.bundleID)
        recorder.start(source)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Open Editor") { openWindow(id: AppTapeApp.editorWindowID) }
                .buttonStyle(.link)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.link)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// One Source in the list. The row *is* the record control (issue #6, ADR-0011): icon, name, then
/// a fixed trailing lane holding the record glyph — `circle` at rest, a pulsing `record.circle.fill`
/// once this row is the one recording (issue #59). Behind the whole row runs its live amplitude
/// waveform, inset out of the glyph lane so the glyph stays legible over the moving signal.
private struct SourceRow: View {
    let source: Source
    let icon: NSImage?
    let glyph: RowRecordGlyph.State
    /// Live amplitude samples (0...1), oldest first — the monitor's trace, or the recording tap's
    /// meter for the row being recorded. Empty reads as a flat (silent) row.
    let samples: [Float]
    let isRecording: Bool
    let reduceMotion: Bool
    let onPick: () -> Void

    @State private var hovered = false

    /// The trailing lane the waveform is inset around, so the record affordance sits in clear space
    /// rather than on top of moving pixels (issue #6, variant H).
    private let laneWidth: CGFloat = 34

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let icon { Image(nsImage: icon).resizable() }
                else { Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary) }
            }
            .frame(width: 28, height: 28)

            Text(source.name)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            ZStack {
                if hovered { Circle().fill(.primary.opacity(0.12)) }
                recordGlyph
            }
            .frame(width: 26, height: 26)
        }
        .padding(.leading, 11)
        .padding(.trailing, (laneWidth - 26) / 2)
        .frame(height: 46)
        .background {
            ZStack {
                if isRecording { Color.red.opacity(0.10) }
                WaveformBackground(samples: samples, isSelected: isRecording, trailingInset: laneWidth)
            }
        }
        .clipShape(.rect(cornerRadius: 9))
        .contentShape(.rect)
        .onHover { hovered = $0 }
        .onTapGesture(perform: onPick)
    }

    private var recordGlyph: some View {
        let filled = RowRecordGlyph.symbolName(glyph) != "circle"
        return Image(systemName: RowRecordGlyph.symbolName(glyph))
            .font(.system(size: 17))
            .foregroundStyle(filled ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            .contentTransition(.symbolEffect(.replace))
            // The in-flight/recording pulse (issue #59), stilled under Reduce Motion.
            .symbolEffect(.pulse, options: .repeating,
                          isActive: RowRecordGlyph.pulses(glyph) && !reduceMotion)
    }
}

/// A real amplitude waveform, mirrored around the row's centre line, drawn behind the row's content.
/// Low-opacity and masked to fade out under the icon and name on the leading edge, leaving the
/// trailing stretch — where there is no text — carrying the signal.
///
/// A `Shape`, not a `Canvas`: a `Canvas` draws nothing inside a lazy list row on macOS 27
/// (issue #7, see `WaveformView`), and the fill gradient a `Shape` takes is all this needs.
private struct WaveformBackground: View {
    var samples: [Float]
    var isSelected: Bool
    /// Width at the trailing edge the waveform must not draw into, so the record affordance sits in
    /// clear space rather than on top of moving pixels.
    var trailingInset: CGFloat = 0

    var body: some View {
        RowWaveformShape(samples: samples)
            .fill(LinearGradient(
                gradient: Gradient(colors: [.accentColor.opacity(0.05), .accentColor.opacity(0.55)]),
                startPoint: .leading, endPoint: .trailing))
            .opacity(isSelected ? 0.9 : 0.6)
            .mask(LinearGradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black.opacity(0.35), location: 0.28),
                .init(color: .black, location: 0.55),
                .init(color: .black, location: 1.0),
            ], startPoint: .leading, endPoint: .trailing))
            .padding(.trailing, trailingInset)
    }
}

/// The mirrored, filled waveform outline. Quadratic segments through the sample midpoints — a
/// straight polyline at this density reads jagged; the curve is what makes it a waveform rather
/// than a chart.
private struct RowWaveformShape: Shape {
    var samples: [Float]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard samples.count > 1 else { return path }

        let midY = rect.midY
        let step = rect.width / CGFloat(samples.count - 1)

        func point(_ index: Int, mirrored: Bool) -> CGPoint {
            let amplitude = CGFloat(samples[index]) * (rect.height / 2) * 0.92
            return CGPoint(x: rect.minX + CGFloat(index) * step,
                           y: mirrored ? midY + amplitude : midY - amplitude)
        }

        func trace(_ path: inout Path, mirrored: Bool, reversed: Bool) {
            let indices = reversed ? Array(samples.indices.reversed()) : Array(samples.indices)
            guard let first = indices.first else { return }
            path.addLine(to: point(first, mirrored: mirrored))
            for offset in 1..<indices.count {
                let previous = point(indices[offset - 1], mirrored: mirrored)
                let current = point(indices[offset], mirrored: mirrored)
                let midpoint = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
                path.addQuadCurve(to: midpoint, control: previous)
            }
            path.addLine(to: point(indices[indices.count - 1], mirrored: mirrored))
        }

        path.move(to: CGPoint(x: rect.minX, y: midY))
        trace(&path, mirrored: false, reversed: false)
        trace(&path, mirrored: true, reversed: true)
        path.closeSubpath()
        return path
    }
}

/// The empty state: when nothing is playing, say so rather than show a blank list under a header
/// that claims "Playing Audio" (issue #6, variant H).
private struct NothingPlaying: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "speaker.slash")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text("No app is playing audio")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }
}
