/// The Capture Engine's observation→decision dropout: a pure value reducer that
/// turns "a chunk of frames arrived, and here is where its first sound is" into
/// "elide / begin / append", and tracks the master's frame count.
nonisolated struct CaptureReducer {
    /// Audio frames committed to the master so far. Sits at `00:00` through the armed window and
    /// only advances at the first sound. Once faults can pad silence, the menu-bar timer
    /// reads the engine's `DropoutReconciler.masterFrames` instead — that count includes padding Dropouts,
    /// so the displayed duration stays wall-clock true; this one counts only the audio.
    private(set) var masterFrames: Int = 0

    /// Whether the first sound has been heard and the master has begun. Also the
    /// save-or-discard answer at stop: false means arm-then-never-play, which
    /// saves nothing — no file was ever created.
    private(set) var hasBegun: Bool = false

    enum Decision: Equatable {
        /// Pre-first-sound silence: write nothing, create no file (head elision).
        case elide
        /// The first sound. Create the file lazily now and write this chunk from
        /// `skipLeadingFrames` onward, so the master starts exactly at t=0 of the
        /// first non-silent frame rather than at the head of a partly-silent chunk.
        case begin(skipLeadingFrames: Int)
        /// The master is running: append the whole chunk, silence included.
        case append
    }

    /// Fold in one drained chunk.
    /// - Parameters:
    mutating func receive(frameCount: Int, firstNonSilentFrame: Int?) -> Decision {
        precondition(frameCount >= 0, "a chunk cannot have negative frames")
        if hasBegun {
            masterFrames += frameCount
            return .append
        }
        guard let first = firstNonSilentFrame else {
            return .elide
        }
        precondition(first >= 0 && first < frameCount, "first non-silent frame must be inside the chunk")
        hasBegun = true
        masterFrames += frameCount - first
        return .begin(skipLeadingFrames: first)
    }
}
