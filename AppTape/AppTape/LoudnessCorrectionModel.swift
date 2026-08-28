//
//  LoudnessCorrectionModel.swift
//  AppTape
//

import Foundation
import Observation

/// The Loudness correction **preview** for the editor (ADR-0013). The correction is a full BS.1770
/// pass where the size estimate is only arithmetic, so it cannot be shown instantly — it resolves
/// from `Measuring…` to a dB figure. This model owns that async measure for the current Recording
/// and Trim, so the inspector shows the figure and playback can apply the same correction.
///
/// It is keyed on `(url, trimmed frame range)`: a redraw with the same key does not re-measure, and a
/// new Trim or Recording supersedes the prior pass. Superseding **cancels the running measure** — the
/// pass runs on a detached `.utility` task whose own cancellation the BS.1770 loop polls, so it stops
/// filtering early and a dragging Trim handle over a long Recording does not pile up whole-range
/// passes. Only the resolved result hops back to the main actor, and only if its key still stands.
@MainActor
@Observable
final class LoudnessCorrectionModel {
    enum State: Equatable {
        /// Normalization is off — no figure is shown at all.
        case off
        /// A BS.1770 pass is running; the inspector shows `Measuring…`.
        case measuring
        /// Resolved: the clamped correction to show and to apply to playback.
        case measured(LoudnessCorrection)
    }

    private(set) var state: State = .off

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var currentKey: String?

    /// The resolved correction, or `nil` while off or measuring.
    var correction: LoudnessCorrection? {
        if case .measured(let correction) = state { return correction }
        return nil
    }

    /// The correction in dB to fold into playback — zero unless a correction has resolved. Playback
    /// adds the manual Gain to this and sets the sum as one `globalGain` (ADR-0013).
    var correctionDB: Double { correction?.decibels ?? 0 }

    /// Measures (or clears) the correction for a Recording's current Trim. Call it on any change to
    /// the selection, the Trim, or the normalize toggle; it dedupes an unchanged key so a redraw is
    /// free, and cancels a superseded pass so a dragging Trim handle does not pile up work.
    func update(recording: Recording, normalize: Bool) {
        guard normalize else {
            task?.cancel(); task = nil
            currentKey = nil
            state = .off
            return
        }
        let (start, count) = recording.trimmedFrameRange
        let url = recording.url
        let key = "\(url.path)|\(start)|\(count)"
        guard key != currentKey else { return }
        currentKey = key

        task?.cancel()
        state = .measuring
        task = Task.detached(priority: .utility) { [weak self] in
            // The measure polls this detached task's own cancellation, so a supersede stops it early.
            let measurement = (try? LoudnessMeter.measure(url: url, startFrame: start, frameCount: count,
                                                          isCancelled: { Task.isCancelled }))
                ?? LoudnessMeasurement(integratedLUFS: nil, truePeakDBTP: -.infinity)
            if Task.isCancelled { return }
            await MainActor.run {
                // Land the result only if this pass is still the current one (its key still stands).
                guard let self, self.currentKey == key else { return }
                self.state = .measured(LoudnessCorrection.compute(for: measurement))
            }
        }
    }
}
