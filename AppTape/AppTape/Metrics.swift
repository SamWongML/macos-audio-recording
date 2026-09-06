//
//  Metrics.swift
//  AppTape
//

import SwiftUI

/// The spacing, type and motion half of the token set (ADR-0019). Values live here rather than
/// inline so the views built after that ADR *inherit* the decision instead of copying it — and so
/// two places quietly disagreeing becomes visible rather than invisible.
enum Metrics {

    // MARK: - Spacing

    /// A 4pt base, on the generous side. One deliberate break in the uniformity: the waveform lane
    /// is the only element allowed to take all remaining height.
    static let xs: Double = 4
    static let sm: Double = 8
    static let md: Double = 12
    static let lg: Double = 16
    static let xl: Double = 24

    /// Sidebar rows, so the name and its metadata are two real lines rather than one crowded one.
    ///
    /// **Declared by ADR-0019 and not applied**: `LibraryRow` is one 32 pt line, with the
    /// timestamp beside the name rather than under it. That is the layout the sweep and the
    /// redesign both judged on screen, so the code is not obviously the wrong half — but a token
    /// nothing reads is the disagreement this enum exists to make visible, not hide. Issue #78
    /// restyles the sidebar and owns reconciling the two: adopt this number, or retire it from
    /// the ADR. Do not quietly delete it, and do not adopt it without looking at the result.
    static let sidebarRowHeight: Double = 40

    // MARK: - Type

    /// Wholly SF, four rungs, no light weights. Nothing goes below 11pt, though macOS permits 10.

    /// A Recording's name. Body/13 semibold.
    ///
    /// **Declared by ADR-0019 and not applied**: `LibraryRow`'s name `Text` names no font and so
    /// inherits plain `.body`. Issue #78's, on the same terms as `sidebarRowHeight`.
    static let name = Font.body.weight(.semibold)

    /// Metadata and secondary lines. Subheadline/11 — pair it with `.secondary`.
    static let metadata = Font.subheadline

    /// Inspector section headers. Headline/13 bold.
    ///
    /// **Declared by ADR-0019 and not applied**: `ExportInspector` uses `Form` `Section` headers,
    /// which macOS styles itself, and overriding a platform-styled header is a decision rather
    /// than a tidy-up. Issue #78's, on the same terms as `sidebarRowHeight`.
    static let sectionHeader = Font.headline

    /// The transport position and the Trim readouts. Body/13 with monospaced digits — the single
    /// content-scoped departure from plain SF, and it is there so digits do not jitter as they
    /// tick, not for flavour.
    static let readout = Font.body.monospacedDigit()

    // MARK: - Motion

    /// What a suppressed animation degrades *to*. Apple's stated replacement for a movement is a
    /// **fade**, not an instant cut, so Reduce Motion still gets a transition — it just stops
    /// travelling.
    static let reducedMotionFade = Animation.easeInOut(duration: 0.2)
}

extension View {
    /// Every animation AppTape writes goes through here (ADR-0019). Only Liquid Glass's own morph
    /// honours Reduce Motion automatically; every `withAnimation` and `.animation` the app writes
    /// is the app's job. One helper rather than a check at each call site, so the next animation
    /// anyone adds inherits the behaviour instead of forgetting it.
    ///
    /// Reads as `.animation(_:value:)` and behaves as it normally. Under Reduce Motion the
    /// intended animation is swapped for `Metrics.reducedMotionFade` and changing text
    /// cross-fades instead of rolling its digits.
    func motion<V: Equatable>(_ intended: Animation? = .default, value: V) -> some View {
        modifier(ReducedMotionAnimation(intended: intended, value: value))
    }
}

private struct ReducedMotionAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var intended: Animation?
    var value: V

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .opacity : .interpolate)
            .animation(reduceMotion ? Metrics.reducedMotionFade : intended, value: value)
    }
}
