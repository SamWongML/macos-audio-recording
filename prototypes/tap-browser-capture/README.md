# PROTOTYPE — Does a process tap really capture Chrome and Safari? (issue #12)

Throwaway. Not production code.

```sh
./run.sh    # builds, signs, launches. A window opens; logs land in ./logs/
```

## Why this is an instrument, not a design prototype

There is no UI question in [#12](https://github.com/SamWongML/macos-audio-recording/issues/12)
and no state model to feel out. The question is empirical: `CATapDescription.bundleIDs` and
`.processRestoreEnabled` are new in macOS 26, documented by one line of header comment each,
and unreported in the wild. So this is a probe with a window on it — every control either
**aims** the tap, **perturbs** the system, or **writes down what the human just did**.

The deliverable is `logs/probe-*.txt`.

## The instrument

**Four strategies**, because "does `bundleIDs` work" is really four questions:

| Strategy | What it proves |
|---|---|
| `processObjectIDs` | The baseline from [#6](https://github.com/SamWongML/macos-audio-recording/issues/6): enumerate the helpers by hand, tap their object IDs. Known to work. |
| `bundleIDsOnMixdownInit` | `CATapDescription(stereoMixdownOfProcesses: [])`, then set `bundleIDs`. The likely intended shape. |
| `bundleIDsOnBareInit` | `CATapDescription()` with the mixdown flags set by hand — in case the empty process array is what breaks the other path. |
| `globalControl` | Taps everything. **If this reads zero, the problem is the grant or the audio, not the aiming.** |

**Every property is read back off the description after construction** (`tap.description` in
the log), so a bundle-ID tap that silently drops its IDs is visible before any audio is.

**The cross-check is the whole point.** An all-zero tap is indistinguishable from genuine
silence — unless you also know the OS thinks the target *is* producing output. Each tick logs
`targetOut=yes(pid …)` from `kAudioProcessPropertyIsRunningOutput`, and when buffers arrive
all-zero while a targeted process reports output, the log says `STALL … <<< THE SILENT
FAILURE`. That distinguishes it from `ioproc.starved`, which is the device having stopped
calling us at all — a different bug with the same symptom.

**Perturbations, so failure can be provoked rather than waited for:** the readout bar sets the
output device's `kAudioDevicePropertyNominalSampleRate` directly (44.1 ↔ 48 kHz), which is the
renegotiation ADR-0001 suspects behind the all-zero reports. `Recreate tap` throws away tap,
aggregate and IOProc and rebuilds them — the candidate recovery.

**Watchers:** a property listener on `kAudioTapPropertyFormat` (format changing under our
feet), a per-second diff of the HAL process table (`proc.added` / `proc.removed` /
`proc.output`), and the last buffer list's shape, so a channel-count change shows up even if
nothing fires a listener.

## Driving it

The scenario from the ticket is a checklist in the window. **Click each step the moment you
have done it** — it stamps a `MARK` into the log, and without those the log is an undated wall
of numbers.

Read the log afterwards; `grep -v proc.initial` first.

## Two facts that shape the run

- **Launch with `open`, never from a shell.** TCC attribution follows the responsible process,
  so a binary started from a terminal is attributed to the terminal and reads all-zero
  ([#6](https://github.com/SamWongML/macos-audio-recording/issues/6)).
- **Safari has no HAL client of its own.** The process table shows only
  `com.apple.WebKit.GPU`, shared between Safari, Xcode and QQ音乐 on this machine. So
  `bundleIDs: ["com.apple.Safari"]` has nothing to match, and `["com.apple.WebKit.GPU"]` would
  match all three. That is a question about `bundleIDs`, not a workaround to skip past.
