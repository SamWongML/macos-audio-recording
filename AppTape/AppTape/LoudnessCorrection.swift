//
//  LoudnessCorrection.swift
//  AppTape
//

import Foundation

/// The Export loudness contract's fixed numbers (ADR-0013). The target and ceiling are identical
/// across all four Quality Presets — Loudness and quality are independent axes.
enum LoudnessTarget {
    /// Target integrated loudness, in LUFS.
    static let integratedLUFS = -16.0
    /// The Ceiling (CONTEXT.md): the highest true peak, in dBTP, the correction lets the audio reach.
    static let truePeakDBTP = -3.0
    /// The Amplification cap (CONTEXT.md): the largest boost a correction applies, so a very quiet,
    /// noisy Recording is left below target rather than having its noise floor lifted into audibility.
    static let amplificationCapDB = 12.0
}

/// What a BS.1770 pass measured over a trimmed range: the integrated loudness (undefined for a
/// silent or too-short range) and the 4× oversampled true peak that the ceiling clamps against.
struct LoudnessMeasurement: Equatable {
    /// Integrated loudness in LUFS, or `nil` when the range is **unmeasurable** — silent under the
    /// −70 LKFS gate, or shorter than one 400 ms gating block. An undefined measurement drives a
    /// 0 dB correction, never an invented one (ADR-0013).
    let integratedLUFS: Double?
    /// Maximum true peak in dBTP. `-.infinity` for pure silence.
    let truePeakDBTP: Double
}

/// The **single fixed linear gain** a normalized Export (and matching playback) applies to a
/// trimmed range (ADR-0013). It is one clamped scalar, never a limiter: amplify toward the target
/// capped at +12 dB, attenuate uncapped, and where the gain would breach the −3 dBTP ceiling it is
/// clamped down and the range lands short of the loudness target rather than reshaping the waveform.
///
/// The manual **Gain** (CONTEXT.md) is a separate axis that rides on top of this — it is not folded
/// in here, so each figure stays legible as its own decibel value.
struct LoudnessCorrection: Equatable {
    /// How the correction landed relative to the target, so the inspector can caption *why* it fell
    /// short. The three land-short cases are distinct on purpose: the cap guards hiss, the ceiling
    /// guards clipping, and an undefined range has nothing to correct at all.
    enum Landing: Equatable {
        /// Reached the target exactly — the figure shows alone, no caption.
        case full
        /// The +12 dB amplification cap bound the gain (a very quiet, noisy range left below target).
        case amplificationCapped
        /// The −3 dBTP ceiling bound the gain (a peaky range clamped short of the loudness target).
        case ceilingReached
        /// The range was too quiet or too short to measure — 0 dB, and Export still completes.
        case undefined
    }

    /// The correction in dB. Zero when the landing is `.undefined`.
    let decibels: Double
    let landing: Landing

    /// Computes the clamped gain for a measurement against the fixed contract (ADR-0013). Defaults
    /// are the shipped numbers; parameters exist so a test can drive the boundary directly.
    static func compute(for measurement: LoudnessMeasurement,
                        target: Double = LoudnessTarget.integratedLUFS,
                        ceiling: Double = LoudnessTarget.truePeakDBTP,
                        cap: Double = LoudnessTarget.amplificationCapDB) -> LoudnessCorrection {
        // An undefined measurement gets no correction — never one invented from a missing figure.
        guard let integrated = measurement.integratedLUFS else {
            return LoudnessCorrection(decibels: 0, landing: .undefined)
        }

        let desired = target - integrated
        // Applying g dB moves the true peak to `truePeak + g`; the ceiling caps that at −3 dBTP, so
        // the largest gain the ceiling permits is `ceiling − truePeak`. This can be negative when a
        // range was captured hotter than the ceiling, forcing attenuation even where we meant to boost.
        let ceilingLimit = ceiling - measurement.truePeakDBTP

        // Attenuation is uncapped (it lowers noise with signal); the ceiling can only ask for *more*.
        if desired <= 0 {
            let gain = min(desired, ceilingLimit)
            let landing: Landing = gain < desired - 1e-9 ? .ceilingReached : .full
            return LoudnessCorrection(decibels: gain, landing: landing)
        }

        // Amplify toward the target, capped at +12 dB, then clamped under the ceiling.
        let capped = min(desired, cap)
        let gain = min(capped, ceilingLimit)
        let landing: Landing
        if gain < desired - 1e-9 {
            // Bound short. The ceiling is the tighter constraint when it undercuts the +12 dB cap.
            landing = ceilingLimit < capped - 1e-9 ? .ceilingReached : .amplificationCapped
        } else {
            landing = .full
        }
        return LoudnessCorrection(decibels: gain, landing: landing)
    }

    // MARK: - Rendering (dB, never LUFS)

    /// The correction as its own decibel figure (`+4.2 dB`), or `No correction` when undefined. The
    /// figure is **always dB** — the measured LUFS is never shown to the user (ADR-0013).
    var figureText: String {
        landing == .undefined ? "No correction" : Self.signedDecibels(decibels)
    }

    /// The one land-short caption for this case, or `nil` for a full hit. Distinct per case so the
    /// user can tell hiss-guarding from clip-guarding.
    var caption: String? {
        switch landing {
        case .full: return nil
        case .amplificationCapped: return "limited to keep the noise floor down"
        case .ceilingReached: return "peak ceiling reached"
        case .undefined: return "range too quiet to measure"
        }
    }

    /// `+4.2 dB`, `0.0 dB`, `−2.5 dB` — one fraction digit, always signed, so a correction and the
    /// manual Gain read as the same kind of figure.
    static func signedDecibels(_ value: Double) -> String {
        let magnitude = value.formatted(.number.precision(.fractionLength(1)))
        // Normalise the sign so 0 shows without a leading "+", negatives use a real minus glyph.
        let signed: String
        if value > 0.05 { signed = "+\(magnitude)" }
        else if value < -0.05 { signed = magnitude.replacingOccurrences(of: "-", with: "−") }
        else { signed = "0.0" }
        return "\(signed) dB"
    }

    /// The one linear scalar that composes the Loudness correction and the manual Gain — a single
    /// multiply, so stacking the two never double-normalizes (ADR-0013). Play applies exactly this
    /// as `AVAudioUnitEQ.globalGain`; Export applies exactly this in its write loop.
    static func linearScalar(correctionDB: Double, gainDB: Double) -> Float {
        Float(pow(10.0, (correctionDB + gainDB) / 20.0))
    }
}
