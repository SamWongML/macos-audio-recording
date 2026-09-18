**Recommendation: make AppTape a regular desktop app with menu bar recording controls.**

Research date: September 17, 2026. This is a product recommendation, not an adopted architecture decision. It draws on the current repository, Apple's design guidance, and first-party product documentation. No comparative user testing was performed.

AppTape records audio from one running application, saves recordings into a folder-backed Library, and provides playback, waveform trimming, loudness correction, gain, and export. That combination benefits from two surfaces: compact controls while someone works in the source application, and a normal window when someone works on the resulting recording. I recommend keeping the Dock and Command-Tab presence while AppTape is running, with a menu bar control that users can enable or disable. Closing the window should leave an active recording running; opening AppTape again should restore a useful window.

Confidence is higher in the two-surface recommendation than in the preferred Dock default. The former follows directly from the two workflows. The latter is a judgment about discoverability and lifecycle simplicity that should be tested with intended users.

The relevant comparison is:

| Product shape | Main advantage | Main cost for AppTape | Assessment |
| --- | --- | --- | --- |
| Menu bar only, including all editing | Very small desktop footprint | Constrains sustained waveform editing, library browsing, and export work | Poor fit for the existing feature set |
| Menu bar utility with a separate editor and a conditional Dock icon | Fast capture, unobtrusive between uses | Users must learn where the app goes; activation-policy transitions add lifecycle work | Viable for frequent capture users; close to today's design |
| Desktop app without menu bar controls | Clear entry point and stable window behavior | More switching away from the source app to manage recording | Leaves an important workflow underserved |
| Desktop app with menu bar controls | Quick capture plus discoverable library and editing | Uses a Dock slot while running; requires consistent controls across surfaces | Recommended default |

These assessments are design inferences, not measured conversion rates or usability scores. Recording duration alone should not decide the result: a long recording can involve very little interaction, while a short recording can require substantial editing.

Apple describes menu bar extras as a way to access an app while another app is in front. Its guidance also says extras can be hidden when space is limited, recommends letting users choose whether to display them, and advises exposing functionality through additional routes. This supports a menu bar shortcut without making it the only capture interface. Apple prefers a menu for simple commands, allowing a more elaborate presentation when the functionality warrants it. AppTape's source list and live meters may justify a richer panel. [Apple Human Interface Guidelines: The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar#Menu-bar-extras)

Apple also explicitly supports apps that live entirely in the menu bar, including richer popover-like interfaces. A desktop default is therefore a recommendation for AppTape's workflow, not an Apple requirement or a claim that menu bar utilities are invalid. [Apple: MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)

The closest product precedents show several valid arrangements:

