# Architecture decision records

One file per decision, numbered in the order it was taken: the context, the decision, and what
it costs. Source files do not cite these — start here.

| # | Decision | Status |
|---|---|---|
| [0001](0001-core-audio-process-taps.md) | Capture Source audio with Core Audio process taps, not ScreenCaptureKit | accepted |
| [0002](0002-personal-team-code-signing.md) | Sign local builds with a free Personal Team, never "Sign to Run Locally" | accepted |
| [0003](0003-immutable-caf-master.md) | Every Recording is an immutable lossless CAF master, trimmed non-destructively | accepted |
| [0004](0004-nsstatusitem-transport.md) | The menu bar item is an NSStatusItem, and it is the transport | accepted |
| [0005](0005-lossless-export-preset.md) | The lossless Export preset is 24-bit ALAC, and is not called Lossless | accepted |
| [0006](0006-library-is-a-folder.md) | The Library is an ordinary folder, and a Recording's metadata rides in extended attributes | accepted |
| [0007](0007-faults-pad-dropouts.md) | Mid-Recording faults pad a Dropout rather than stopping the Recording | accepted |
| [0008](0008-denied-grant-inferred.md) | A denied grant is inferred from silence, never reported | accepted |
| [0009](0009-runway-clock-disk-guard.md) | The disk guard is a Runway clock, not a byte count | accepted |
| [0010](0010-silence-and-dropouts.md) | Silence never ends a Recording, and every gap becomes a Dropout | accepted |
| [0011](0011-hand-rolled-menu-bar-panel.md) | The panel stays hand-rolled; the expanded-interface session is not worth the left-click | accepted |
| [0012](0012-non-blocking-export.md) | Export runs non-blocking in the inspector, and navigating away from the Recording cancels it | accepted |
| [0013](0013-loudness-clamped-gain.md) | Loudness normalization is one clamped gain, not a limiter | accepted |
| [0014](0014-hold-off-idle-sleep.md) | A Recording holds off idle system sleep, but only the idle timer | accepted |
| [0015](0015-adopted-file-faithful-or-refused.md) | An adopted file is faithful-or-refused, never silently converted | accepted |
| [0016](0016-recording-starts-at-first-sound.md) | A Recording begins at the first sound, not the first press | accepted |
| [0017](0017-activation-policy.md) | AppTape is `.accessory` at rest and `.regular` while the editor is open | accepted |
| [0018](0018-no-xcuitest-layer.md) | AppTape ships no XCUITest layer; the suite is unit and integration tests | accepted |
| [0019](0019-content-colour-palette.md) | The app owns two content colours and nothing else | accepted |
| [0020](0020-rename-refuses.md) | The Library shows the name you chose, and a rename refuses rather than fixes | accepted |
| [0021](0021-growing-recording-re-adopted.md) | A Recording that grew is re-adopted, not followed | accepted |
| [0022](0022-explicit-nonisolated-background-work.md) | Background work is explicitly `nonisolated` | accepted |
| [0023](0023-detail-pane-layout.md) | The detail pane is ruler, lane, summary, dock | accepted |
| [0024](0024-trailing-column-not-inspector.md) | The trailing pane is a column, not a SwiftUI inspector | accepted |
| [0025](0025-library-row-and-inspector.md) | The Library row is one line; the inspector states the Export | accepted |
| [0026](0026-app-icon.md) | Prism Pulse is the app icon | accepted |
| [0027](0027-transport-readout-width.md) | The transport reserves its widest readout | accepted |
| [0028](0028-motion-is-feedback.md) | Motion is feedback | accepted |
| [0029](0029-selection-and-focus-fills.md) | The selection fill is the system's; the focus ring is ours | accepted |
| [0030](0030-editor-default-height.md) | The trailing column sets the editor's default height | accepted |
| [0031](0031-growing-recording-figures.md) | A growing Recording states the engine's figures, or nothing | accepted |
| [0032](0032-measure-treatments-on-target-surface.md) | A treatment is measured on the surface it lands on, in both appearances | accepted |
| [0033](0033-playhead-is-an-instrument.md) | The playhead is an instrument, not content | accepted |
| [0034](0034-single-empty-state.md) | An empty state is spoken once, by the pane that owns the fact | accepted |
| [0035](0035-trailing-column-top-edge.md) | The trailing column's fill reaches the window's top edge | accepted |
| [0036](0036-dock-boundary.md) | The Export dock's boundary is the system's, and it is conditional | accepted |
| [0037](0037-warning-colour-on-the-mark.md) | A warning's colour belongs to its mark, not to its sentence | accepted |
| [0038](0038-dock-fill.md) | The Export dock's fill is the bottom bar's own | accepted |
| [0039](0039-dark-pane-fills.md) | In Dark the panes' fill and the step between them come from the wallpaper | accepted |
| [0040](0040-trimmed-away-colour.md) | The Trimmed-away half is authored, not filtered | accepted |
| [0041](0041-reason-outside-the-control.md) | A blocker's reason sits outside the control, not inside it | accepted |
| [0042](0042-dock-states-the-blocker.md) | The dock states the blocker; the control does not wear it | accepted |
| [0043](0043-capture-run-accepts-its-world.md) | One run of capture accepts its world, and takes time as a parameter | accepted |
| [0044](0044-single-recording-read-point.md) | A Recording is read once, at a single boundary | accepted |
| [0045](0045-views-accept-their-state.md) | The views accept their state; they do not reach for it | accepted |
| [0046](0046-export-refuses-once.md) | An Export refuses once, and both callers ask | accepted |
| [0047](0047-single-points-to-seconds-mapping.md) | The lane maps points to seconds in one place | accepted |
| [0048](0048-export-identifies-by-recording.md) | An Export's subject is the Recording, not the path it had at launch | accepted |
| [0049](0049-envelope-cache-is-derived-data.md) | The envelope cache is derived data, and is keyed on the file | accepted |
