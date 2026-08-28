//
//  CaptureReducer.swift
//  AppTape
//

/// The Capture Engine's observation→decision seam: a pure value reducer that
/// turns "a chunk of frames arrived, and here is where its first sound is" into
/// "elide / begin / append", and tracks the master's frame count.
///
/// It exists so the one rule that governs the shape of a Recording — a Recording
/// **begins at the first sound, not the first press** (ADR-0016) — is a pure
/// function that can be unit-tested exhaustively off the realtime thread. The
/// IOProc only copies samples into the ring buffer; the non-realtime writer
/// thread scans a drained chunk for its first non-silent frame and feeds that
/// observation here. Nothing in this type touches Core Audio, the file, or a
/// clock, so its whole behaviour is visible to a test.
///
/// The asymmetry it encodes (ADR-0016): the **head** is elided — leading silence
/// before the first sound is dropped, so an armed recorder waiting for audio
/// writes nothing and the master's t=0 is the first sample heard — while
/// **interior** silence, once the master has begun, is kept as real zero-frames
/// so Trim points stored against the master never shift.
struct CaptureReducer {
    /// Audio frames committed to the master so far. Sits at `00:00` through the armed window and
    /// only advances at the first sound (ADR-0016). Once faults can pad silence, the menu-bar timer
    /// reads the engine's `SeamReconciler.masterFrames` instead — that count includes padding Seams,
    /// so the displayed duration stays wall-clock true; this one counts only the audio (ADR-0010).
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
    ///
    /// - Parameters:
    ///   - frameCount: frames in the chunk.
    ///   - firstNonSilentFrame: index of the first frame carrying any non-zero
    ///     sample, or `nil` if the whole chunk is silent. The writer thread, not
    ///     the realtime IOProc, computes this.
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