| Product | Documented behavior | Implication for AppTape |
| --- | --- | --- |
| Audio Hijack | A main session window supports management and controls. An optional menu bar window can start, stop, and monitor sessions while the app is in the background. | Strong precedent for combining normal windows with quick recording controls. [Session Basics](https://rogueamoeba.com/support/manuals/audiohijack/?page=sessionbasics) |
| Piezo | Launch opens a main window containing source selection, meters, and Record. | Even a simple app-audio recorder can reasonably use a desktop window as its entry point. [Using Piezo](https://rogueamoeba.com/support/manuals/piezo/?page=usage) |
| SoundSource | Lives in the menu bar, has no Dock or Command-Tab entry, and offers a global shortcut and a pinnable window. | A credible menu bar model for recurring audio adjustments; its task differs from managing and editing saved recordings. [Main Window Overview](https://www.rogueamoeba.com/support/manuals/soundsource/?page=main-window-overview) |
| Apple Screenshot / QuickTime screen recording | Recording can stop through a menu bar Stop button or a keyboard shortcut; the captured result can then be edited. | Supports separate capture and editing surfaces, and confirms that direct menu bar Stop is an established recording pattern. [Apple recording guide](https://support.apple.com/en-us/102618) |
| CleanShot X | Provides capture history and a dedicated video editor with trimming and export. | An adjacent example of a quick capture tool also needing substantial post-capture UI; this does not establish its Dock policy. [CleanShot X](https://cleanshot.com/) |

These sources establish what the products offer, not whether their interface choices cause commercial success or are preferred by AppTape's audience.

AppTape already implements much of the hybrid. Its [app scene](/Users/demon/codes/macos-audio-recording/AppTape/AppTape/AppTapeApp.swift:17) creates a normal editor window, defaulting to 1200 × 680, but suppresses it at launch. [ADR-0017](/Users/demon/codes/macos-audio-recording/docs/adr/0017-activation-policy.md) makes the app accessory at rest and regular while the editor exists. The material decision is therefore whether its desktop identity should persist when the editor closes, and whether the window should offer recording controls.

The current empty state directs users to the menu bar to record, rather than offering capture inside the window. The [source](/Users/demon/codes/macos-audio-recording/AppTape/AppTape/EditorView.swift:159) and [ADR-0034](/Users/demon/codes/macos-audio-recording/docs/adr/0034-single-empty-state.md) make this deliberate. A desktop version should replace that dead end with a source chooser and a clear Record action, then keep recording status and Stop accessible as the library fills. Merely retaining the Dock icon would be an incomplete redesign.

ADR-0017 rejects a permanent Dock icon partly because there would be nothing useful behind it at rest. That conclusion depends on the existing launch and empty-state choices. A window containing the Library and a New Recording action would give the Dock icon a purpose even before the first recording. Reopening from the Dock or launching through Finder or Spotlight should reliably reveal that window.

There is also a concrete engineering tradeoff. The repository's [editor-close investigation](/Users/demon/codes/macos-audio-recording/docs/investigations/2026-09-16-editor-close-menu-bar.md) documents the coordination required when changing activation policy. A stable regular policy would remove those runtime policy transitions. It would not, by itself, prove that every reported menu bar animation is fixed: the investigation explicitly leaves visual confirmation outstanding. This is supporting evidence for simplicity, not the sole reason to change the product.

I would specify the proposed behavior as follows:

1. **Explicit launch opens the Library window.** An empty Library offers source selection and Record; an existing Library offers recordings plus New Recording. Any future launch-at-login feature can start quietly by a separate, deliberate rule.
2. **The window provides a complete core workflow.** Users can choose a source, start and stop, inspect recording status, play, trim, adjust loudness, and export without having to locate the menu bar icon.
3. **The menu bar provides quick access.** Keep source selection, recording status, Stop, and Open Library readily available, with one underlying recording state shared by both surfaces. Offer the menu bar option during setup and in settings.
4. **Closing and quitting remain distinct.** Closing the window preserves active capture and leaves the app recoverable through the Dock. Quit ends and finalizes recording. The final exit behavior should be communicated clearly.
5. **Keep the Dock identity stable by default.** Do not promote and demote the application each time the editor opens or closes. Defer a hide-Dock preference until there is evidence that the audience values it enough to justify supporting the alternate lifecycle.
6. **Provide a keyboard route to capture controls.** A configurable global shortcut is a useful follow-up, particularly for full-screen use. Essential controls should also work with keyboard navigation and assistive technology inside the app.

The current status-item click deserves a separate decision. [MenuBarController](/Users/demon/codes/macos-audio-recording/AppTape/AppTape/MenuBarController.swift:62) opens the panel while idle but stops recording on left-click while active; right-click then becomes the panel route. One-click Stop has Apple precedent, so it is not inherently wrong. The concern is that a dot and timer may look like status to inspect. My preferred default is for the app icon to open controls consistently. If direct Stop is retained, make its stop meaning visually explicit and supply another obvious route to inspect capture without ending it. This recommendation would revisit ADR-0004 rather than silently override it.

A menu bar default would become more attractive if users primarily collect quick clips, export immediately, rarely return to the Library, and strongly prefer keeping a recorder resident without a Dock icon. A desktop default becomes more attractive when users revisit recordings, compare them, adjust exports, or launch the app only when needed. AppTape's current feature set supports the latter path, but actual usage remains unknown.

Before adopting a change, run a small exploratory comparison with roughly six to eight intended users. Give both versions the same tasks: make a first recording, inspect it without stopping, recover the app after closing its window, find yesterday's recording, trim and export it, and stop while the source app is full screen. Counterbalance which version people see first. Observe completion, hesitation, lost-app incidents, accidental stops, and keyboard access, then ask about Dock preference. This is a practical qualitative check, not a statistically representative preference study. No test results are claimed here.

Implementing this proposal would require revisiting ADR-0017 and the capture entry-point assumptions in ADR-0034. Revising status-item clicks or keyboard scope would also revisit ADR-0004 and the decisions it references. This research leaves those accepted decisions and application code unchanged.