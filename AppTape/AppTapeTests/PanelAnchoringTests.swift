//
//  PanelAnchoringTests.swift
//  AppTapeTests
//

import Testing
import CoreGraphics
@testable import AppTape

/// The status button's frame is a claim to be checked, not trusted (ADR-0011):
/// `[0,0 29x0]` before the item is placed, its last frame retained while hidden,
/// and stale duplicates just after a restore. These pin the geometry decision.
struct PanelAnchoringTests {
    // A single 1440×900 primary screen, origin at (0,0).
    let mainScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    var screens: [CGRect] { [mainScreen] }

    @Test func placedButtonFrameIsUsable() {
        // A real status item sits at the top of the screen, inside its frame.
        let button = CGRect(x: 1360, y: 876, width: 29, height: 24)
        #expect(PanelAnchoring.isButtonFrameUsable(button, within: screens))
    }

    @Test func zeroHeightFrameBeforePlacementIsUnusable() {
        // The `[0,0 29x0]` an item reports before it is placed.
        let unplaced = CGRect(x: 0, y: 0, width: 29, height: 0)
        #expect(!PanelAnchoring.isButtonFrameUsable(unplaced, within: screens))
    }

    @Test func frameOutsideEveryScreenIsUnusable() {
        // A stale frame left behind on a screen that is no longer attached.
        let offscreen = CGRect(x: 5000, y: 5000, width: 29, height: 24)
        #expect(!PanelAnchoring.isButtonFrameUsable(offscreen, within: screens))
    }

    @Test func frameStraddlingAScreenEdgeIsUnusable() {
        // Contained means fully contained: half-off the right edge does not count.
        let straddling = CGRect(x: 1430, y: 876, width: 29, height: 24)
        #expect(!PanelAnchoring.isButtonFrameUsable(straddling, within: screens))
    }

    @Test func fallbackRectSitsAtTopRightBelowTheMenuBar() {
        let rect = PanelAnchoring.fallbackRect(mainScreen: mainScreen, statusBarThickness: 24)
        // Top edge flush with the screen top so the popover auto-flips below it.
        #expect(rect.maxY == mainScreen.maxY)
        // Pinned to the right edge.
        #expect(rect.maxX == mainScreen.maxX)
    }

    @Test func anchorPrefersAUsableButton() {
        let button = CGRect(x: 1360, y: 876, width: 29, height: 24)
        let anchor = PanelAnchoring.anchor(
            buttonWindowFrame: button,
            screens: screens,
            mainScreen: mainScreen,
            statusBarThickness: 24
        )
        #expect(anchor == .statusButton)
    }

    @Test func anchorFallsBackWhenTheFrameIsUnusable() {
        let anchor = PanelAnchoring.anchor(
            buttonWindowFrame: CGRect(x: 0, y: 0, width: 29, height: 0),
            screens: screens,
            mainScreen: mainScreen,
            statusBarThickness: 24
        )
        #expect(anchor == .screenFallback(
            PanelAnchoring.fallbackRect(mainScreen: mainScreen, statusBarThickness: 24)
        ))
    }

    @Test func anchorFallsBackWhenThereIsNoFrameAtAll() {
        let anchor = PanelAnchoring.anchor(
            buttonWindowFrame: nil,
            screens: screens,
            mainScreen: mainScreen,
            statusBarThickness: 24
        )
        if case .screenFallback = anchor {
            // expected
        } else {
            Issue.record("expected a screen fallback when no button frame exists")
        }
    }
}
