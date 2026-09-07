//
//  EmptyColumnPrototype.swift
//  AppTape
//
//  ⚠️ PROTOTYPE — THROWAWAY. Lives only on `prototype/empty-column-dark`, never merged.
//
//  Five treatments for the trailing column's boundary, switchable in the running app from the
//  title-bar picker (or ⌃⌥← / ⌃⌥→). Answers issue #111: ADR-0034 emptied the column, and the
//  fill that used to carry a glyph and two lines of text now carries nothing. Measured at
//  1200 × 680, the fill did not move — Dark `(42,42,42)` detail against `(27,27,27)` column,
//  Light `(255,255,255)` against `(242,242,242)` — but Dark's step is 36% where Light's is 5%,
//  about seven times as loud, and with nothing drawn on it the Dark column reads as a hole.
//
//  The switcher lives in the **title bar**, not in a docked strip like #77's, because the thing
//  being judged is a boundary that runs the full height of the body. A strip along the bottom
//  would cut every variant's column short and hand it Xcode's status-bar silhouette for free —
//  which is a different design, not a neutral harness.
//
//  What is HELD CONSTANT across all five:
//    • the column is still 276 pt and still permanent (ADR-0024) — nothing here hides it;
//    • the column still never explains itself (ADR-0034) — no variant puts a sentence back;
//    • no new colour is owned: every fill is a system colour, a system material, or a measured
//      correction on one (ADR-0019).
//
//  What the variants are FREE to disagree about: whether the correction is appearance-aware,
//  whether the instrument is a fill step at all, and whether the empty column and the populated
//  one get the same answer.

import AppKit
import SwiftUI

// MARK: - The variants

enum EmptyColumnVariant: String, CaseIterable, Identifiable {
    case asIs, levelled, hairline, material, dissolves, topEdge

    var id: String { rawValue }

    /// `APPTAPE_COLUMN_VARIANT=A` … `=E`, so each variant can be photographed from a **fresh
    /// launch at the saved frame** rather than by flipping the picker — the map's harness rule.
    var key: String {
        switch self {
        case .asIs: return "A"
        case .levelled: return "B"
        case .hairline: return "C"
        case .material: return "D"
        case .dissolves: return "E"
        case .topEdge: return "F"
        }
    }

    var title: String {
        switch self {
        case .asIs: return "A — As it stands"
        case .levelled: return "B — Level the step"
        case .hairline: return "C — Hairline, no step"
        case .material: return "D — Chrome material"
        case .dissolves: return "E — The empty column dissolves"
        case .topEdge: return "F — As it stands, reaching the top edge"
        }
    }

    /// The one-line thesis, printed on the picker so a screenshot carries its own argument.
    var thesis: String {
        switch self {
        case .asIs:
            return "nothing changes; a bare pane is the honest look of a pane with nothing in it"
        case .levelled:
            return "same instrument, tuned per appearance: the step reads ~5% in both"
        case .hairline:
            return "no fill difference at all; a 1 pt rule is the whole boundary"
        case .material:
            return "the column is chrome, so it takes a material — Xcode's actual instrument"
        case .dissolves:
            return "an empty column stops being a pane; the treatment returns with the ladder"
        case .topEdge:
            return "A's exact fill, run through the title bar — is the gap the defect, not the dark?"
        }
    }

    /// The only variant whose boundary is drawn rather than filled. `E` deliberately draws
    /// **no** rule when empty: dissolving a pane and then outlining where it was is the worst of
    /// both, and saying so out loud is cheaper than photographing it.
    func drawsHairline(isEmpty: Bool) -> Bool { self == .hairline }

    /// Whether the column paints anything of its own.
    func paintsFill(isEmpty: Bool) -> Bool {
        switch self {
        case .hairline: return false
        case .dissolves: return !isEmpty
        default: return true
        }
    }

    /// **Whether the fill runs through the title bar to the window's top edge.**
    ///
    /// Measured on the shipping build and not in the ticket: the column's fill starts at
    /// **y = 52 pt** in both appearances — below the title bar — so what the eye gets is a
    /// rectangle stuck to the right-hand side with a square top corner, not a pane. Report 0006's
    /// primary source says the opposite is Apple's model: Xcode's inspector seam *"starts at the
    /// literal top of the window"*, and WWDC20's *Adopt the new look of macOS* calls a split
    /// view's dividers reaching the top of the window the point of `fullSizeContentView`. This
    /// window hides its toolbar background (issue #7) precisely so the body reads to the edge —
    /// and then the column stops short of it.
    ///
    /// `A` is the true control and keeps the gap. Everything that changes the fill also closes it,
    /// so the two questions are asked separately: `A` vs `F` is *is the gap the defect?*, `A` vs
    /// `B`/`D` is *is the darkness?*
    var reachesTopEdge: Bool { self != .asIs }
}

// MARK: - The fill

