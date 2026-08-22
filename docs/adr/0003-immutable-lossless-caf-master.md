---
status: accepted
---

# Every Recording is an immutable lossless CAF master, trimmed non-destructively

A Recording is captured to a **CAF file holding the tap's native Float32 PCM, written once and never modified**. Trim is not an edit of that file: it is a start point and an end point stored against the Recording, applied when Exporting. Export always reads the trimmed frame range from the master and re-encodes to the chosen Quality Preset; it is never a byte-copy. The file is written with the raw `AudioFile` API from a dedicated writer thread fed by a lock-free ring buffer, because the tap is read on a realtime IOProc that cannot do file I/O.

## Considered options

**Capturing to AAC directly** would cost about 58 MB/hour instead of 1.4 GB/hour, which is a real difference. It was rejected because every Export would then be a lossy-to-lossy transcode of already-lossy audio, and because it puts an encoder on the capture path. **Int16 CAF** halves the size honestly, but adds a convert-and-dither step and a clipping risk, since the tap hands us post-mix float that can exceed 0 dBFS. **ALAC in CAF** is lossless at roughly half of Int16, but its variable-size packets require a `pakt` chunk finalised at close, which destroys the crash property below. ALAC and AAC remain perfectly good *Export* presets; they are just wrong for capture.

**Destructive Trim** — rewriting or truncating the file — was rejected for a reason beyond undo. An append-only writer is what makes the crash story cheap; a file that is also mutated after the fact needs a far more careful durability argument for no user-visible gain.

The write API was chosen by elimination. **`AVAudioFile`** is the pleasant Swift-native option but does not expose `kAudioFilePropertyDeferSizeUpdates`, so it cannot deliver the crash guarantee. **`ExtAudioFile`** can reach the underlying `AudioFileID` through the read-only `kExtAudioFileProperty_AudioFile` (`ExtendedAudioFile.h:182`), but its reason to exist is a client-to-file format converter and we do no conversion. **`AudioFileInitializeWithCallbacks`** would let us own the file descriptor, which is the only way to `fcntl` it — see the durability limit below. **Raw `AudioFile`** won: `AudioFileWritePackets` documents that "for all uncompressed formats, packets == frames" (`AudioFile.h:901`), so appending is just advancing `inStartingPacket`, and `inUseCache: false` keeps a write-once file from evicting the page cache.

## Consequences

**Disk cost is the headline.** 48 kHz stereo Float32 is 384 KB/s, about **1.4 GB per hour**. This is the input to any future decision about maximum Recording length or low-disk warnings.

**Crash safety is app-crash only, deliberately.** CAF is the one container designed for this: `CAFFile.h:127` states that a negative `mChunkSize` means the chunk runs to the end of the file, expressly so that "if the program were to crash during recording then the file is still well defined." Combined with `kAudioFilePropertyDeferSizeUpdates` (which defaults to 1, "less safe since, if the application crashes before the size is updated, the file may not be readable" — `AudioFile.h:1109`), a crashed Recording opens as a normal Recording, complete to within a few seconds, with no repair step. **Power loss and kernel panics are not covered.** Buying that would need periodic `F_FULLFSYNC` (`fcntl.h:260`) or `F_BARRIERFSYNC` (`fcntl.h:307`), which requires the file descriptor, which forces the callbacks-based write path. Judged not worth it for a local utility.

**The IOProc can drop samples, and must say so.** No ring buffer is large enough to be a guarantee, and a realtime thread may not block, so on overrun the IOProc drops and increments a counter rather than overwriting. A counted gap is diagnosable; a silently mangled file is not. The buffer is sized at roughly ten seconds (~3.8 MB) so that a disk stall or an indexing storm cannot reach that path in practice. Note that `kAudioDevicePropertyIOThreadOSWorkgroup` exists but is not used: the writer thread is intentionally *not* realtime, so it does not join the audio workgroup.

**The tap is always requested as a stereo mixdown.** A Source-scoped recorder should capture the application's audio, not the shape of whatever output device happens to be attached, so a 6-channel device must not silently yield 6-channel Recordings. `CATapDescription`'s mixdown initialisers duplicate mono sources across both channels, which wastes disk on genuinely mono material — accepted. Note that those initialisers do **not** document their resulting format, so sample rate and channel count are read from `kAudioTapPropertyFormat` at creation and written into the CAF's ASBD; they are never assumed to be 48 kHz stereo.

Settled in issue #5.
