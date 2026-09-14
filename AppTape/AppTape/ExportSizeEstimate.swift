import Foundation

/// The live `≈ MB` size estimate shown beside the waveform. It is a **pure function of
/// the preset, the source format, and the trimmed duration** — and of nothing else. That is the
/// whole point of the type: Loudness and Gain never enter it, so the readout is invariant to them
/// by construction rather than by remembering not to pass them. It recomputes as a Trim
/// handle drags because the duration it is given changes, not because anything here is stateful.
enum ExportSizeEstimate {
    /// Container and header overhead over the raw codec payload ('s `× 1.02`).
    static let overhead = 1.02

    /// Estimated bytes for exporting `duration` seconds at `preset`, from a source of `format`.
    /// `bitrate × duration × 1.02`, in bytes. Negative or non-finite durations read as zero
    /// rather than producing a nonsense figure.
    static func bytes(preset: QualityPreset, format: SourceFormat, duration: Double) -> Double {
        guard duration.isFinite, duration > 0 else { return 0 }
        let bitsPerSecond = preset.estimatedBitsPerSecond(for: format)
        return bitsPerSecond * duration * overhead / 8
    }

    /// The estimate as `≈ 12.4 MB` — three significant figures, decimal units, matching how the
    /// ADRs speak of Export cost. The leading `≈` says out loud that the size is estimated, never
    /// promised (CONTEXT.md's Quality Preset).
    static func text(preset: QualityPreset, format: SourceFormat, duration: Double) -> String {
        "≈ \(sizeText(bytes: bytes(preset: preset, format: format, duration: duration)))"
    }

    /// `426 KB`, `12.4 MB`, `123 MB`, `1.90 GB` — three significant figures in decimal units, with
    /// the **unit following the number** rather than pinned to MB. Public so the pre-flight refusal
    /// can name both the estimate and the free space in the same units.
    static func sizeText(bytes: Double) -> String {
        let bytes = max(0, bytes)
        let kilobytes = bytes / 1_000
        if kilobytes < 1000 {
            // Sub-KB is still spoken of in KB — `0.004 KB` is a truer thing to show than `4 bytes`
            // for a figure that is explicitly an estimate.
            return "\(threeSigFigs(kilobytes)) KB"
        }
        let megabytes = kilobytes / 1_000
        if megabytes < 1000 {
            return "\(threeSigFigs(megabytes)) MB"
        }
        return "\(threeSigFigs(megabytes / 1_000)) GB"
    }

    /// Three significant figures, trailing zeros kept (`0.500`, `12.4`, `123`) so the readout does
    /// not jitter between two- and three-digit widths as a handle drags.
    private static func threeSigFigs(_ value: Double) -> String {
        value.formatted(.number.precision(.significantDigits(3)).grouping(.never))
    }
}
