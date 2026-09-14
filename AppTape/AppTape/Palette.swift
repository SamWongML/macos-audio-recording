import SwiftUI

/// The two content colours the app owns. Chrome stays on system materials and the user's accent;
/// indigo marks the audio and the Trim, and appears nowhere else.
enum Palette {
    /// The small bright marks: waveform peaks, the Trim handle under the hand, the "is Trimmed"
    /// scissors.
    static let signal = Color(.signal)

    /// The large field: the waveform body.
    static let signalMuted = Color(.signalMuted)

    /// The Trimmed-away audio's peaks — `signal`'s counterpart outside the Trim.
    static let signalQuiet = Color(.signalQuiet)

    /// The Trimmed-away audio's body — `signalMuted`'s counterpart outside the Trim, and the same
    /// story as `signalQuiet`.
    static let signalMutedQuiet = Color(.signalMutedQuiet)
}
