# macOS 27 design guidance for a Dock-first AppTape

Research date: September 18, 2026. This is research and a proposed design direction, not an accepted ADR or an implementation specification. It extends [App format](app-format.md) with version-specific Apple evidence. The recommended product shape is a normal Mac application with a complete recording and editing window, plus a secondary menu bar recording surface. Apple supports this arrangement; Apple does not mandate it for all recorders.

## Evidence and version boundaries

The distinction between macOS 26 and 27 matters materially. Some currently indexed HIG pages retain 2025 text, while WWDC26 explicitly changes the Mac appearance. Prefer the version-specific 2026 descriptions and actual macOS 27 system components for geometry; retain the HIG's enduring interaction principles. The official [macOS 27 guide](https://developer.apple.com/wwdc26/guides/macos/) confirms platform refinements and links the 2026 design and SwiftUI sessions. This report does not infer that every new cross-platform SwiftUI placement is available on Mac.

| Topic | Verified Apple evidence | Consequence for AppTape |
| --- | --- | --- |
| Sidebar edges | WWDC26 Keynote says Mac sidebars now extend to window edges. | Do not rebuild the inset floating sidebar appearance from the macOS 26 launch. |
| Toolbar structure | WWDC26 Keynote describes a more uniform toolbar supporting text and headings. | Restore a real toolbar and let the OS provide its structure. |
| Window corners | WWDC26 State of the Union describes a consistent tighter radius across Mac windows. | Use the system window; remove reasons to imitate old radius measurements. |
| Glass preferences | WWDC26 introduces a user-controlled Liquid Glass tint slider. | Let standard materials respond to the preference. |
| Menu icons | macOS 27 reduces menu-item symbol images by default. | Do not apply the 2025 advice to iconize every action indiscriminately. |

