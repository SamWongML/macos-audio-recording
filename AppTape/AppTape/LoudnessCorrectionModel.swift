import Foundation
import Observation

/// The Loudness correction preview for the editor.
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
    /// adds the manual Gain to this and sets the sum as one `globalGain`.
    var correctionDB: Double { correction?.decibels ?? 0 }

    /// Measures (or clears) the correction for a Recording's current Trim.
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
            let measurement =
                (try? LoudnessMeter.measure(
                    url: url, startFrame: start, frameCount: count,
                    isCancelled: { Task.isCancelled }))
                ?? LoudnessMeasurement(integratedLUFS: nil, truePeakDBTP: -.infinity)
            if Task.isCancelled { return }
            // Bound before the hop: reading the weak capture inside the `MainActor.run` closure
            // would capture the mutable `self` box itself into concurrently-executing code.
            guard let model = self else { return }
            await model.land(measurement, forKey: key)
        }
    }

    /// Land a finished pass — only if it is still the current one (its key still stands).
    private func land(_ measurement: LoudnessMeasurement, forKey key: String) {
        guard currentKey == key else { return }
        state = .measured(LoudnessCorrection.compute(for: measurement))
    }
}
