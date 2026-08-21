# TCC & permissions research: capturing another app's audio (macOS 27)

Scope: this covers TCC/permission behavior for the two capture approaches under
consideration in ticket #2 — Core Audio process taps (`AudioHardwareCreateProcessTap`)
and ScreenCaptureKit audio-only capture — for a **local-only, unsandboxed, non-notarized**
SwiftUI app targeting **macOS 27.0 exclusively**. Every claim below is cited to either
(a) a file path + line/symbol in the macOS 27.0 SDK or an installed system framework on
this machine, (b) an official Apple Documentation page (fetched via the Apple doc search
tool), or (c) a web source with an exact URL. Anything not independently verifiable is
flagged as such rather than stated as fact.

This machine: Xcode 27.0 (build 27A5237l), macOS 27.0 (build 26A5416b), SDK at
`/Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk`
— note the installed Xcode is `Xcode-beta.app`, not `Xcode.app`; `/Applications/Xcode.app`
does not exist on this machine.

## TL;DR

- **Core Audio process taps** are gated by TCC service **`kTCCServiceAudioCapture`**,
  which System Settings surfaces as its own pane: **"System Audio Recording Only"** — a
  grant that is genuinely separate from Screen Recording and does **not** grant or require
  screen access. This has existed since **macOS 14.2 (Sonoma)**, not macOS 26/27 — see
  the correction in [§2](#2-does-macos-2627-introduce-a-distinct-system-audio-permission).
- **ScreenCaptureKit audio-only capture** (`SCStreamConfiguration.capturesAudio`, no
  video output) is, as far as this research can verify, still gated by the **combined**
  Screen Recording grant (`kTCCServiceScreenCapture`, System Settings pane **"Screen &
  System Audio Recording"**) — there is no evidence of a lighter audio-only path through
  ScreenCaptureKit. This is the single biggest TCC-related UX difference between the two
  candidate capture APIs: **the Core Audio tap path can ask for audio only, without ever
  touching Screen Recording; ScreenCaptureKit cannot.** See [§1](#1-tcc-permissions-per-capture-approach)
  for the evidence chain.
- Neither path requires a sandbox entitlement in this project, because the app is not
  sandboxed. `com.apple.security.device.audio-input` (the "Audio Input" entitlement) is
  an **App Sandbox** entitlement for microphone access — irrelevant here since (a) this
  project doesn't sandbox and (b) it's not capturing the microphone.
- **Local-signing stability (the highest-value question, §4):** TCC ties a grant to
  bundle identifier + the signing identity's Team ID (or, for ad-hoc/"Sign to Run
  Locally" builds, effectively to the binary's ad-hoc signature). The actionable
  takeaway confirmed across multiple independent Apple Developer Forums threads: **ad-hoc
  signing ("Sign to Run Locally") is the single biggest cause of TCC permission resets
  on every rebuild**, because Xcode re-signs the binary with a fresh ad-hoc signature
  (and, on Apple Silicon, the kernel enforces code-signature matching for already-running
  vs. newly-launched processes) on every build, which macOS treats as a different app.
  Signing with a **real Team ID — even a free Personal Team tied to any Apple ID — makes
  the grant stable across rebuilds**, because TCC's identity check keys off the stable
  Team ID + bundle ID pair rather than the ad-hoc hash. A paid Apple Developer Program
  membership is **not required** for grant stability. See [§4](#4-the-local-build-problem)
  for exact forum citations and the concrete Xcode settings.

## 1. TCC permissions per capture approach

### Core Audio process taps (`AudioHardwareCreateProcessTap`)

- **API surface and availability.** `AudioHardwareCreateProcessTap` /
  `AudioHardwareDestroyProcessTap` are declared in
  `CoreAudio.framework/Versions/A/Headers/AudioHardwareTapping.h`, both
  `API_AVAILABLE(macos(14.2))`. `CATapDescription` (the tap configuration object) is
  declared in `CoreAudio.framework/Versions/A/Headers/CATapDescription.h`,
  `API_AVAILABLE(macos(12.0), ios(15.0))` as a class, with two properties added later:
  `bundleIDs` (line 136) and `processRestoreEnabled` (line 167), both
  `API_AVAILABLE(macos(26.0))`. So the tap-creation API itself is not new; macOS 26 only
  added the ability to describe taps by bundle identifier (so a tap can be pre-configured
  to reattach to an app that isn't running yet) and to persist/restore taps across the
  tapped process restarting.
- **TCC service identifier.** Confirmed directly from the installed system's own TCC
  localization table on this machine:
  `/System/Library/PrivateFrameworks/TCC.framework/Versions/A/Resources/Localizable.loctable`
  (a binary plist; dumped via `plutil -convert json`), English locale, key
  `REQUEST_ACCESS_SERVICE_kTCCServiceAudioCapture`. This is ground truth — the actual
  string macOS 27 will show the user — not a secondary source.
- **Exact prompt text:** `"“%@” would like access to record your system audio."` (`%@` is
  replaced with the app's display name at prompt time.)
- **System Settings pane.** From
  `/System/Library/ExtensionKit/Extensions/SecurityPrivacyExtension.appex/Contents/Resources/Localizable.loctable`
  (the actual Privacy & Security settings-pane extension shipped on this machine), English
  locale:
  - `AUDIO_CAPTURE_HEADER` = `"System Audio Recording Only"` — the section title.
  - `AUDIO_CAPTURE` = `"System Audio Recording"` — the row label under it.
  - `AUDIO_CAPTURE_SUMMARY` = `"Allow the applications below to access and record your
    system audio."`
  - This is a **separate section** from Screen Recording (see below) — confirming the
    grant is independent and does not require or imply screen access.
- **Official Apple documentation** corroborates this is a distinct, audio-only grant: the
  relevant page is *"Capturing system audio with Core Audio taps"*
  (`/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps`,
  fetched via Apple doc search), subsection *"Configure the sample code project"*: "Before
  you run the sample code project in Xcode, ensure that you're using macOS 14.2 or later.
  > Important: To capture audio with a tap, you need to include the
  `NSAudioCaptureUsageDescription` key in your Info.plist file... **The first time you
  start recording from an aggregate device that contains a tap, the system prompts you to
  grant the app system audio recording permission.**" Note the prompt fires on first
  *recording* from the aggregate device the tap feeds into, not at tap-creation time.
- **Entitlement:** none. Neither `AudioHardwareTapping.h` nor `CATapDescription.h`
  reference any entitlement, and Apple's own sandboxed-capture guidance
  (`/documentation/AVFoundation/requesting-authorization-to-capture-and-save-media#Enable-entitlements-in-macOS`)
  only calls out `com.apple.security.device.camera` and
  `com.apple.security.device.audio-input` as needed *"if your app uses device
  cameras / microphones"* under App Sandbox — process taps capture other processes'
  *output*, not a hardware input device, and this project isn't sandboxed regardless.

### ScreenCaptureKit audio-only capture

- **API surface.** `SCStreamConfiguration.capturesAudio` (bool, default `NO`) has existed
  since `API_AVAILABLE(macos(13.0), ...)` —
  `ScreenCaptureKit.framework/Versions/A/Headers/SCStream.h:315`. Companion properties:
  `sampleRate`/`channelCount` (audio format), `excludesCurrentProcessAudio` (line 330,
  also macos 13.0), and (unrelated to this project's v1 scope, which explicitly excludes
  the microphone) `captureMicrophone`/`microphoneEnabled` (the latter macOS 27-only,
  `SCStream.h:192`).
- **TCC service identifier.** No ScreenCaptureKit header, and no Apple documentation page
  found via `DocumentationSearch`, references `kTCCServiceAudioCapture` in connection with
  `SCStream`/`SCStreamConfiguration`. Every piece of official guidance for the framework
  instead points to **`kTCCServiceScreenCapture`**:
  - The framework-level doc page `/documentation/ScreenCaptureKit` states plainly:
    *"Request screen recording permission from the person before capturing content. In
    the Info pane of the Xcode target editor, add a `NSScreenCaptureUsageDescription` key
    with a description of why your app requires screen recording access."* This sentence
    is not scoped to video-only capture — it's the framework's blanket permission
    requirement.
  - `SCShareableContent.h` (the API you must call *before* you can build an
    `SCContentFilter`, audio-only or not), header comment on
    `getCurrentProcessShareableContentWithCompletionHandler:`: the general
    `getShareableContentWithCompletionHandler:` "will contain the windows, displays and
    applications that are **available to capture**", and the redacted variant is
    described as returning content "available to capture by current process **without
    user consent via TCC**" — i.e., the non-redacted, normal enumeration path requires
    TCC consent up front, before any stream (audio or video) is even configured.
  - The Privacy & Security pane text (same
    `SecurityPrivacyExtension.appex` localization table cited above) makes the bundling
    explicit: `SCREEN_CAPTURE_HEADER` = `"Screen & System Audio Recording"`,
    `SCREEN_CAPTURE_SUMMARY` = `"Allow the applications below to record the content of
    your screen **and audio**, even while using other applications."` — the single
    combined Screen Recording grant is explicitly documented as covering *both* screen
    and audio for apps using that permission family. The separate, narrower
    `"System Audio Recording Only"` section (§ above) is presented as a distinct
    capability, and nothing in ScreenCaptureKit's docs or headers wires it up to that
    narrower grant.
  - **Caveat:** this is a well-evidenced *inference* (multiple independent primary
    sources agree), not a single explicit Apple statement of the form "SCStream audio
    always uses kTCCServiceScreenCapture." No sample project or doc page was found that
    exercises `capturesAudio = true` with `capturesVideo`-equivalent disabled and
    confirms which pane lights up. If ticket #2 leans toward ScreenCaptureKit, this
    specific point (audio-only via ScreenCaptureKit still requiring full Screen
    Recording consent) is worth a 5-minute empirical check on this machine before
    finalizing — build a minimal `SCStream` with `capturesAudio = true` and see which
    Privacy & Security section the running app appears under.
  - Sample-project doc corroboration: *"Capturing screen content in macOS: Configure the
    sample code project"* (`/documentation/ScreenCaptureKit/capturing-screen-content-in-macos#Configure-the-sample-code-project`):
    *"The first time you run this sample, the system prompts you to grant the app Screen
    Recording permission."* — this sample captures both audio and video, consistent with
    a single combined grant, but doesn't isolate the audio-only case.
- **Entitlements.** `SCStreamErrorMissingEntitlements` exists as an error case
  (`SCError.h`, since macOS 12.3), meaning *some* ScreenCaptureKit configurations do
  require entitlements — but the only ScreenCaptureKit-adjacent entitlement documented is
  `com.apple.developer.persistent-content-capture` (*"Entitlements: ScreenCaptureKit"* doc
  page), described as: *"A Boolean value that indicates whether a Virtual Network
  Computing (VNC) app needs **persistent** access to screen capture."* That's for apps
  that keep capturing while fully backgrounded/no foreground window across long-lived
  scenarios (VNC-style); a menu-bar app that captures only while the user has explicitly
  started a recording in the foreground app doesn't need it. No entitlement is required
  for ordinary (non-persistent, non-sandboxed) ScreenCaptureKit use.

## 2. Does macOS 26/27 introduce a distinct system-audio permission?

**Correcting a premise in the research brief:** the "System Audio Recording Only" /
`kTCCServiceAudioCapture` permission is **not new to macOS 26 or 27**. Apple's own sample
project documentation for Core Audio taps says the feature requires only *"macOS 14.2 or
later"* (`/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps#Configure-the-sample-code-project`),
and `AudioHardwareCreateProcessTap` itself is `API_AVAILABLE(macos(14.2))` in the SDK
header. So this separate, audio-only-without-screen-access permission has existed since
**macOS 14.2 (Sonoma point release)**.

What *is* true and directly relevant: **it can be requested without also granting screen
access.** The System Settings evidence in §1 shows two independent sections
("Screen & System Audio Recording" vs. "System Audio Recording Only") with independent
per-app grant lists — granting one does not touch the other. This satisfies the "bad UX"
concern in the brief: an app that only calls `AudioHardwareCreateProcessTap` and never
touches ScreenCaptureKit/CoreGraphics screen APIs will only ever surface the narrower
"System Audio Recording Only" prompt, never a full Screen Recording prompt.

What changed in macOS 26/27 specifically, per the SDK header diff (grepped
`API_AVAILABLE(macos(26.0))` / `macos(27.0)` across CoreAudio, AudioToolbox,
ScreenCaptureKit):

- **macOS 26.0:** `CATapDescription.bundleIDs` and `.processRestoreEnabled`
  (`CATapDescription.h:136,167`) — lets a tap be described by bundle ID and persist
  across the tapped process quitting/relaunching. `AUAudioMix`-related Audio Unit
  additions (spatial audio mixing, unrelated to permissions). `SCScreenshotManager`
  (single-frame capture) was added at macOS 26.0 — still under the same
  `kTCCServiceScreenCapture` family, no new permission type introduced for it.
- **macOS 27.0:** `AudioHardware.h`'s `kAudioDevicePropertySuggestedReferenceDevice`
  (unrelated to permissions). ScreenCaptureKit gained several 27.0-only APIs —
  `SCStreamErrorInsufficientStorage`/`NotSupported` (`SCError.h`),
  `SCContentSharingPicker.available`, `SCStream.microphoneEnabled`/`.capturing`,
  `SCStreamFrameInfoVideoOrientation`, `addClipBufferingOutput`/`removeClipBufferingOutput`,
  `SCRecordingEditor`, `SCRecordingOutputConfiguration.mixesAudioWithMicrophone`,
  `SCClipBufferingOutput` — all capture-*feature* additions (clip buffering, HDR
  presets, mic-mix-in, orientation metadata, insufficient-storage handling). **None of
  these introduce a new TCC service identifier or a new usage-description key.** No
  `NSSystemAudioCaptureUsageDescription` (or any other "system audio" plist key beyond
  `NSAudioCaptureUsageDescription`, which predates 26/27) exists anywhere in the macOS
  27 SDK headers or in Apple's `Information-Property-List` documentation reachable via
  `DocumentationSearch`.
- No `kTCCService*` string search of the installed TCC framework's own localization
  table turned up any additional audio- or screen-related service beyond
  `kTCCServiceAudioCapture`, `kTCCServiceScreenCapture`, `kTCCServiceMicrophone`, and
  `kTCCServiceRemoteDesktop` (which shares screen-capture's exact prompt string and is
  Remote Desktop/Screen Sharing's own permission, not relevant here).

## 3. Info.plist keys and entitlements

| Capture path | Info.plist key | Confirmed by |
|---|---|---|
| Core Audio process tap | `NSAudioCaptureUsageDescription` | Apple doc: `/documentation/BundleResources/Information-Property-List/NSAudioCaptureUsageDescription` — *"A message that tells people why your app is requesting access to capture system audio on macOS."* Also required per the Core Audio taps sample project doc (§1). |
| ScreenCaptureKit (video and/or audio) | `NSScreenCaptureUsageDescription` | Apple doc: `/documentation/ScreenCaptureKit` framework page (§1 quote). |
| (Not used in v1 — no microphone) | `NSMicrophoneUsageDescription` | Apple doc: `/documentation/AVFAudio/AVAudioApplication/requestRecordPermission(completionHandler:)` — *"Apps that access any of the device's microphones must declare their intent to do so… If an application attempts to access any of the device's microphones without a corresponding purpose string, the app exits."* Listed here only for completeness since v1 has no mic capture. |

Keys that were searched for but **do not exist** anywhere in the macOS 27 SDK headers,
`BundleResources` documentation, or the TCC framework's own strings:
`NSSystemAudioCaptureUsageDescription` (does not exist — `NSAudioCaptureUsageDescription`
is the real key for system audio, and always has been since 14.2). No key name has
shifted between macOS 26 and 27 for either path.

**Entitlements:** none required for either capture path in this project, because:
1. The app is unsandboxed (per project constraints), so App Sandbox device entitlements
   (`com.apple.security.device.audio-input`, `.microphone`, `.camera`) don't apply — those
   only govern access when `com.apple.security.app-sandbox` is also present.
2. Core Audio process taps have no documented entitlement requirement at all (§1).
3. ScreenCaptureKit's only documented entitlement (`com.apple.developer.persistent-content-capture`)
   is scoped to VNC-style persistent/background capture, not this project's use case (§1).

**Paid Apple Developer Program membership:** not required for either the Info.plist keys
or any entitlement identified above — none of them are gated, Apple-approval-required
capabilities. This is a meaningful category on Apple's platforms generally (contrast with,
e.g., `com.apple.developer.endpoint-security.client` — *"You must request this entitlement
from Apple"* — or `com.apple.vm.networking` — *"This entitlement is restricted to
developers of virtualization software. To request this entitlement, contact your Apple
representative"*), but nothing analogous was found anywhere in Apple's documentation for
screen or system-audio capture: neither `NSAudioCaptureUsageDescription` /
`NSScreenCaptureUsageDescription` nor `com.apple.developer.persistent-content-capture`
carry any "request from Apple" / "not available on free accounts" language. The membership
question that *does* matter is about **code-signing stability for TCC grants**, covered
next.

## 4. The local-build problem

This is a runtime code-signing/TCC behavior question that cannot be fully verified from
static SDK headers alone — it requires either Apple's own guidance on the mechanism (found
in the code-signing technotes, §4a) or real-world developer reports confirming it plays out
as expected in practice (§4b). Both agree, and — notably — the forum answers below are from
the same Apple DTS engineer ("Quinn 'The Eskimo!'") who is the credited author of the
TN3126/TN3127/TN3179 code-signing technotes already cited elsewhere in this document, so the
official-doc and forum evidence are not independent — they're the same person's explanation
in two venues, which is worth knowing but doesn't weaken the technical content.

### 4a. The underlying mechanism (Apple's own technotes)

TCC records a grant keyed by (a) the requesting app's bundle identifier, and (b) a
representation of its code-signing identity via the code's **designated requirement (DR)**.
For a properly signed app (any real Apple-issued identity — including a free "Apple
Development" identity from a Personal Team), the DR references the bundle ID plus "signed
by an Apple-issued certificate of this class," which doesn't change between rebuilds — so
the grant survives. For an ad-hoc-signed app ("Sign to Run Locally", no Team), there is no
Apple-issued certificate to build a DR against, so identity tracking falls back to the
binary's cdhash, which is different on every rebuild — see
[TN3127: Inside Code Signing: Requirements](https://developer.apple.com/documentation/Technotes/tn3127-inside-code-signing-requirements)
and [TN3179: Understanding local network privacy](https://developer.apple.com/documentation/Technotes/tn3179-understanding-local-network-privacy#Build-time-considerations).
TN3127 shows the actual DR Xcode embeds for a free "Apple Development" identity —
`identifier "<bundle-id>" and anchor apple generic and certificate leaf[subject.CN] =
"Apple Development: …" and certificate 1[...] /* exists */` — which depends only on the
bundle ID and the certificate, never on the compiled binary's bytes, and states directly:
*"A privilege, like microphone access, acquired by an existing version of your app is
still available to a new version."* TN3179 states the ad-hoc-signing problem directly for
the sibling mechanism that uses the same code-identity approach: *"Local network privacy
tracks the identity of your program using its code signature. This presents a challenge on
macOS, which allows for unsigned code and ad hoc signed code (Xcode displays this as Sign
to Run Locally). To ensure that local network privacy reliably tracks the identity of your
macOS program, sign it with an Apple-issued code-signing identity."*

### 4b. Real-world corroboration (Apple Developer Forums)

- **[Why does my app lose Screen Recording permission after updating (adhoc signature)?](https://developer.apple.com/forums/thread/795739)**
  — Original poster: *"For example, in version 1.0.0, I grant Screen Recording permission
  to the app. Later, I build a new version (1.1.0) and update by dragging the new app into
  the Applications folder to overwrite the previous one. However, when I launch the updated
  app, it asks for Screen Recording permission again, even though I have already granted it
  for the previous version."* Apple DTS engineer Quinn's reply: *"In general, macOS tracks
  code identity using the code's designated requirement. Ad hoc signed code does not include
  a stable DR, and thus macOS is unable to tell that version N+1 of your app is the 'same
  code' as version N."* His fix, verbatim: *"Sign your code with a stable code-signing
  identity, ideally one issued by Apple. That means: Apple Development, during development
  [...] Apple Distribution, for submission to the App Store [...] Developer ID, for direct
  distribution."* And explicitly: *"Ad hoc code signing has its place — for example, it's
  great for open source tooling like Homebrew — but it will cause problems if you're
  building a Mac app that you intend to distribute widely."* — **this is a direct,
  high-authority confirmation of the exact scenario this project needs to avoid**, and
  confirms "Apple Development" (free, personal-team) is Apple's own recommended fix for
  local development, not just a workaround.
- **[How to handle TCC permissions on macOS](https://developer.apple.com/forums/thread/730043)**
  (context: CI/UI-test automation, but the guidance is general) — a poster reports: *"We're
  testing ad-hoc signed bundles as well as DeveloperID signed ones with the same Application
  ID and it seems that TCC gets confused over time and simply treats the permissions as not
  granted."* Quinn's guidance: *"when dealing with TCC it's best to sign your code with a
  stable signing identity, typically, Apple Developer for day-to-day work and Developer ID
  for final distribution... Doing this will radically cut down on the amount of TCC
  thrash."* He also explicitly warns against mixing ad-hoc and Developer ID signatures under
  the same bundle ID, and recommends CI pipelines use Apple Development signing rather than
  ad hoc for exactly this reason.
- **[CapSoftware/Cap issue #1722](https://github.com/CapSoftware/Cap/issues/1722)** ("Local
  dev builds unable to test screen recording on macOS Sequoia — TCC/ScreenCaptureKit
  completely broken for unsigned binaries") — independent, non-Apple corroboration from a
  real screen-recording app's contributors: `CGPreflightScreenCaptureAccess()` consistently
  returned `false` for ad-hoc/unsigned debug builds even after granting permission in System
  Settings; the reporter tried five different ad-hoc-signing workarounds, all unsuccessful,
  before the thread converges on the same conclusion as the two forum threads above —
  proper (non-ad-hoc) signing is required for stable local TCC state. Useful as evidence
  this isn't a one-off report but a broadly-hit problem across multiple real projects.

### Practical fix

Configure the target with a **real signing identity** — a free **Personal Team** (tied to
any Apple ID, no paid membership) is sufficient, per Apple's own DTS guidance above — rather
than "Sign to Run Locally". This gives the app a stable Apple-issued-certificate-anchored DR,
which is what TCC's identity check keys off, so a grant made once persists across rebuilds
even though DerivedData paths rotate and the binary's raw bytes change build-to-build. A
paid Developer ID is not required for this stability; it mainly buys distribution outside
Xcode's debugger (Gatekeeper/notarization), which is explicitly out of scope for this
project.

## 5. Runtime detection of permission state

### Core Audio process tap path

- **No CGPreflight-equivalent exists.** `CGPreflightScreenCaptureAccess` /
  `CGRequestScreenCaptureAccess` are declared in
  `CoreGraphics.framework/Versions/A/Headers/CGWindow.h:300,308`
  (`API_AVAILABLE(macos(10.15))`) and are explicitly scoped to Screen Recording: the
  header doc for `CGRequestScreenCaptureAccess` says *"A previously denied process is not
  re-prompted; the user must enable access in System Settings > Privacy & Security >
  Screen Recording."* Nothing in `CoreAudio.framework` or `AudioToolbox.framework`
  declares an analogous preflight/request pair for `kTCCServiceAudioCapture`. A full grep
  of both frameworks for `Preflight`/`Authoriz`/`Permission`/`Consent` inside headers
  turned up **no such API**.
- **Practical detection mechanism:** attempt the operation and inspect the `OSStatus`.
  `AudioHardwareBase.h:166` defines `kAudioDevicePermissionsError = '!hog'` — the error
  Core Audio's HAL returns when the calling process lacks the required permission. In
  practice this surfaces when you try to start I/O on (or read from) an aggregate device
  that contains a tap the user hasn't granted "System Audio Recording Only" for yet — the
  doc-cited behavior in §1 is that the *prompt itself* fires the first time you start
  recording from such a device, so the natural pattern is: create the tap and aggregate
  device, attempt to start it, and handle a `kAudioDevicePermissionsError` result (denied
  or not yet decided will look the same at this call — see caveat below).
- **Distinguishing "not yet asked" from "denied":** no public API was found for this on
  the Core Audio side. `AVAudioApplication.recordPermission` (§ next) only covers the
  *microphone*, not process taps, so it cannot be reused here. Since this project is
  local-only, the pragmatic answer given in the checklist below is to track "have we
  attempted this before" in the app's own `UserDefaults`, since the OS gives no
  first-class tri-state API for this specific service.

### ScreenCaptureKit path

- `CGPreflightScreenCaptureAccess()` / `CGRequestScreenCaptureAccess()` (same CoreGraphics
  APIs above) are the conventional way apps check/request Screen Recording before using
  ScreenCaptureKit, and — per §1's evidence that ScreenCaptureKit's audio-only capture
  rides on the same `kTCCServiceScreenCapture` grant — these should apply to the
  audio-only case too. `CGPreflightScreenCaptureAccess` returns a plain `bool`; per its
  header doc, *"If this returns false, call `CGRequestScreenCaptureAccess` to prompt the
  user."* Neither function distinguishes "never asked" from "denied" — both surface as
  `false`/no prompt-on-retry, per the `CGRequestScreenCaptureAccess` doc comment quoted
  above ("a previously denied process is not re-prompted"). Apps conventionally infer
  "previously denied" by tracking, in their own state, whether they already called
  `CGRequestScreenCaptureAccess()` once.
- Alternative/complementary: calling `SCShareableContent.getShareableContentWithCompletionHandler:`
  or `.current` and inspecting the returned `NSError`/empty-content result is the
  ScreenCaptureKit-native way to detect a missing grant, since `SCStream` itself fails at
  configuration/start time with `SCStreamErrorUserDeclined` (`SCError.h`, -3801) if the
  user has denied access. This does distinguish "declined" from other failure modes, but
  still doesn't cleanly separate "not yet asked" — `CGPreflightScreenCaptureAccess()` is
  the more direct check for that.

### AVCaptureDevice/microphone family (not used, noted for completeness)

Not applicable to v1 (no microphone), but included since the brief asked: microphone
detection uses `AVCaptureDevice.authorizationStatus(for: .audio)` returning
`AVAuthorizationStatus` (`.notDetermined`/`.authorized`/`.denied`/`.restricted`) — this
*does* cleanly distinguish "not yet asked" (`.notDetermined`) from "denied" (`.denied`),
unlike either of the two APIs actually used by this project. Source:
`/documentation/AVFoundation/AVCaptureDevice/authorizationStatus(for:)` and
`/documentation/BundleResources/requesting-authorization-for-media-capture-on-macos`.

## 6. macOS 27 vs. macOS 26 changes summary

See §2 for the full header-level diff. Net summary: **no permission-model change**
between macOS 26 and 27 for either capture path. All macOS 26/27-tagged APIs found in
CoreAudio/ScreenCaptureKit/AudioToolbox are capture-*feature* additions (bundle-ID-based
tap description and tap process-restore in 26; clip buffering, HDR presets, mic-mix-in,
orientation metadata, insufficient-storage/not-supported error cases, and a
`.microphoneEnabled`/`.capturing` state surface in 27) — none of them add, rename, or
deprecate a TCC service, a usage-description Info.plist key, or an entitlement relevant
to this project.

---

## Project configuration checklist

Actionable steps for ticket #11 (Scaffold the Xcode project). Written to be
copy-paste-executable regardless of which capture API ticket #2 selects; the
Core-Audio-tap-only and ScreenCaptureKit-only lines are marked.

### 1. Signing (do this first — it's the rebuild-stability fix)

- In the target's **Signing & Capabilities** tab: check **"Automatically manage
  signing"**, and select **your Personal Team** (a free Apple ID account is enough — no
  paid enrollment needed) as the Team. Do **not** leave Signing Certificate on
  **"Sign to Run Locally"** — that's the ad-hoc-signing path that causes TCC grants to
  reset on every rebuild (§4).
- Pick a **stable, permanent bundle identifier** now (e.g.
  `com.<yourname>.macos-audio-recording`) and do not change it later — every TCC grant is
  keyed to it, and changing it orphans all prior grants and forces every permission to be
  re-requested.
- Do not rely on the default Xcode-generated bundle ID scheme if it's liable to change
  (e.g., tied to a project rename) — treat the bundle ID as a fixed, deliberate choice.

### 2. Info.plist keys

Add whichever key(s) correspond to the capture path ticket #2 selects:

- **If Core Audio process taps:** add `NSAudioCaptureUsageDescription` with a real
  purpose string, e.g. *"This app needs system audio access to record audio from the
  application you select."*
- **If ScreenCaptureKit:** add `NSScreenCaptureUsageDescription` with a real purpose
  string, e.g. *"This app needs screen recording access to capture audio from the
  application you select."* (Framing the copy around "audio," even though the OS-level
  grant is the full screen-recording one, sets correct user expectations given §1's
  finding that ScreenCaptureKit audio-only still requires full Screen Recording consent.)
- Do **not** add `NSMicrophoneUsageDescription` (v1 has no microphone capture) or
  `NSSystemAudioCaptureUsageDescription` (not a real key — verified absent from the SDK
  and Apple's documentation, §3).

### 3. Entitlements

- None required for either path, given this project is unsandboxed and doesn't need
  persistent/background capture. Do not enable App Sandbox, and do not add
  `com.apple.developer.persistent-content-capture` unless a future version needs
  capture to survive full backgrounding VNC-style (§1, §3).

### 4. Runtime permission handling to implement

- **Core Audio tap path:** create the tap + aggregate device, attempt to start it, and
  handle `kAudioDevicePermissionsError` (`AudioHardwareBase.h`, `'!hog'`) as the
  "no permission" signal (§5). Track locally (e.g. `UserDefaults`) whether the app has
  already triggered this flow once, since there's no OS-level tri-state query for this
  service.
- **ScreenCaptureKit path:** call `CGPreflightScreenCaptureAccess()` before attempting to
  build an `SCStream`; if `false`, call `CGRequestScreenCaptureAccess()` to prompt (only
  effective the first time — a prior "Don't Allow" requires the user to flip it on
  manually in System Settings, since a denied process is not re-prompted per the header
  doc in §5). Handle `SCStreamErrorUserDeclined` (`SCError.h`, -3801) as a fallback signal.

### 5. Developer-iteration commands

`tccutil` (confirmed via `strings /usr/bin/tccutil` on this machine — it accepts the full
`kTCCService*` name or the same string with the `kTCCService` prefix omitted):

```sh
# Reset the "System Audio Recording Only" grant for this app (Core Audio tap path)
tccutil reset AudioCapture <your.bundle.id>

# Reset the "Screen & System Audio Recording" grant for this app (ScreenCaptureKit path)
tccutil reset ScreenCapture <your.bundle.id>

# Reset everything TCC knows about this bundle ID, across all services
tccutil reset All <your.bundle.id>
```

Use these between test runs whenever you need to re-exercise the first-prompt flow
during development — far faster than manually toggling switches in System Settings.

### 6. Open item to verify empirically before finalizing ticket #2

Confirm experimentally (outside this research pass) which System Settings section lights
up when a minimal `SCStream` is configured with `capturesAudio = true` and no video
consumer — this research found strong indirect evidence (§1) that it's the combined
"Screen & System Audio Recording" grant, not the narrower "System Audio Recording Only"
one, but no single Apple source states this outright for the audio-only configuration
specifically.
