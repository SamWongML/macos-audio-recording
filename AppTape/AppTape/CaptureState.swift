import Foundation

/// What the editor is allowed to know about the capture in flight.
@MainActor
protocol CaptureState {
    /// Master duration so far, published on the run's 4 Hz clock gate — 0 through the armed window
    /// before the first sound. The sidebar row's live clock and the transport's readout.
    var elapsed: TimeInterval { get }

    /// What the master weighs right now, on the same 4 Hz gate.
    var masterByteCount: Int64? { get }

    /// Whether `recording` is the one being captured right now, and so not exportable: its `.caf` is
    /// still growing in place and its Trim end is undefined until Stop.
    func isCapturing(_ recording: Recording) -> Bool
}

extension CaptureState {
    /// Whether this Recording's audio is still arriving: it has no frames at all, or it is the
    /// one being captured right now.
    func isStillArriving(_ recording: Recording) -> Bool {
        recording.isEmpty || isCapturing(recording)
    }
}

extension CaptureRun: CaptureState {}
