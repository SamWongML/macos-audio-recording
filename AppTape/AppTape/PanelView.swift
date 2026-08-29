//
//  PanelView.swift
//  AppTape
//

import AppKit
import Combine
import SwiftUI

/// The hand-rolled panel's transport surface: the list *is* the panel and a row *is* the
/// record control — no button chrome (issue #6, variant H). Pressing a Source aims the tap at
/// its helper processes and starts a Recording; the pressed row then *is* the running Recording
/// — a pulsing `record.circle.fill` in a reserved trailing lane, over a live level meter — while
/// the one-click stop lives on the status item itself (issue #8, ADR-0004). The panel stays open
/// through a start so that transition is seen; it dismisses the ordinary transient way (outside
/// click, Escape, a right-click on the status item).
///
/// It honours **Reduce Transparency** — an opaque background instead of the popover's vibrant
/// material — and **Reduce Motion**, which stills the record glyph's pulse (issue #59).
struct PanelView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = SourceModel()
    private var recorder: RecordingController { .shared }
    /// Rescans the world for the list's live ordering (playing first). Slow enough not to churn.
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    /// Drives the pressed row's bring-up glyph across the ~500 ms in-flight threshold — `sincePress`
    /// advances with wall-clock time, which no `@Observable` change reports, so the view is nudged.
    /// Only bumps while recording, so it never re-renders the idle panel.
    private let recTick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    @State private var recNudge = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            blockingBanner
            sourceList
            Divider()
            footer
        }
        .frame(width: 280)
        // Reduce Transparency (issue #59): swap the popover's vibrant material for an opaque
        // window background. At rest the fill is clear so the material shows through as before.
        .background(reduceTransparency ? Color(nsColor: .windowBackgroundColor) : Color.clear)
        .onAppear {
            // Capture the SwiftUI open-window action so a status-item stop-click can open the
            // editor from AppKit (EditorPresenter).
            EditorPresenter.shared.bind(openWindow)
            model.refresh()
        }
        .onReceive(tick) { _ in model.refresh() }
        .onReceive(recTick) { _ in if recorder.isRecording { recNudge &+= 1 } }
        // An unrelated key handler, exactly the kind a real control adds: it silently takes
        // the popover's free Escape away (ADR-0011), which is why the app owns Escape in
        // MenuBarController. Kept to hold that guarantee honest as the panel grows.
        .onKeyPress(.space) { .ignored }
    }

    // MARK: - Header

    @ViewBuilder private var header: some View {
        if recorder.isRecording {
            HStack(spacing: 8) {
                Circle().fill(.red).frame(width: 9, height: 9)
                Text(recordingName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text(recorder.elapsedText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        } else {
            Text("Record")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)
        }
    }

    private var recordingName: String {
        model.sources.first { $0.bundleID == recorder.recordingSourceID }?.name ?? "Recording"
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
            LazyVStack(spacing: 0) {
                if model.sources.isEmpty {
                    Text("No applications running.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                } else {
                    ForEach(model.sources) { source in
                        // A Source with no HAL clients yet cannot be aimed at by object ID, so
                        // pressing it could do nothing. Show it dimmed and inert rather than
                        // swallow the press silently.
                        let capturable = !source.processObjectIDs.isEmpty
                        let isTarget = recorder.isRecording && recorder.recordingSourceID == source.bundleID
                        let glyph = RowRecordGlyph.state(
                            isRecordingTarget: isTarget,
                            sincePress: isTarget ? recorder.sincePress : nil,
                            hasFirstSound: recorder.hasFirstSound)
                        SourceRow(source: source,
                                  icon: model.icon(for: source),
                                  glyph: glyph,
                                  // Only the recording row carries live meter data; every other row's
                                  // meter is dead and reads zero (issue #59).
                                  meterColumns: isTarget ? recorder.meterColumns : [],
                                  reduceMotion: reduceMotion)
                            .opacity(capturable ? 1 : 0.4)
                            .contentShape(Rectangle())
                            .onTapGesture { if capturable { pick(source) } }
                        Divider().padding(.leading, 44)
                    }
                }
            }
        }
        .frame(maxHeight: 320)
    }

    /// While recording, the transport is busy: a press cannot start a second Recording (one
    /// Source at a time), so rows are inert until stop. On a start the panel stays open — the
    /// pressed row becomes the record control, showing bring-up then the live meter (issue #59);
    /// a start refused below the floor (ADR-0009) also stays open, for its banner.
    private func pick(_ source: Source) {
        guard !recorder.isRecording else { return }
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

/// One Source in the list. The row *is* the record control (issue #6, ADR-0011): icon, name,
/// then a fixed lane holding the live level meter and — in a reserved trailing sub-lane the
/// meter insets around, so it stays legible over the waveform — the record glyph. `circle` at
/// rest; a pulsing `record.circle.fill` once this row is the one recording (issue #59).
private struct SourceRow: View {
    let source: Source
    let icon: NSImage?
    let glyph: RowRecordGlyph.State
    /// Recent meter fills (0...1), oldest first — non-empty only for the recording row.
    let meterColumns: [Double]
    let reduceMotion: Bool

    /// The reserved trailing sub-lane the meter insets around, holding the record glyph.
    private let glyphLane: CGFloat = 26
    /// The whole meter-plus-glyph lane, so name width — and thus truncation — is consistent.
    private let laneWidth: CGFloat = 120

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let icon { Image(nsImage: icon).resizable() }
                else { Image(systemName: "app.dashed").resizable() }
            }
            .frame(width: 22, height: 22)

            Text(source.name)
                .font(.callout)
                .lineLimit(1)

            Spacer(minLength: 8)

            ZStack(alignment: .trailing) {
                meter
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.trailing, glyphLane)   // the waveform insets around the glyph lane
                recordGlyph
                    .frame(width: glyphLane)
            }
            .frame(width: laneWidth, height: 22)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    /// The live level meter. Empty (a dead or absent tap) draws nothing, which reads as exactly
    /// zero (issue #59) — so a non-recording row is flat and the recording row flattens the moment
    /// its tap goes silent.
    @ViewBuilder private var meter: some View {
        if meterColumns.contains(where: { $0 > 0 }) {
            LevelMeterShape(fills: meterColumns)
                .fill(Color.red.opacity(0.85))
        } else {
            Color.clear
        }
    }

    private var recordGlyph: some View {
        let filled = RowRecordGlyph.symbolName(glyph) != "circle"
        return Image(systemName: RowRecordGlyph.symbolName(glyph))
            .font(.system(size: 15))
            .foregroundStyle(filled ? Color.red : Color.secondary)
            // The in-flight/recording pulse (issue #59), stilled under Reduce Motion.
            .symbolEffect(.pulse, options: .repeating, isActive: RowRecordGlyph.pulses(glyph) && !reduceMotion)
    }
}

/// The row's live level meter, drawn as a compact scroll of vertical bars — one per recent meter
/// fill, oldest at the leading edge — mirrored around the centre line (issue #59). Deliberately
/// its own `Shape` rather than the audio-envelope `WaveformPath`: the input is a single 0...1 fill
/// per column, already dB-scaled by `LevelMeter`, not a reduced min/max/rms envelope, so nothing is
/// faked into an `Envelope.Column`. A `Shape`, not a `Canvas`, because a `Canvas` draws nothing
/// inside a lazy list row on macOS 27 (issue #7, see `WaveformView`).
private struct LevelMeterShape: Shape {
    /// Meter fills 0...1, oldest first.
    var fills: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !fills.isEmpty else { return path }
        let slot = rect.width / CGFloat(fills.count)
        let barWidth = Swift.max(1, slot * 0.6)
        let mid = rect.midY
        let maxHalf = rect.height / 2
        for (i, fill) in fills.enumerated() {
            let half = Swift.max(0.5, CGFloat(min(1, max(0, fill))) * maxHalf)
            let x = rect.minX + slot * CGFloat(i) + (slot - barWidth) / 2
            let bar = CGRect(x: x, y: mid - half, width: barWidth, height: half * 2)
            path.addRoundedRect(in: bar, cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2))
        }
        return path
    }
}
