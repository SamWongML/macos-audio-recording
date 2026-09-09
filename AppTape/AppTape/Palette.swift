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
/// Trim drag handle while it is under the hand, and the Library's "is Trimmed" scissors glyph —
/// plus the waveform body, which takes `signalMuted`. Not the Export button, not the selected
/// Quality Preset rung, not focus rings, not the sidebar selection.
///
/// **The playhead was on this list and is not any more** (ADR-0033). It is a transport readout
/// drawn *over* the audio, not audio — the same object as the loupe's crosshair, which was
/// `.primary` from the start — and while it was `Signal` it crossed `Signal` peaks at **1.00 : 1**
/// in both appearances. The list is the audio and the Trim; the playhead was never either.
///
/// **Never a text colour in Dark Mode.** `Signal` dark measures 3.29:1 on the dark window
/// background, under the 4.5:1 small-text floor. It is legitimate as a fill and as a small
/// non-text mark; a glyph carrying words takes `.primary`.
///
/// **One site lives outside this file: the app icon** (`AppTape.icon`, ADR-0026). The list above
/// governs *views*, where the test is "is this pixel captured audio?". The icon is the app's
/// identity seen from outside the app, and it is the waveform, so it takes `Signal` for the same
/// reason the lane does — light `#5856D6` on a pale tile, and `Signal`'s High Contrast dark stop
/// `#9694F0` on the dark one, because a small indigo mark on a near-black tile needs exactly the
/// lift Increase Contrast needs. Those values are in the `.icon` bundle, not here.
///
/// **`AccentColor.colorset` is empty on purpose — do not fill it in.** A custom global accent
/// renders only when the person's System Settings → General → Accent color is Multicolor, and any
/// other choice overrides it app-wide, so an accent shipped that way is committed only on machines
/// that happen to have no opinion. `Signal` is therefore written at each content site instead. We
/// never contest the user's accent; we simply stopped using it for content.
enum Palette {
    /// The small bright marks: waveform peaks, the Trim handle under the hand, the "is Trimmed"
    /// scissors. **Not the playhead** — see the note above. Seeded from `systemIndigo` and **ours** thereafter — Apple declines
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

    /// The Trimmed-away audio's peaks — `signal`'s counterpart outside the Trim.
    ///
    /// The lane used to make this colour by drawing the waveform a second time under
    /// `.grayscale(1)`, on the stated grounds that what changes outside the Trim is *colour, not
    /// brightness* (ADR-0019). **Measured, that was never true** (ADR-0040): `grayscale(1)`
    /// preserves luminance only approximately, and it moved the Trimmed-away half ~13% — down in
    /// Dark, which recedes and reads correctly, and **up in Light**, where the Trimmed-away half
    /// came out *louder* than the kept half and the black playhead measured **2.82 : 1** over
    /// these peaks, under ADR-0033's 3 : 1 floor.
    ///
    /// So the quiet half is authored rather than filtered. Dark `#666666` **renders `(91,91,91)`**,
    /// exactly what `grayscale(1)` rendered — Dark measured correctly and stays a control. Light
    /// `#707070` **renders `(101,101,101)`**, receding from `signal`'s rendered peaks by the same
    /// **19%** of luminance Dark already receded by, which is what puts the playhead at
    /// **3.60 : 1** — the floor is cleared by the relationship, not by a number chosen to clear it.
    ///
    /// **The authored value is not the rendered one**, which cost a calibration pass: the capture
    /// path drops every colour ~10 encoded levels (`signal`'s own `#5E5CE6` renders `(83,81,220)`),
    /// so these stops are chosen to make the *render* land on its target. Both numbers are given
    /// above for that reason — the second is the one that was measured.
    ///
    /// No High Contrast variant, and not by omission: Increase Contrast moves `signal` *away*
    /// from the lane ground in both appearances, so a fixed grey recedes further in both
    /// directions, which is the relationship this stop is for.
    static let signalQuiet = Color(.signalQuiet)

    /// The Trimmed-away audio's body — `signalMuted`'s counterpart outside the Trim, and the same
    /// story as `signalQuiet`. Dark `#505050` **renders `(70,70,70)`**, what `grayscale(1)`
    /// rendered; light `#7C7C7C` **renders `(113,113,113)`**, receding by the **13%** Dark's body
    /// already receded by.
    ///
    /// It stays darker than its ground and lighter than `signalQuiet` in Light, so the Trimmed-away
    /// half keeps the peak-against-body structure that says it is still audio.
    static let signalMutedQuiet = Color(.signalMutedQuiet)
}
