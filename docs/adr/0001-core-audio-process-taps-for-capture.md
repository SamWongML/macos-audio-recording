---
status: proposed — pending validation by the Chrome/Safari capture spike
---

# Capture Source audio with Core Audio process taps, not ScreenCaptureKit

We need to capture the audio of one chosen running application on macOS 27, locally, without asking the user to install a virtual audio driver. An exhaustive grep of the installed macOS 27.0 SDK confirms the field is exactly two APIs — no newer or higher-level system-audio API shipped in macOS 26 or 27. We chose **Core Audio process taps**: `AudioHardwareCreateProcessTap` with a `CATapDescription`, read through an aggregate device's IOProc.

## Considered options

**ScreenCaptureKit** was rejected. It is a screen-capture API that happens to carry audio: every `SCContentFilter` initializer that can scope to an application requires an `SCDisplay`, so there is no display-free audio path, and Apple's own sample always attaches a `.screen` output. It asks for the Screen Recording permission — a screen-shaped prompt that Apple documents as requiring an app restart after the first grant, which is a poor first run for a menu bar app whose only ask is to hear what a browser is playing. Its `SCRunningApplication` carries a single `processID`, with nothing in the headers about how helper-process audio is attributed.

**Core Audio process taps** won on three counts. They are the actual audio primitive — an Apple Developer Forums answer redirects an audio-only ScreenCaptureKit user straight to `AudioHardwareCreateProcessTap`. They use the narrower System Audio Recording permission. And macOS 26 added `CATapDescription.bundleIDs` and `.processRestoreEnabled`, aimed squarely at our hardest case: Chrome has routed audio through a separate Audio Service process since v76, so the process that owns the HAL client is not the process the user thinks of as "the browser".

## Consequences

Two risks ride along, both real and both cited in the research:

- Process taps are reported to **silently degrade to all-zero PCM buffers**, correlated with output sample-rate renegotiation. The callback keeps firing with valid timestamps; only the samples are dead. The only reported recovery is destroying and recreating *both* the tap and the aggregate device. The app must detect and recover from this rather than trust the callback.
- A tap has been reported failing silently against Microsoft Teams while ScreenCaptureKit-based tools succeeded. Teams is a WebRTC app, architecturally unlike our named targets, so this is a caution flag rather than a disqualifier.

The exact runtime semantics of `bundleIDs` and `processRestoreEnabled` are undocumented and unreported in the wild — in particular whether a helper process spawned fresh for a newly-opened tab is picked up automatically. This decision is **provisional until a spike proves capture works against real Chrome and Safari sessions**; if it does not, ScreenCaptureKit is the fallback and this ADR gets superseded.

Full research, with SDK header line citations: `docs/research/capture-api.md` on branch `research/capture-api`, and issue #2.
