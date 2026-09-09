//
//  BoundaryVariant.swift
//  AppTape
//
//  **Throwaway prototype harness (issue #115), never merged.**
//

import AppKit
import SwiftUI

/// The sidebar/detail boundary, five ways, chosen by `APPTAPE_BOUNDARY=a|b|c|d|e`.
///
/// The question (#115): in Dark the sidebar measures `(42,42,42)` against a detail of `(42,42,42)`
/// — a step of `1.000 : 1`, with no divider — so the window's left 1200 pt is one flat field.
/// A palette argument decides nothing here (ADR-0032), so each candidate is built into the running
/// app and the fills are read off a screenshot.
///
/// - `a` **baseline** — what ships today. Nothing added.
/// - `b` **divider only** — a system hairline at the boundary, running to the window's *top* edge,
///   which is what issue #7 hid the toolbar background for and what ADR-0035 then used for the
///   trailing column. No fill moves, so nothing lands on the waveform's surface.
/// - `c` **scrim behind the material** — the trailing column's instrument (flat black at a low
///   alpha, deliberately not appearance-adaptive) painted *behind* the sidebar's list. If the
///   sidebar's `NSVisualEffectView` blends behind-window, this moves nothing, and that is a fact
///   worth measuring rather than assuming.
/// - `d` **opaque sidebar + scrim** — `.scrollContentBackground(.hidden)` first, so the fill is
///   ours. Guaranteed to move; costs the sidebar its vibrancy, which ADR-0019 spends on chrome
///   deliberately.
/// - `e` **d + the divider** — Finder uses both: sidebar `(41,40,41)`, content `(37,36,37)`, and a
///   divider at x = 202–205 (research 0008, finding 3).
enum BoundaryVariant: String {
    case a, b, c, d, e

    static let current: BoundaryVariant = {
        let raw = ProcessInfo.processInfo.environment["APPTAPE_BOUNDARY"] ?? "a"
        return BoundaryVariant(rawValue: raw.lowercased()) ?? .a
    }()

    /// The same alpha the trailing column carries, so the two boundaries are argued in one unit.
    static let scrim = EditorView.inspectorColumnScrim

    var wantsDivider: Bool { self == .b || self == .e }
    var wantsScrim: Bool { self == .c || self == .d || self == .e }
    /// Whether the sidebar gives up its material so the scrim has an opaque fill to sit on.
    var wantsOpaqueSidebar: Bool { self == .d || self == .e }
}
