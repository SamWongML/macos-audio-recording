//  PROTOTYPE — throwaway. Variant H: F's real waveform, with the record affordance the
//  record-affordance research recommends — no button chrome, no coloured capsule.

import SwiftUI

/// Variant H — the row *is* the record control.
///
/// Two research results meet here. From `record-affordance.md`: the primary action belongs
/// in the row, because the row already carries the motion and colour that told the person
/// "this app is making noise" — moving the control elsewhere makes them look away from it.
/// The glyph is kept legible over the moving waveform by **layout**, a trailing lane the
/// waveform is inset around, reinforced by a `.thinMaterial` puck — not by z-order.
///
/// The rejected big blue capsule is best read as a *size* violation rather than a colour
/// one: "Use style — not size — to visually distinguish the preferred choice among
/// multiple options" (HIG, Buttons: Style). So H removes the button chrome entirely rather
/// than shrinking it.
struct VariantH: View {
    static let title = "Row is the record control"
    @Bindable var model: SourceModel
    @State private var recordingID: String?
    @State private var hovered: String?
    @FocusState private var focused: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let laneWidth: CGFloat = 34
    private var monitor: LevelMonitor { .shared }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(recordingID == nil ? "Playing Audio" : "Recording").font(.headline)
                Spacer()
                if monitor.looksUnpermitted {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help("Taps are running but every sample is zero — System Audio Recording is probably not granted. There is no API to check.")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVStack(spacing: 2) {
                    if model.playing.isEmpty {
                        NothingPlaying()
                    } else {
                        ForEach(model.playing) { source in row(source) }
                    }
                }
                .padding(6)
            }
            .frame(height: 250)

            Divider()
            footer
        }
        .frame(width: 320)
        .onAppear { monitor.sync(with: model.sources) }
        .onChange(of: model.sources) { _, sources in monitor.sync(with: sources) }
    }

    /// The keyboard path, and only the keyboard path.
    ///
    /// This used to be a Record button that acted on `playing.first`, which is arbitrary
    /// the moment two apps are playing — the button named no target, so it was a guess
    /// wearing a label. It now acts strictly on the **focused** row (⇥ / ↑ / ↓ to move,
    /// ⏎ to fire) and says which app that is, so the target is never in doubt. With
    /// nothing focused there is nothing to record, and it says so instead of guessing.
    private var target: Source? {
        if let recordingID { return model.sources.first { $0.id == recordingID } }
        return model.playing.first { $0.id == focused }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let target {
                // Text + Text is soft-deprecated at macOS 26; interpolate instead.
                Text("\(recordingID == nil ? "Record" : "Recording") \(Text(target.name).foregroundStyle(.primary))")
                    .foregroundStyle(.secondary)
            } else {
                Text(model.playing.isEmpty ? "Nothing is playing" : "Select an app to record")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(recordingID == nil ? "Record" : "Stop") {
                recordingID = recordingID == nil ? target?.id : nil
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .keyboardShortcut(.defaultAction)
            .disabled(target == nil)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private func row(_ source: Source) -> some View {
        let isRecording = recordingID == source.id
        Button {
            recordingID = isRecording ? nil : source.id
        } label: {
            HStack(spacing: 10) {
                AppIcon(source: source, size: 28)
                Text(source.name).foregroundStyle(.primary)
                Spacer(minLength: 8)

                ZStack {
                    Circle().fill(.thinMaterial)
                    Image(systemName: isRecording ? "record.circle.fill" : "circle")
                        .font(.system(size: 17))
                        .foregroundStyle(isRecording ? AnyShapeStyle(.red)
                                                     : AnyShapeStyle(.secondary.opacity(hovered == source.id || focused == source.id ? 0.9 : 0.45)))
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.pulse, options: .repeating, isActive: isRecording)
                        .symbolEffectsRemoved(reduceMotion)
                }
                .frame(width: 26, height: 26)
            }
            .padding(.leading, 11)
            .padding(.trailing, (laneWidth - 26) / 2)
            .frame(height: 46)
            .background {
                ZStack {
                    if isRecording { Color.red.opacity(0.10) }
                    if let ring = monitor.ring(for: source.bundleID) {
                        WaveformBackground(ring: ring,
                                           isSelected: isRecording,
                                           trailingInset: laneWidth)
                    }
                }
            }
            .clipShape(.rect(cornerRadius: 9))
            .contentShape(.rect)
        }
        // Plain, so the row keeps list styling instead of acquiring button chrome.
        .buttonStyle(.plain)
        .focused($focused, equals: source.id)
        .onHover { hovered = $0 ? source.id : nil }
    }
}
