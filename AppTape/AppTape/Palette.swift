import SwiftUI

/// AppTape's two content colours — and the only two colours the app owns (
/// *content is the colour*).
enum Palette {
    /// The small bright marks: waveform peaks, the Trim handle under the hand, the "is Trimmed"
    /// scissors. **Not the playhead** — see the note above. Seeded from `systemIndigo` and **ours** thereafter — Apple declines
    /// to publish stable values for the system colours, and indigo has moved before.
    static let signal = Color(.signal)

    /// The large field: the waveform body. A separate stop rather than `signal` at a lower alpha,
    /// because dropping alpha muddies indigo toward grey while a big fill at a small mark's
    /// saturation vibrates and halates on a dark canvas. Always lower saturation than `signal`,
    /// and on dark lower lightness too: light `#6C6BC9` (S.465 vs.610), dark `#4A48A8`
    /// (S.400 vs.734, L.471 vs.631).
    static let signalMuted = Color(.signalMuted)

    /// The Trimmed-away audio's peaks — `signal`'s counterpart outside the Trim.
    static let signalQuiet = Color(.signalQuiet)

    /// The Trimmed-away audio's body — `signalMuted`'s counterpart outside the Trim, and the same
    /// story as `signalQuiet`. Dark `#505050` **renders `(70,70,70)`**, what `grayscale(1)`
    /// rendered; light `#7C7C7C` **renders `(113,113,113)`**, receding by the **13%** Dark's body
    /// already receded by.
    static let signalMutedQuiet = Color(.signalMutedQuiet)
}
