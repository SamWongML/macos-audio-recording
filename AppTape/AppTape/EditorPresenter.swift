import SwiftUI

/// Opens the editor window from outside SwiftUI — specifically from the status item's
/// stop-click, which is an AppKit event with no `@Environment(\.openWindow)` of its own.
@MainActor
final class EditorPresenter {
    static let shared = EditorPresenter()

    private var openWindow: OpenWindowAction?

    /// Called from a SwiftUI view's environment to hand over its `openWindow` action.
    func bind(_ action: OpenWindowAction) { openWindow = action }

    /// Opens the editor, optionally selecting the Recording just captured.
    func open(selecting url: URL? = nil) {
        EditorModel.shared.activate(selecting: url)
        openWindow?(id: AppTapeApp.editorWindowID)
    }
}