/// The column's background, per variant. Everything here is measured on screen afterwards, never
/// trusted from the number written in it (ADR-0032) — the alphas below are *starting points*.
struct PrototypeColumnFill: View {
    var variant: EmptyColumnVariant
    var isEmpty: Bool
    var reduceTransparency: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            switch variant {
            case .asIs, .dissolves, .topEdge:
                if variant.paintsFill(isEmpty: isEmpty) { shipping }
            case .levelled:
                levelled
            case .hairline:
                EmptyView()
            case .material:
                material
            }
        }
        .modifier(TopEdge(on: variant.reachesTopEdge))
    }

    /// What `main` draws today: `.controlBackgroundColor` under a flat black scrim at 0.05,
    /// identical in both appearances.
    private var shipping: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
            Color.black.opacity(EditorView.inspectorColumnScrim)
        }
    }

    /// **The scrim becomes appearance-aware, and it changes sign.** The arithmetic is why this
    /// variant exists at all: in Dark, `.controlBackgroundColor` is `(30,30,30)` against a detail
    /// that draws `(42,42,42)`, so *twelve* of the step's fifteen units are the system's own and
    /// only three are the scrim. Deleting the black in Dark would land the column at 30 — still
    /// 29% darker, still a hole. Closing the gap means lifting the column **toward** the detail,
    /// which is a white scrim, which is exactly what ADR-0032 ruled out when it said the column
    /// wants to be darker in both appearances.
    ///
    /// 0.045 white over `(30,30,30)` computes to `(40,40,40)` — a 5% step from the detail's 42,
    /// matching Light's 255 → 242. Light is untouched.
    private var levelled: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
            if colorScheme == .dark {
                Color.white.opacity(0.045)
            } else {
                Color.black.opacity(EditorView.inspectorColumnScrim)
            }
        }
    }

    /// The instrument report 0006 found in Xcode: *a material/shade difference, no hairline*. It
    /// is legal here where it would not be on the waveform — ADR-0019 puts glass on chrome and
    /// keeps it off content, and this column is chrome.
    ///
    /// Reduce Transparency falls back to the shipping fill, as the sidebar's `.bar` already does.
    @ViewBuilder
    private var material: some View {
        if reduceTransparency {
            shipping
        } else {
            Rectangle().fill(.regularMaterial)
        }
    }
}

/// The fill either fills the body or fills the window. `ignoresSafeArea` rather than a negative
/// padding: the title bar's 52 pt is a safe-area inset, and reading it back off a hard-coded
/// number is how a window that ever grows a second toolbar row gets a stripe.
private struct TopEdge: ViewModifier {
    var on: Bool
    func body(content: Content) -> some View {
        if on { content.ignoresSafeArea(edges: .top) } else { content }
    }
}

// MARK: - The switcher

/// A title-bar picker rather than a docked strip — see the file header.
///
/// **It has to be small and it has to claim priority.** The first attempt was a segmented picker
/// beside the variant's title and its one-line thesis, ~700 pt of toolbar content: macOS 27 moved
/// the whole item into the overflow menu, so the item took its space (the window subtitle
/// truncated to `Sep 4, 2…`) and drew nothing at all. One `.menu` picker, plus
/// `visibilityPriority(.high)` on the item so it is the last thing to overflow rather than the
/// first. The thesis lives in the issue and the README instead.
struct EmptyColumnVariantPicker: View {
    @Binding var variant: EmptyColumnVariant

    var body: some View {
        Picker("Variant", selection: $variant) {
            ForEach(EmptyColumnVariant.allCases) { v in
                Text(v.title).tag(v)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(width: 250)
        .background {
            // Invisible buttons: the shortcuts have to live somewhere, and a picker does not
            // take them.
            Group {
                Button("") { cycle(-1) }.keyboardShortcut(.leftArrow, modifiers: [.control, .option])
                Button("") { cycle(1) }.keyboardShortcut(.rightArrow, modifiers: [.control, .option])
            }
            .opacity(0)
        }
    }

    private func cycle(_ delta: Int) {
        let all = EmptyColumnVariant.allCases
        let index = (all.firstIndex(of: variant)! + delta + all.count) % all.count
        variant = all[index]
    }
}

// MARK: - Which variant is showing

/// The env var wins when it is set, so a screenshot pass can launch fresh at the saved frame
/// (never resizing a live window — the map's harness rule) and the picker is hidden, keeping the
/// title bar out of the comparison. Without it the picker drives an `@AppStorage`, so the human's
/// pick survives the relaunch that changing appearance needs.
enum EmptyColumnPrototype {
    static let forced: EmptyColumnVariant? = {
        guard let key = ProcessInfo.processInfo.environment["APPTAPE_COLUMN_VARIANT"] else { return nil }
        return EmptyColumnVariant.allCases.first { $0.key == key.uppercased() }
    }()

    static var showsPicker: Bool { forced == nil }
}
