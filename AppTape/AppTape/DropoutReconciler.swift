import Foundation

/// The writer thread's host-time→master reconciler: a pure value reducer, like `CaptureReducer`,
/// so the whole rule is visible to a test off the realtime thread.
nonisolated struct DropoutReconciler {
    let sampleRate: Double
    /// A gap larger than this ends the Recording rather than being padded.
    let maxGapSeconds: Double
    /// The smallest gap worth padding as a Dropout.
    let minDropoutFrames: Int

    /// Frames committed to the master so far — real audio plus every pad. Matches what the writer
    /// has actually written once each decision is applied.
    private(set) var masterFrames: Int = 0
    /// Every Dropout padded so far, in order, with `start` at the master frame each began.
    private(set) var dropouts: [Dropout] = []

    /// Host time (seconds) at which the master's t=0 landed, captured from the first chunk that
    /// carries a valid host time. Nil until then — before it, everything is contiguous.
    private var anchorSeconds: Double?

    init(sampleRate: Double, maxGapSeconds: Double = 30, minDropoutFrames: Int = 128) {
        self.sampleRate = sampleRate
        self.maxGapSeconds = maxGapSeconds
        self.minDropoutFrames = minDropoutFrames
    }

    enum Decision: Equatable {
        /// No gap: write the chunk as-is.
        case append
        /// A gap opened: write `frames` zero-frames first — that is the Dropout — then the chunk.
        case pad(frames: Int, cause: Dropout.Cause)
        /// The gap exceeded 30 s: end the Recording. The chunk is discarded and the master ends at
        /// its last real sample; nothing is padded.
        case end
    }

    /// Reconcile one chunk against the wall clock, before it is written.
    /// - Parameters:
    mutating func account(hostTimeSeconds: Double,
                          hostTimeValid: Bool,
                          newFrames: Int,
                          rebuildInFlight: Bool) -> Decision {
        precondition(newFrames >= 0, "a chunk cannot contribute negative frames")

        guard let anchor = anchorSeconds else {
            // Establish the anchor on the first chunk that can be trusted; until then, contiguous.
            if hostTimeValid { anchorSeconds = hostTimeSeconds - Double(masterFrames) / sampleRate }
            masterFrames += newFrames
            return .append
        }
        guard hostTimeValid else {
            // Cannot reconcile an untrusted timestamp — assume contiguity.
            masterFrames += newFrames
            return .append
        }

        let expected = Int(((hostTimeSeconds - anchor) * sampleRate).rounded())
        let gap = expected - masterFrames

        if gap > Int((maxGapSeconds * sampleRate).rounded()) {
            return .end
        }
        if gap >= minDropoutFrames {
            let cause: Dropout.Cause = rebuildInFlight ? .rebuild : .overrun
            dropouts.append(Dropout(start: masterFrames, frames: gap, cause: cause))
            masterFrames += gap          // the pad
            masterFrames += newFrames    // the chunk after it
            return .pad(frames: gap, cause: cause)
        }
        // Gap within tolerance (or the chunk arrived a touch early): just append.
        masterFrames += newFrames
        return .append
    }
}
