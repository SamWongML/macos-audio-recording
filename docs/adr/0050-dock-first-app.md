---
status: accepted
---

# 0050. AppTape is a Dock-first app with a secondary recording helper

AppTape has one primary Library/editor window with Source selection and recording controls available even when the Library is empty, and keeps its Dock identity while running so launching and returning to the app always has a useful destination. The menu bar helper belongs to the same application: closing the window leaves capture running, while Quit exits both surfaces; an independent background service would complicate ownership and the meaning of Quit without serving the agreed workflow. The redesign rethinks presentation and interaction around the existing recording, Trim, Gain, Loudness and Export capabilities.

This supersedes ADR-0017's conditional Dock identity and launch-suppressed editor, and amends the menu-bar-only capture entry points in ADR-0004 and ADR-0034. The decision is accepted for the redesign; the lifecycle slice is implemented, while the remaining recording controls, inspector, commands and Export lifetime work are pending.

## Recording interaction

Clicking the helper consistently opens its controls, including an explicit Stop button, rather than ending a Recording immediately; this amends ADR-0004 and removes the one-click-stop requirement behind ADR-0011 without assuming that its measured framework problems have disappeared. Stopping from the helper saves quietly and offers Show Recording, while stopping in the main window selects the completed Recording for editing; quitting during capture asks the user to choose Stop Recording and Quit or Keep Recording. The helper is enabled by default and can be disabled in Settings, because the main window supports the complete workflow.

Both surfaces separate Source selection from Record, remember the chosen Source and prevent changing it during capture. A compact recording strip above the editor content keeps Source, recording status and Stop independent of playback and the selected Recording.

## Editing while recording

The user can browse, play, trim and export older Recordings while capture continues, with the active Source, elapsed time and Stop available independently of the selected Recording. Quality Preset, Loudness, Gain and Export live in a collapsible inspector whose visibility is remembered, amending ADR-0024's permanently visible column; using SwiftUI's inspector implementation still requires checking its historical layout failures on the target system. ADR-0045's dependency-injection rule remains, but its restriction that the editor cannot command capture is amended so both surfaces can control the same capture owner.

Capture, playback and Export have keyboard-accessible commands, and Trim has editable time fields and VoiceOver support; a system-wide recording shortcut is deferred. This amends ADR-0023's rejection of typable Trim points and its previous layout around an editor without capture controls. If the selected Recording disappears from the Library, the window stays open, clears selection and explains that the file is no longer available rather than closing or automatically selecting another Recording.

## Export lifetime

One Export at a time continues through selection changes, inspector collapse and window closure, with app-wide progress and Cancel available when the window is shown. Quitting with an unfinished Export requires confirmation, amending ADR-0012's automatic cancellation on navigation or close while preserving its parameter snapshot and atomic destination replacement. This makes Export an application-owned operation rather than work whose lifetime depends on the selected Recording's view.

## Lifecycle implementation

Issue #140 implements a stable regular application identity and automatic launch of the single Library/editor window, including an empty Library; Dock reopen reveals that window after hide, minimize or close without involving the helper. The shared `EditorPresenter` owns presentation, and removing a selected file clears selection and stops playback while leaving the workspace open with an unavailable explanation. Closing the window leaves capture running; Export still cancels on navigation and window closure until its dedicated lifetime ticket implements the decision above.

The [Apple design research](../research/macos-27-dock-first-design.md) remains the supporting evidence, and ADR-0017 retains the measurements and rationale for the superseded conditional identity.
