//
//  Palette.swift
//  AppTape
//

import SwiftUI

/// AppTape's two content colours — and the only two colours the app owns (ADR-0019:
/// *content is the colour*).
///
/// Chrome stays on system materials and the **user's** accent. Indigo marks the audio and the
/// Trim, and appears **exhaustively** at these sites and nowhere else: the waveform peaks, the
/// playhead, the Trim drag handle while it is under the hand, and the Library's "is Trimmed"
/// scissors glyph — plus the waveform body, which takes `signalMuted`. Not the Export button,
/// not the selected Quality Preset rung, not focus rings, not the sidebar selection.
///
/// **Never a text colour in Dark Mode.** `Signal` dark measures 3.29:1 on the dark window
/// background, under the 4.5:1 small-text floor. It is legitimate as a fill and as a small
/// non-text mark; a glyph carrying words takes `.primary`.
///
/// **`AccentColor.colorset` is empty on purpose — do not fill it in.** A custom global accent
/// renders only when the person's System Settings → General → Accent color is Multicolor, and any
/// other choice overrides it app-wide, so an accent shipped that way is committed only on machines
/// that happen to have no opinion. `Signal` is therefore written at each content site instead. We
/// never contest the user's accent; we simply stopped using it for content.
enum Palette {
    /// The small bright marks: waveform peaks, playhead, the Trim handle under the hand, the
    /// "is Trimmed" scissors. Seeded from `systemIndigo` and **ours** thereafter — Apple declines
    /// to publish stable values for the system colours, and indigo has moved before.
    ///
    /// Light `#5856D6` (5.65:1 on the light window background), dark `#5E5CE6` (3.29:1).
    /// High Contrast: light `#403FA0` (8.62:1), dark `#9694F0` (6.19:1) — both clear 4.5:1.
    static let signal = Color(.signal)

    /// The large field: the waveform body. A separate stop rather than `signal` at a lower alpha,
    /// because dropping alpha muddies indigo toward grey while a big fill at a small mark's
    /// saturation vibrates and halates on a dark canvas. Always lower saturation than `signal`,
    /// and on dark lower lightness too: light `#6C6BC9` (S .465 vs .610), dark `#4A48A8`
    /// (S .400 vs .734, L .471 vs .631).
    ///
    /// No High Contrast variant, deliberately: raising a *field's* contrast makes the lane louder
    /// without making anything more legible, and fights the anti-halation reason it exists.
    static let signalMuted = Color(.signalMuted)
}
