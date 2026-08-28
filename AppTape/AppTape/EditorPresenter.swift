//
//  EditorPresenter.swift
//  AppTape
//

import SwiftUI

/// Opens the editor window from outside SwiftUI — specifically from the status item's
/// stop-click, which is an AppKit event with no `@Environment(\.openWindow)` of its own.
///
/// The action is captured once from a live SwiftUI view (the panel, which the user must
/// open to pick a Source before any Recording can exist) and stashed here. Opening the
/// suppressed editor `Window` is also what flips the app to `.regular` (ADR-0017).
@MainActor
final class EditorPresenter {
    static let shared = EditorPresenter()

    private var openWindow: OpenWindowAction?

    /// Called from a SwiftUI view's environment to hand over its `openWindow` action.
    func bind(_ action: OpenWindowAction) { openWindow = action }

    /// Opens the editor, optionally selecting the Recording just captured. The model is told
    /// before the window is shown — and again on every reopen, since a suppressed `Window`
    /// reuses its `NSWindow` and does not re-run the view's `.task` (ADR-0017, EditorWindowLifecycle).
    func open(selecting url: URL? = nil) {
        EditorModel.shared.activate(selecting: url)
        openWindow?(id: AppTapeApp.editorWindowID)
    }
}
