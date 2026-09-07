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
    /// **ADR-0019 declared 40; #78 judged both on screen and kept 32** (ADR-0025). Forty points
    /// buys a second line, and the second line's only content was the timestamp — which the day
    /// section header above and the brief two panes to the right already state. A taller row for a
    /// fact stated twice elsewhere is emptier, not calmer, and it costs four visible Recordings at
    /// the default window height. The number is now read by `LibraryRow`, so the token and the code
    /// agree.
    static let sidebarRowHeight: Double = 32

    // MARK: - Type

    /// Wholly SF, four rungs, no light weights. Nothing goes below 11pt, though macOS permits 10.

    /// A Recording's name. Body/13 semibold.
    ///
    /// **Adopted by #78**: `LibraryRow` reads it. With the timestamp gone the name carries the row
    /// on its own, and semibold is what makes it the thing scanned rather than one of three greys.
    static let name = Font.body.weight(.semibold)

    /// Metadata and secondary lines. Subheadline/11 — pair it with `.secondary`.
    static let metadata = Font.subheadline

    /// Inspector section headers. Headline/13 bold.
    ///
    /// **Retired by #78, kept as a stop nothing reads** (ADR-0025). `ExportInspector` stayed a
    /// grouped `Form`, whose `Section` headers macOS styles itself and restyles between releases.
    /// Overriding them would freeze this app's headers at one OS version's idea of them for no gain
    /// the ticket could see on screen. It is left declared, and deliberately unused, because the
    /// next surface that needs a header outside a `Form` should use this rather than invent one.
    static let sectionHeader = Font.headline

    /// The transport position and the Trim readouts. Body/13 with monospaced digits — the single
    /// content-scoped departure from plain SF, and it is there so digits do not jitter as they
    /// tick, not for flavour.
    static let readout = Font.body.monospacedDigit()

    // MARK: - Motion

    /// **Motion is feedback** (ADR-0028): something moves only to confirm an action the user just
    /// took, or to mark a state change they must notice. There are two stops because those are two
    /// different jobs, and a single duration gets one of them wrong — 0.25 s on a Trim handle feels
    /// like drag, 0.12 s on an Export phase is a flicker you miss.

    /// Direct manipulation: the thing under the cursor answering the cursor. Short enough to read
    /// as the control being *stiff* rather than as an animation playing.
    static let motionQuick = Animation.easeOut(duration: 0.12)

    /// A change the user should notice but did not directly cause — an Export phase arriving, a
    /// loudness measurement landing, a size estimate re-reckoned after a Trim.
    static let motionState = Animation.easeInOut(duration: 0.25)

    /// What a suppressed animation degrades *to*. Apple's stated replacement for a movement is a
    /// **fade**, not an instant cut, so Reduce Motion still gets a transition — it just stops
    /// travelling.
    static let reducedMotionFade = Animation.easeInOut(duration: 0.2)
}

// MARK: - The two motion helpers

// ADR-0028 supersedes ADR-0019's "Reduce Motion gets one helper, not four call sites". The
// principle it stated is untouched and is why both of these exist: only Liquid Glass's own morph
// honours Reduce Motion automatically, so every animation the app writes must honour it itself,
// and a contract that has to be remembered at each call site is one that will be forgotten. What
// changed is the *count*. One helper owned two contracts — which animation plays, and how changing
// text redraws — and bundling them is what let a wrong content transition sit unnoticed at all five
// sites in the app: `.interpolate` interpolates between symbol and shape states, it does not roll
// digits, so the digit rolling `.motion` documented had never once happened. Two helpers, one
// contract each, and each degrades itself.

extension View {
    /// Swaps the animation, and honours Reduce Motion. Reads as `.animation(_:value:)` and behaves
    /// as it normally does.
    ///
    /// **Attach it to the smallest view that contains the change, never to a container** — the
    /// operative half of ADR-0028, and not a style preference. `.animation(_:value:)` animates
    /// every property of its subtree *including that subtree's own resolved geometry*, so on a pane
    /// whose position is derived rather than stated it means "animate where this pane is". Four of
    /// these on the Export inspector's `Form` are why the trailing column used to travel in from
    /// the top-left of the detail pane and take seconds to arrive (issue #88).
    ///
    /// There is deliberately **no default animation**: `.default` is a framework spring, and four
    /// call sites took it without choosing it. Pick `Metrics.motionQuick` or `Metrics.motionState`.
    func motion<V: Equatable>(_ intended: Animation?, value: V) -> some View {
        modifier(ReducedMotionAnimation(intended: intended, value: value))
    }

    /// Swaps the content transition, and honours Reduce Motion. Use it where a `Text`'s *value*
    /// changes and the redraw should say so — `.numericText()` on a figure that ticks.
    ///
    /// Separate from `motion(_:value:)` because what a row's text does when it changes is an
    /// editorial choice per row, while honouring Reduce Motion is one rule for the whole app. Under
    /// Reduce Motion this resolves to `.opacity`: rolling digits are motion too.
    func textTransition(_ intended: ContentTransition) -> some View {
        modifier(ReducedMotionTextTransition(intended: intended))
    }
}

private struct ReducedMotionAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var intended: Animation?
    var value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? Metrics.reducedMotionFade : intended, value: value)
    }
}

private struct ReducedMotionTextTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var intended: ContentTransition

    func body(content: Content) -> some View {
        content.contentTransition(reduceMotion ? .opacity : intended)
    }
}
