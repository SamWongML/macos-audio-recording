# What the probe found — issue #12

Every claim below is a line in `logs/`. The run is named after each one.

**Verdict: process taps capture both browsers. [ADR-0001](../../docs/adr/0001-core-audio-process-taps-for-capture.md)
is confirmed, not superseded — but its headline reason for choosing taps does not survive.**

## 1. `bundleIDs` works, and cannot be used

It is an **exact match on an app bundle**. No prefix rule, and no reach into XPC services.

| Aim | Result | Log |
|---|---|---|
| `["com.google.Chrome"]`, mixdown init | **nothing** — zero callbacks while Chrome played | `213555` |
| `["com.google.Chrome"]`, bare init | **nothing** — so it is not the init shape | `213706` |
| `["com.google.Chrome.helper"]` | captures, peak 0.59–0.84 | `213656` |
| `["com.samwongml.AppTape.ToneEmitter"]` (an ordinary app) | captures, peak exactly 0.2500 | `214931` |
| `["com.apple.Safari"]` | **nothing** — Safari owns no HAL client | `214010` |
| `["com.apple.WebKit.GPU"]` | **nothing**, twice, while `pid 92638` reported `isRunningOutput=Y` | `214052`, `214225` |
| `processes: [117, 119, 121]` — the same WebKit processes, by object ID | captures Bilibili, peak 0.82–0.96 | `214152` |

The last two rows are the finding. The bundle ID in the failing row is not a guess: it is the exact
string `kAudioProcessPropertyBundleID` reports for the process that an object-ID tap successfully
captures at peak 0.92. The difference is what kind of bundle it is:

```
/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/
    com.apple.WebKit.GPU.xpc/Contents/MacOS/com.apple.WebKit.GPU
```

An **XPC service**, where Chrome's helper and the tone emitter are `.app` bundles. So `bundleIDs`
resolves app bundles and nothing else, and **Safari — half the reason this ticket exists — is
unreachable by it**. Aim by process object ID.

This costs ADR-0001 one of its three reasons for preferring taps over ScreenCaptureKit: `bundleIDs`
was cited as "aimed squarely at our hardest case". It is aimed at the easy half of it.

## 2. `processRestoreEnabled` is the API that matters, and it defaults to **on**

Undocumented: a `CATapDescription` nobody has touched reads back `isProcessRestoreEnabled == true`.
The probe originally only assigned the property when enabling it, which silently made its own
"disabled" control a no-op — worth knowing before writing the same bug in the app.

Kill the Source and relaunch it as a **different pid**, under a live tap:

- **restore on** — capture resumes at full level within ~1 s, no re-aiming, no recreate (`215059`:
  `pid 55395` dies, `pid 55434` arrives, peak back to 0.2500).
- **restore off** — the relaunched process reports `isRunningOutput=Y` and the tap delivers
  **all-zero buffers indefinitely** (`215313`: `pid 56083`, zero for the rest of the run).

That second row is the silent all-zero failure ADR-0001 warns about, reproduced on demand — and its
cause here is a disabled restore, not sample-rate renegotiation.

**Restore works on object-ID taps too** (`215531`: `processes=[122]`, `bundleIDs=[]`, emitter
relaunches as `pid 56732`, capture resumes). So aiming by object ID does not forfeit it.

## 3. A tap can be built before its target exists

Aimed at a bundle ID matching no running process, a tap captures that process as soon as it launches
— including **Chrome started from cold** (`215433`: helper `pid 56457`, peak 0.48).

The ticket's "is a helper spawned for a *new tab* picked up?" turns out not to arise: Chrome routes
every tab through **one** audio service process. Opening a second video mid-capture produced no
`proc.added` and no interruption (`213831`).

## 4. Sample-rate renegotiation did not break the tap

Forcing the output device 48000 → 44100 → 48000 mid-capture (`213831`):

```
[+00:15.083] MARK   ***  SET OUTPUT RATE 48000 -> 44100 Hz  ***
[+00:15.165] TICK   peak=0.8321 callbacks=100 nonZeroBuf=97 zeroBuf=3
[+00:16.107] TICK   peak=0.8302 callbacks=88  nonZeroBuf=79 zeroBuf=9
[+00:17.107] TICK   peak=0.7866 callbacks=94  nonZeroBuf=94 zeroBuf=0
```

A dozen dropped buffers, then normal. **The tap's own format never moved**: still
`rate=48000 ch=2 bits=32 fmt=lpcm`, still 48128 frames/s, while the device ran at 44.1 kHz. The
format property listener never fired once, in any run. The tap is insulated from the output device's
rate — so a Recording's sample rate is fixed at tap creation and cannot change underneath it.

Not reproducing the failure is not proof it cannot happen; it is one machine, built-in speakers.
But the reported trigger did not trigger it.

## 5. Destroy-and-recreate is a clean recovery

`213831` at `+00:41`: tap and aggregate destroyed and rebuilt, capturing again by `+00:42`.

## 6. Numbers the rest of the map can use

- Delivered format: `rate=48000 ch=2 bits=32 fmt=lpcm flags=0x9 bytesPerFrame=8` — **interleaved**
  Float32 stereo (`0x9` = `IsFloat | IsPacked`, no `IsNonInterleaved`). One buffer of 4096 bytes per
  callback = 512 frames, ~94 callbacks/s.
- **Peak exceeded 1.0**: `peak=1.0914` on YouTube (`213831` at `+00:27`) — the post-mix float above
  0 dBFS that [#24](https://github.com/SamWongML/macos-audio-recording/issues/24) has to handle,
  observed rather than assumed.
- `AudioDeviceStart` **blocked for 90 s** while the TCC prompt was on screen (`202505`), then
  returned `noErr`.
- The grant survived rebuild-and-relaunch with no second prompt — [ADR-0002](../../docs/adr/0002-sign-with-a-personal-team-not-ad-hoc.md) again.
- **The IOProc is not called at all until something on the system plays.** Once running it keeps
  being called, delivering zeros, even after the tapped process dies. A Recording started while the
  Source is silent may therefore receive no frames at all for that stretch.

## 7. A caveat about the probe's own stall detector

"All-zero buffers while the target reports `isRunningOutput=Y`" fires a **one-tick false positive**
at the instant a restored process comes back (`215059` at `+00:18`), because the process registers as
producing output a beat before its audio reaches the tap. Any such detector in the app needs a grace
period.
