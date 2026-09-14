import SwiftUI

/// The spacing, type and motion half of the token set. Values live here rather than
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
    static let sidebarRowHeight: Double = 32

    // MARK: - Type

    /// Wholly SF, four rungs, no light weights. Nothing goes below 11pt, though macOS permits 10.

    /// A Recording's name. Body/13 semibold.
    static let name = Font.body.weight(.semibold)

    /// Metadata and secondary lines. Subheadline/11 — pair it with `.secondary`.
    static let metadata = Font.subheadline

    /// Inspector section headers. Headline/13 bold.
    static let sectionHeader = Font.headline

    /// The transport position and the Trim readouts. Body/13 with monospaced digits — the single
    /// content-scoped departure from plain SF, and it is there so digits do not jitter as they
    /// tick, not for flavour.
    static let readout = Font.body.monospacedDigit()

    // MARK: - Motion

    /// **Motion is feedback**: something moves only to confirm an action the user just
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

// supersedes 's "Reduce Motion gets one helper, not four call sites". The
// principle it stated is untouched and is why both of these exist: only Liquid Glass's own morph

extension View {
    /// Swaps the animation, and honours Reduce Motion. Reads as `.animation(_:value:)` and behaves
    /// as it normally does.
    func motion<V: Equatable>(_ intended: Animation?, value: V) -> some View {
        modifier(ReducedMotionAnimation(intended: intended, value: value))
    }

    /// Swaps the content transition, and honours Reduce Motion. Use it where a `Text`'s *value*
    /// changes and the redraw should say so — `.numericText` on a figure that ticks.
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
