# Dock lifecycle validation

Implementation: issue #140. Tested with Xcode 27.0 (27A266a), macOS 27.0 (26A428),
and an Apple Development signed Debug build.

## Automated checks

- Full Swift Testing suite: 358 tests passed.
- Focused EditorModel and EditorPresenter suites passed after their failing cases were established.
- Strict swift-format lint, git diff whitespace checks, and signed build passed.
- Standards and Spec reviews found no actionable code issues.

## Native checks completed

- Fresh explicit Finder launch opens the primary Library/editor without opening the helper.
- Reopening from Finder after minimizing or hiding restores the editor with its selection.
- Closing the editor leaves the application running; Finder reopen creates one editor with its selection preserved.
- A temporary one-second WAV was adopted and played, then moved out of the Library through Finder. Playback stopped, selection cleared, the editor remained open, and it displayed “Recording unavailable” with “The selected file is no longer in the Library.” No other Recording was selected.
- The temporary file was moved to `/private/tmp`; the original 42 Library Recordings were unchanged.

Finder reopen exercises the application reopen callback; it does not establish the visual Dock-click behavior.

## Still to verify manually

- Direct Dock clicks, stable Dock/app-switcher presence and absence of visual flicker through the lifecycle.
- Fresh launch with an empty Library (covered at the model/presenter seam, not exercised against the populated user Library).
- Closing the editor during live capture and returning while capture continues.

The native UI tool provided access to the editor and Finder but did not provide usable Dock/helper controls; attempts to inspect the Dock timed out. No UI-test target was added.
