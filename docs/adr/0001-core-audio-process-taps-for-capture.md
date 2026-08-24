---
status: accepted
---

# Capture Source audio with Core Audio process taps, not ScreenCaptureKit

We need to capture the audio of one chosen running application on macOS 27, locally, without asking the user to install a virtual audio driver. An exhaustive grep of the installed macOS 27.0 SDK confirms the field is exactly two APIs — no newer or higher-level system-audio API shipped in macOS 26 or 27. We chose **Core Audio process taps**: `AudioHardwareCreateProcessTap` with a `CATapDescription`, read through an aggregate device's IOProc.

## Considered options

**ScreenCaptureKit** was rejected. It is a screen-capture API that happens to carry audio: every `SCContentFilter` initializer that can scope to an application requires an `SCDisplay`, so there is no display-free audio path, and Apple's own sample always attaches a `.screen` output. It asks for the Screen Recording permission — a screen-shaped prompt that Apple documents as requiring an app restart after the first grant, which is a poor first run for a menu bar app whose only ask is to hear what a browser is playing. Its `SCRunningApplication` carries a single `processID`, with nothing in the headers about how helper-process audio is attributed.

**Core Audio process taps** won on three counts. They are the actual audio primitive — an Apple Developer Forums answer redirects an audio-only ScreenCaptureKit user straight to `AudioHardwareCreateProcessTap`. They use the narrower System Audio Recording permission. And macOS 26 added `CATapDescription.bundleIDs` and `.processRestoreEnabled`, aimed squarely at our hardest case: Chrome has routed audio through a separate Audio Service process since v76, so the process that owns the HAL client is not the process the user thinks of as "the browser".

## Consequences

The spike in issue #12 captured Chrome playing YouTube and Safari playing Bilibili, at full level, through a tap. Taps are the right primitive and this ADR stands. Three of the things recorded above need correcting.

**`bundleIDs` cannot aim the tap.** It is an exact match on **app bundles** only: it captures `com.google.Chrome.helper`, and an ordinary app by its own bundle ID, but it matches nothing for `com.google.Chrome` — there is no prefix rule — and nothing for `com.apple.WebKit.GPU`, even though that is the exact bundle ID the HAL client reports, and a tap aimed at the very same process by object ID captures it at full level. WebKit's audio lives in an XPC service, not an app bundle. Since Safari is half the reason this decision exists, **the app aims taps by process object ID**, resolving the Source's helper processes itself. That voids one of the three reasons recorded above for preferring taps: `bundleIDs` is aimed at the easy half of the helper-process problem, not at the hard half.

**`processRestoreEnabled` is the property that earns its keep, and it defaults to on.** A `CATapDescription` nobody has touched already reads back `true`, which the header does not say. With it enabled, a Source that quits and relaunches as a different process is picked up again within about a second, with no re-aiming — and this works for object-ID taps as well as bundle-ID ones, so aiming by object ID forfeits nothing. Assign the property explicitly rather than only when enabling it, or the disabled case silently stays enabled.

**The all-zero failure is real, but not from the trigger recorded above.** Forcing the output device from 48 kHz to 44.1 kHz and back mid-capture cost about a dozen dropped buffers and then recovered on its own; the tap's own format never moved, staying 48 kHz Float32 stereo while the device ran at 44.1 kHz, and the format property listener never fired. What *did* produce indefinite all-zero buffers — the callback still firing, the Source still reporting `kAudioProcessPropertyIsRunningOutput` — was a Source restarting under a tap with `processRestoreEnabled` turned off. So detection cannot rely on the callback stopping: it must cross-check the buffers against the Source's `isRunningOutput`, with a grace period, because a restored process reports output a beat before its audio reaches the tap. Destroying and recreating both tap and aggregate device remains a clean recovery, verified. The policy for each of these events is issue #13's to settle.

The remaining caution stands unchanged: a tap has been reported failing silently against Microsoft Teams, a WebRTC app architecturally unlike our named targets.

Three measurements the capture path inherits. The tap delivers **interleaved** Float32 stereo (`flags=0x9`), 512 frames per callback at roughly 94 callbacks a second. Its sample rate is fixed at tap creation and cannot change underneath a Recording. And the IOProc is not called at all until something on the system is playing, so a Recording started while the Source is silent may receive no frames for that stretch — issue #33.

Full research, with SDK header line citations: `docs/research/capture-api.md` on branch `research/capture-api`, and issue #2. Spike evidence: `prototypes/tap-browser-capture/FINDINGS.md` on branch `prototype/tap-browser-capture`, and issue #12.
