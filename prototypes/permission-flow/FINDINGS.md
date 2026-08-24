# FINDINGS — the permission probe (issue #14)

Throwaway instrument. The question: **is a TCC denial of `kTCCServiceAudioCapture` observable
from inside the app?** [The ticket assumed yes](https://github.com/SamWongML/macos-audio-recording/issues/14),
via `kAudioDevicePermissionsError`. It is not.

Run with `./run.sh` (one run) or `./deny.sh` (drives the denied case end to end).
Everything below is measured on macOS 27.0, under bundle id `com.samwongml.AppTape.PermProbe`
— deliberately **not** AppTape's own id, so denying it never touches the real app's grant.

## The headline: denial is silent, and identical to silence

| | granted | **denied** |
|---|---|---|
| `AudioDeviceStart` | `noErr`, 0.000 s | **`noErr`, 0.000 s** |
| IOProc callbacks in 6 s | 563–564 | **563–565** |
| buffers all-zero | 0 | **all of them** |
| peak | 0.0999 | **0.0** |

`kAudioDevicePermissionsError` (`'!hog'`) exists in `AudioHardwareBase.h` and **never appeared
once**, in any state. A denied app is not told it is denied: the aggregate device is created,
the IOProc is installed, and the device calls it at the normal rate forever, with every sample
exactly zero.

So the app's only discriminator is the cross-check the picker already has for free:

```
VERDICT all-zero while 2 process(es) report output   <<< THE SILENT FAILURE
```

`kAudioProcessPropertyIsRunningOutput` says the Source is producing audio; the tap says
digital silence. Neither fact alone means anything. Together they mean no permission.

## The instrument had to be fixed twice, and both bugs are findings

**A process hearing its own audio is not a TCC-gated act.** The first cut emitted a tone from
the probe itself via `AVAudioEngine`, and a global tap captured it at peak exactly 0.1000 with
no grant, no prompt, and no `tccd` involvement at all. Granted and denied looked identical for
the wrong reason. The tone had to move into a **separate process** (`afplay`) before the
capture was gated. **The app therefore cannot self-test its permission** by tapping itself —
that path always succeeds.

**An unanswered prompt is a hang, not an error.** With the prompt on screen and nobody
clicking, the blocking moved *earlier* than expected:

```
 1.178  aggregate.create status=0
61.185  ioproc.create status=0                     <- blocked 60.007 s
91.190  device.start RETURNED noErr after 30.005s  <- then blocked another 30.005 s
        callbacks=0                                <- and the device never called us at all
```

Two round-number timeouts, and `AudioDeviceCreateIOProcIDWithBlock` is the one that ate a
whole minute — **before `AudioDeviceStart` is even reached**. This qualifies
[#12](https://github.com/SamWongML/macos-audio-recording/issues/12)'s "`AudioDeviceStart`
blocking 90 s behind the TCC prompt": the 90 s is not one call, it is 60 + 30 across two.
Any timeout on starting a Recording has to wrap the **whole** bring-up, not just the start.

Note also that this is a **third** state, distinguishable from the other two: zero callbacks
is not the same observation as zero-valued callbacks.

| state | `AudioDeviceStart` | callbacks | samples |
|---|---|---|---|
| granted | `noErr`, instant | ~94/s | real audio |
| denied | `noErr`, instant | ~94/s | all zero |
| prompt unanswered | `noErr`, after 30 s | **none** | — |

## What `tccd` shows that the API does not

The OS **does** have a preflight path for this service — it is just not exposed to us:

```
AUTHREQ_CTX: service=kTCCServiceAudioCapture, preflight=yes   -> authValue=1 (unknown)
AUTHREQ_CTX: service=kTCCServiceAudioCapture, preflight=no    -> AUTHREQ_PROMPTING
```

`preflight=yes` answers without prompting: `authValue` 0 = denied, 1 = never asked,
2 = allowed. Core Audio asks this question internally on every tap start. There is no public
API that reaches it (grepped CoreAudio and AVFoundation across the macOS 27 SDK), but it is
worth knowing the state genuinely exists rather than assuming the OS is as blind as we are.

## The recovery surface

`x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture` **works**.
`Privacy_AudioCapture` is a real anchor in `SecurityPrivacyExtension.appex`, which declares
`legacyBundleIdentifier = com.apple.preference.security`.

One wrinkle worth designing around: the window it opens is titled
**"Screen & System Audio Recording"**, not "System Audio Recording Only" — that is the
section *within* the pane. An app that has promised it never wants screen access sends the
user to a page whose heading says Screen Recording.

## Also confirmed

- `tccutil reset AudioCapture <id>` returns the state to never-asked and the prompt genuinely
  comes back — observed three times from the granted state.
- `kAudioTapPropertyFormat` reads back a plausible `rate=48000 ch=2 flags=0x9` **in every
  state, including denied**, re-confirming
  [#11](https://github.com/SamWongML/macos-audio-recording/issues/11).

## Not established

Whether flipping the toggle in System Settings recovers a **running** tap, or whether the app
has to rebuild it (or relaunch). That decides what the recovery message tells the user to do
after they flip the switch, and it is not answered here.
