//
//  PanelAnchoring.swift
//  AppTape
//

import CoreGraphics

/// Where the panel should hang when it opens.
enum PanelAnchor: Equatable {
    /// The status button's frame is usable; anchor the popover to the button.
    case statusButton
    /// The button frame was unusable; anchor to this rect, in screen
    /// coordinates, at the top-right of the main screen below the menu bar.
    case screenFallback(CGRect)
}

/// The status button's own window frame is the natural anchor, but it is
/// untrustworthy at exactly the moments it matters (ADR-0011): `[0,0 29x0]`
/// before the item is placed, its last frame retained while `isVisible` is
/// false, and a stale duplicate shared by two items just after a restore. So a
/// candidate frame is treated as a claim to be checked, and an unusable one
/// falls back to the top-right of the main screen rather than refusing to open —
/// a hidden item is exactly when someone is hunting for the app.
enum PanelAnchoring {
    /// A button-window frame is usable only if it is non-empty *and* fully
    /// contained in some screen's frame.
    static func isButtonFrameUsable(_ frame: CGRect, within screens: [CGRect]) -> Bool {
        guard !frame.isEmpty else { return false }
        return screens.contains { $0.contains(frame) }
    }

    /// A thin sliver at the top-right of the main screen whose top edge is flush
    /// with the screen top, so a popover shown from its `.maxY` edge auto-flips
    /// to sit just below the menu bar — the same placement the real status item
    /// gets.
    static func fallbackRect(mainScreen: CGRect, statusBarThickness: CGFloat) -> CGRect {
        CGRect(x: mainScreen.maxX - 1,
               y: mainScreen.maxY - statusBarThickness,
               width: 1,
               height: statusBarThickness)
    }

    /// Decide the anchor from a candidate button frame and the screen layout.
    static func anchor(buttonWindowFrame frame: CGRect?,
                       screens: [CGRect],
                       mainScreen: CGRect?,
                       statusBarThickness: CGFloat) -> PanelAnchor {
        if let frame, isButtonFrameUsable(frame, within: screens) {
            return .statusButton
        }
        let main = mainScreen ?? screens.first ?? .zero
        return .screenFallback(fallbackRect(mainScreen: main, statusBarThickness: statusBarThickness))
    }
}
