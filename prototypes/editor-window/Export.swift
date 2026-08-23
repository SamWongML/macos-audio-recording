//  PROTOTYPE — throwaway. The Quality Presets and the live size estimate from issue #9.
//  Nothing is encoded here; Export is a stub because #27 owns what it does while it runs.

import Foundation
import SwiftUI

enum QualityPreset: String, CaseIterable, Identifiable {
    case master, high, standard, compact
    var id: Self { self }

    var title: String {
        switch self {
        case .master: "Master quality"
        case .high: "High"
        case .standard: "Standard"
        case .compact: "Compact"
        }
    }

    /// Visible as subtitle text, never editable (issue #9).
    var subtitle: String {
        switch self {
        case .master: "24-bit ALAC"
        case .high: "AAC 256 kbps"
        case .standard: "AAC 128 kbps"
        case .compact: "HE-AAC 64 kbps"
        }
    }

    var kilobitsPerSecond: Double? {
        switch self {
        case .master: nil
        case .high: 256
        case .standard: 128
        case .compact: 64
        }
    }

    /// Measured coefficient against the Float32 master. Issue #9 flagged that 0.46 came off
    /// a synthetic tone and wants a second look against real captured audio.
    var masterFraction: Double { 0.46 }

    func estimatedBytes(seconds: Double, sampleRate: Double, channels: Double) -> Int64 {
        if let kbps = kilobitsPerSecond {
            return Int64(kbps * 1000 / 8 * seconds * 1.02)
        }
        return Int64(seconds * sampleRate * channels * 4 * masterFraction)
    }
}

extension Recording {
    func estimate(_ preset: QualityPreset) -> Int64 {
        preset.estimatedBytes(seconds: trimmedDuration, sampleRate: sampleRate, channels: 2)
    }

    /// "≈ 12.4 MB" — three significant figures, per issue #9.
    func estimateText(_ preset: QualityPreset) -> String {
        let bytes = Double(estimate(preset))
        let mb = bytes / 1_000_000
        if mb >= 100 { return "≈ \(Int(mb.rounded())) MB" }
        if mb >= 10 { return String(format: "≈ %.1f MB", mb) }
        if mb >= 1 { return String(format: "≈ %.2f MB", mb) }
        return String(format: "≈ %.0f KB", bytes / 1000)
    }
}

/// Sticky app-wide preference (issue #9), not a property of a Recording.
@MainActor @Observable
final class ExportSettings {
    var preset: QualityPreset = .high
    /// Reserved by #24 / #25. Drawn but inert — the editor's job here is only to prove
    /// there is somewhere sensible for it to land.
    var normalizeLoudness = false
    var gain: Double = 0
    var lastMessage: String?

    func run(_ recording: Recording) {
        lastMessage = "PROTOTYPE — would export \(Format.time(recording.trimmedDuration)) "
            + "of “\(recording.name)” as \(preset.title) (\(recording.estimateText(preset)))"
        Diag.note(lastMessage!)
    }
}

/// Shared because every variant needs the same two facts; where it *sits* is the variable.
struct PresetPicker: View {
    var recording: Recording
    var settings: ExportSettings
    var style: Style = .menu

    enum Style { case menu, tabs, list }

    var body: some View {
        switch style {
        case .menu:
            Picker("Quality", selection: Bindable(settings).preset) {
                ForEach(QualityPreset.allCases) { preset in
                    Text("\(preset.title) — \(preset.subtitle)").tag(preset)
                }
            }
        case .tabs:
            Picker("Quality", selection: Bindable(settings).preset) {
                ForEach(QualityPreset.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        case .list:
            VStack(alignment: .leading, spacing: 2) {
                ForEach(QualityPreset.allCases) { preset in
                    let selected = settings.preset == preset
                    Button { settings.preset = preset } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(preset.title)
                                Text(preset.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(recording.estimateText(preset))
                                .font(.caption).monospacedDigit()
                                .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        }
                        .padding(.vertical, 4).padding(.horizontal, 8)
                        .background(selected ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(.clear),
                                    in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// The block #25 will design properly. Present here only to hold its ground.
struct LevelControlsStub: View {
    var settings: ExportSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Normalize loudness", isOn: Bindable(settings).normalizeLoudness)
            HStack {
                Text("Gain").foregroundStyle(settings.normalizeLoudness ? .primary : .secondary)
                Slider(value: Bindable(settings).gain, in: -12...12)
                Text(String(format: "%+.1f dB", settings.gain))
                    .font(.caption).monospacedDigit().frame(width: 58, alignment: .trailing)
            }
            Text("Reserved for #25 — not designed here.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
