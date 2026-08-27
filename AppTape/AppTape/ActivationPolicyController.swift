//
//  ActivationPolicyController.swift
//  AppTape
//

import AppKit

/// Flips the app between `.accessory` at rest and `.regular` while the editor
/// window is open (ADR-0017). The flip is *existence-based*, not focus-based:
/// the app is `.regular` for exactly as long as an editor window is open,
/// regardless of which app is frontmost, so ⌘-Tabbing to the app being recorded
/// does not make the Dock icon and menu bar flicker away.
///
/// `LSUIElement` makes the app launch `.accessory` with no Dock-icon flash;
/// SwiftUI 27 exposes no scene-level activation-policy API, so the flip stays an
/// AppKit call in the app shell.
@MainActor
final class ActivationPolicyController {
    static let shared = ActivationPolicyController()

    /// How many editor windows are open. A single `Window` scene tops out at
    /// one, but a count keeps the flip robust against paired open/close reports.
    private var openEditorCount = 0

    func editorDidOpen() {
        openEditorCount += 1
        apply()
    }

    func editorDidClose() {
        openEditorCount = max(0, openEditorCount - 1)
        apply()
    }

    /// The policy implied by how many editor windows are open. Existence-based:
    /// any open window is `.regular`, only zero is `.accessory` — the whole rule,
    /// kept pure so it can be tested without a running app.
    nonisolated static func policy(forOpenEditorCount count: Int) -> NSApplication.ActivationPolicy {
        count > 0 ? .regular : .accessory
    }

    private func apply() {
        let policy = Self.policy(forOpenEditorCount: openEditorCount)
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }
}
