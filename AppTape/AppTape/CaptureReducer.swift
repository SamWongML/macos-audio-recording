/// The Capture Engine's observation→decision dropout: a pure value reducer that turns "a chunk of
/// frames arrived, and here is where its first sound is" into "elide / begin / append", and tracks
/// the master's frame count.
nonisolated struct CaptureReducer {
    /// Audio frames committed to the master so far.
    private(set) var masterFrames: Int = 0

    /// Whether the first sound has been heard and the master has begun.
    private(set) var hasBegun: Bool = false

    enum Decision: Equatable {
        /// Pre-first-sound silence: write nothing, create no file (head elision).
        case elide
        /// The first sound.
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