The first, second, and fourth changes are directly described in the [WWDC26 Keynote](https://developer.apple.com/videos/play/wwdc2026/101/). The corner change and automatic uniform toolbar treatment as content scrolls are described in [Platforms State of the Union, WWDC26](https://developer.apple.com/videos/play/wwdc2026/102/). Its explanation also makes clear that existing scroll-edge APIs can customize this treatment. These sources supersede the 2025 visual description; they do not prescribe AppTape's information architecture.

The [macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes) and their indexed beta content describe reduced symbols in AppKit and SwiftUI menus, preserving selected system commands and providing explicit image-visibility overrides. For SwiftUI, `labelStyle(.titleAndIcon)` can retain a meaningful icon. Prefer icons where they identify a Source or another object; make deliberate exceptions for important actions. Search indexing exposed both older beta and newer release titles, so verify exact signatures against the installed SDK before implementation.

## Design principles that change the product, not just its skin

Apple's 2026 design principles treat purpose, agency, responsibility, familiarity, flexibility, simplicity, craft, and delight as trade-offs to resolve for people. They emphasize that every additional feature consumes attention and trust. A redesign should therefore make the existing capture-to-export journey coherent before expanding into a general audio workstation. [Principles of great design, WWDC26](https://developer.apple.com/videos/play/wwdc2026/250/)

**Recommendation:** preserve the present domain: one Source, immutable Recording, folder-backed Library, non-destructive Trim and Gain, and Export. A Dock-first design can transform discoverability, navigation, visual hierarchy, and recording control without introducing tracks, projects, effects, pause/resume, or recording schedules. Those would be separate product decisions.

The key success criterion is that someone launching AppTape can choose a Source, record, stop, find the result, trim, and export without discovering the menu bar helper. The helper then earns its place by reducing app switching while the person works in the Source.

## Main window and navigation

Apple distinguishes primary windows, which contain navigation and main content, from auxiliary windows dedicated to a particular task. It recommends standard window UI, fluid resizing, and restraint in opening additional windows. [HIG: Windows](https://developer.apple.com/design/human-interface-guidelines/windows)

**Recommendation:** begin with one primary Library-and-editor window. Keep recording setup and ongoing recording status in that window. A dashboard that only leads to another window adds an extra step to a small product; separate Recording windows should be justified by a demonstrated need to compare or work on several recordings simultaneously. An empty Library must still be a useful recording surface.

Apple describes split views as adjacent panes for related levels of content: selecting an item in a leading pane reveals its contents in a following pane. That is a natural match for a Recording list and selected Recording. [HIG: Split views](https://developer.apple.com/design/human-interface-guidelines/split-views)

**Recommendation:** avoid adding a navigation sidebar containing only “Library” and “Recordings.” If there is only one collection, its list can be the leading pane. Introduce top-level navigation only when there are actual peer destinations. The waveform should occupy the largest useful area, with playback and Trim directly associated with it. Recording controls refer to a live Source; playback controls refer to a saved Recording. Their proximity must not imply that selecting an old Recording changes capture's Source.

The HIG supports hiding a sidebar, concise hierarchy, and adapting to smaller windows. Its currently indexed geometric description says floating/inset, which is specifically older than the WWDC26 edge-to-edge change. Preserve its interaction guidance without freezing that older geometry. [HIG: Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)

**Recommendation:** design narrow-window behavior deliberately: protect the waveform and current Stop action; let the Library collapse using the standard sidebar control where appropriate. Do not choose the existing 960-point floor simply because it exists. Measure the minimum usable width on the redesigned interface with long recording and application names.

## Toolbar, commands, and recording visibility

Apple recommends a restrained toolbar for frequent actions, logical groups, system overflow, and menu-bar equivalents for toolbar commands. Standard components are preferable to custom backgrounds that interfere with system rendering. [HIG: Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)

**Recommendation:** start with these conceptual groups, then validate actual layout:

- Window navigation: show/hide Library and the selected Recording's title.
- Capture: Source chooser plus Record, changing to a clearly labeled Stop and recording state while active.
- Selected Recording actions: Export, with less frequent commands in menus or contextual controls.

Playback and detailed Trim controls can remain near the waveform, where their subject is unambiguous. Do not make every action prominent. The current elapsed recording time is status, not an unlabeled button. A persistent live-capture strip is an alternative if source names, meters, and Runway make the toolbar overcrowded; prototype both with real content.

SwiftUI's toolbar visibility priorities move less important items into overflow first. A high priority keeps an item visible longer; it is not an absolute guarantee. [Apple: visibilityPriority](https://developer.apple.com/documentation/swiftui/toolbarcontent/visibilitypriority(_:))

**Recommendation:** give Stop the highest relevant priority, but also make it reachable through the app's command menu. Test the narrowest supported size rather than assuming a priority prevents disappearance. The 2026 SwiftUI session also presents `ToolbarOverflowMenu`, pinned trailing placement, and navigation-bar minimization, but its examples span platforms. Keep a recording transport stable while scrolling instead of copying an iPhone's hiding navigation bar. [What’s new in SwiftUI, WWDC26](https://developer.apple.com/videos/play/wwdc2026/269/)

The installed Apple-authored [SwiftUI 27 toolbar reference](/Users/demon/.codex/skills/swiftui-whats-new-27/references/toolbar.md) resolves the platform trap: `.low`/`.high` visibility priorities are available on macOS 26.1, and relative priority initializers arrive on macOS 27. `ToolbarOverflowMenu` and `.topBarPinnedTrailing` are iOS/visionOS only. Explicit `.onScrollDown`/`.onScrollUp` minimization is iOS only; Mac supports the automatic case. Do not put the unavailable examples into AppTape's specification. The reference is local SDK guidance, distinct from the browser sources above.

The same session verifies updated automatic Liquid Glass rendering, custom interactive glass on Mac, and the `appearsActive` environment for custom inactive-window treatment. Those are useful adoption details, not reasons to replace standard buttons with bespoke glass controls.

## Inspector and Export

In the macOS 26 AppKit design explanation, sidebars and inspectors are distinct structural regions; AppKit split items supply appropriate materials. It also warns against making informational toolbar text look like a glass-backed button and against hard-coding control heights. Those enduring distinctions remain useful even though 27 revises the outer geometry. [Build an AppKit app with the new design, WWDC25](https://developer.apple.com/videos/play/wwdc2025/310/)

**Recommendation:** keep per-Recording Gain, Loudness, Quality Preset, and Export together as a secondary editing area. Decide whether that area must always be visible based on the workflow and minimum width. A native inspector is worth a fresh prototype, but it is not an automatic requirement. A separate Export sheet is also viable if export settings are infrequently adjusted; it would be a substantive workflow change, not cosmetic modernization.

[ADR-0024](../adr/0024-trailing-column-not-inspector.md) records crashes and sidebar interactions in an older `.inspector` plus `NavigationSplitView` configuration, as well as a deliberate always-visible 276-point column. These are repository evidence and product decisions, not an Apple ban on inspectors. No verified Apple source in this investigation establishes that the exact defects are fixed in macOS 27. Reproduce the actual layout on the target SDK/OS before replacing the workaround. Do not claim that absence from release notes proves resolution.

## Liquid Glass, color, and visual hierarchy

Apple places Liquid Glass in the controls/navigation layer and explicitly advises against using it for content backgrounds; ordinary materials differentiate content. [HIG: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)

**Recommendation:** the waveform, Recording list, time ruler, and numeric export facts remain content. Do not wrap each in glass cards. Use real toolbars, native sidebar structure, and system control styles to obtain the current appearance. Custom glass should solve a specific floating-control problem, not become the redesign's visual objective.

Apple recommends semantic system colors, consistent color meanings, appearance and contrast variants for custom colors, and signals beyond color alone. [HIG: Color](https://developer.apple.com/design/human-interface-guidelines/color)

**Recommendation:** preserve meaningful waveform/Trim distinction but reevaluate it on current surfaces. Record/Stop needs text or shape as well as red. Source icons are useful identity information. Keep decorative tint restrained so a recording indicator remains immediately recognizable. Test both appearances, increased contrast, and the new glass preference extremes; copied RGB values and screenshot-matched translucent fills are not a durable platform strategy.

## Menu bar helper and Dock lifecycle

Apple's `MenuBarExtra` documentation explicitly demonstrates a normal window plus an extra for frequently used functionality when the app is inactive. Its window style supports richer controls. Menu-bar-only apps are a separate supported configuration, using `LSUIElement` to omit Dock/app-switcher presence. [Apple: MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)

**Recommendation:** treat “helper” initially as a second surface in the same app process, not a separate installed agent. A separate process that survives Quit creates additional questions about capture ownership, state transfer, launch-at-login, and the meaning of Quit. Apple guidance does not require that complexity for an extra.

The `.regular` activation policy describes an ordinary app with Dock presence; `.accessory` omits the Dock and application menu bar. [Apple: ActivationPolicy](https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum)

**Recommendation:** use stable regular identity throughout the app's running lifetime. Explicit launch opens a useful window. Closing the last window leaves capture running and does not remove the Dock identity. Quit finalizes capture and exits the app and helper under a clearly decided policy. These are recommendations for AppTape; they intentionally revisit [ADR-0017](../adr/0017-activation-policy.md).

AppKit's reopen callback handles Finder and Dock reactivation. Miniaturized windows count as visible in that callback, a relevant edge case when deciding whether to recreate or reveal a window. [Apple: applicationShouldHandleReopen](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldhandlereopen(_:hasvisiblewindows:))

**Recommendation:** Dock activation restores or reveals the primary window without duplicating it. “Open AppTape” in the helper does the same. A Dock menu may offer Record/Stop and Show Library, but it must remain a shortcut: Apple says its commands should also be available elsewhere. [HIG: Dock menus](https://developer.apple.com/design/human-interface-guidelines/dock-menus)

The new `NSStatusItem.expandedInterfaceDelegate` publicly documents lifecycle callbacks for custom expanded UI; standard `NSMenu` items use the system's own handling. [Apple: expandedInterfaceDelegate](https://developer.apple.com/documentation/appkit/nsstatusitem/expandedinterfacedelegate)

**Recommendation:** choose the menu-bar interaction before choosing its API. A consistent click-to-open helper can use standard menu or popover behavior; if the direct Stop gesture is retained, make its meaning unmistakable and preserve an obvious way to inspect state without stopping. [ADR-0011](../adr/0011-hand-rolled-menu-bar-panel.md) contains measured left-click, Escape, and repeat-click trade-offs for the new delegate. These remain local evidence to recheck, not behavior to assume solved by Dock-first identity.

Suggested helper contents are Source, idle/waiting/recording state, elapsed time, Record/Stop, and Open AppTape. A meter is useful if it genuinely confirms incoming audio. Detailed waveform editing and Export settings belong in the main window. Whether stopping from the helper foregrounds the app is a product choice: automatically bringing it forward helps immediate editing but interrupts someone still working in the Source.

## Accessibility and precise recording language

Apple asks for perceivable, adaptable interfaces, contrast testing, larger text support, non-color state cues, VoiceOver descriptions, and inspection with Accessibility Inspector. [HIG: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)

**Recommendation:** core capture actions must work from the keyboard and VoiceOver in the main app. Give Source, Record, Stop, playback, and Trim handles meaningful labels and values. Provide numeric or other keyboard-operable Trim adjustment so dragging a narrow waveform handle is not the sole route. Announce state changes without reading every meter update or clock tick. Essential Stop must not rely on a hidden right-click route. Test Reduce Motion and avoid continuous pulsing as the only evidence of recording.

The 2026 naming session favors language that sets expectations, fits its audience, and remains understandable across contexts and languages. [Craft clear names for features and labels in your app, WWDC26](https://developer.apple.com/videos/play/wwdc2026/290/)

**Recommendation:** preserve the glossary's established terms. Distinguish “Waiting for audio” after arming from an actual Recording beginning at first sound. A visible zero timer alone does not explain that distinction. Name an unavailable Source and offer a recovery action; do not imply an audio permission denial unless it is known. Keep Export and Save distinct because Recordings already save automatically.

## Decisions to settle and validation work

The research supports a native, full-workflow primary window and secondary recording access. It does not settle these choices:

1. One Library/editor window or separate Recording windows; default to one unless comparison is a primary task.
2. Helper in the main process or an independently persistent service; default to the same process unless surviving Quit is explicitly required.
3. Consistent helper click-to-open or direct Stop; decide discoverability versus one-click speed explicitly.
4. Stop reveals/selects the result or preserves the user's current focus; consider initiation context.
5. Always-visible Export area or collapsible inspector/sheet; decide from frequency and usable width.
6. Active capture while browsing/editing older Recordings; the UI must preserve the distinction even if supported.

Prototype with empty Library, a silent Source, active recording, an unavailable Source, low Runway, a long filename, an unreadable adopted file, and Export in progress. Exercise launch, close, minimize, hide, Dock reopen, app switching, and Quit while recording. Validate narrow and tiled windows, keyboard navigation, VoiceOver, both appearances, increased contrast, reduced transparency/motion, and glass preference extremes. These are proposed checks, not completed test results.

Before implementation, explicitly revisit ADR-0004, 0011, and 0017 for capture/lifecycle; 0023, 0024, 0025, 0030, 0034, and 0035 for window/Export layout; and any color/material records whose measured surfaces change. Preserve their historical evidence. A revised product decision does not retroactively invalidate the measurements that justified the old implementation.
