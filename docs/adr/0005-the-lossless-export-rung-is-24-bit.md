---
status: accepted
---

# The lossless Export rung is 24-bit ALAC, and is not called Lossless

The top Quality Preset is **24-bit ALAC in `.m4a`**, presented as **Master quality**. It is deliberately not bit-exact against the Float32 master that [ADR-0003](0003-immutable-lossless-caf-master.md) writes, and it deliberately does not use the word *lossless*.

The reason is that on macOS 27 there is no lossless path for the master at all. Every Apple Lossless source-data flag in `CoreAudioBaseTypes.h:544` describes **signed integer** input — 16, 20, 24, or 32 bit — and no float variant exists. Apple's FLAC encoder fails the same test less honestly: handed Float32 input it emits `from 24-bit source` at a byte size **identical** to the explicitly-24-bit path (5,240,533 bytes for both, on a 30-second 48 kHz stereo probe), so it discards eight bits and reports nothing. Whatever this rung does, it converts.

Given that it must convert, the choice is only *how far*.

## Considered options

**ALAC from 32-bit integer** is the most faithful conversion available and was rejected on price. Measured on the same probe it produced 8,155,864 bytes against an 11,520,044-byte Float32 master: **71%, about 977 MB per hour.** That is close enough to the master's own footprint that the rung stops being an export and starts being an expensive copy, while still not being bit-exact.

**ALAC from 16-bit** is 21% of the master and genuinely cheap, but it is CD depth applied to material that may still be normalized and Gain-adjusted downstream, and it throws away headroom for a saving the AAC rungs already provide more of.

**FLAC** is a wash on size (5,240,533 against ALAC's 5,278,325, a 0.7% difference) and loses on container: `.m4a` opens in Music and QuickTime without a thought, and per `afconvert -hf` the `m4af` container does not accept Opus but does accept both `alac` and `flac`, so the container choice is free and the codec choice is Apple-native.

**Dropping the rung entirely** — "reveal the master in Finder" plus AAC 256 — was seriously considered and rejected because **the master is untrimmed**. A lossless-grade export of the *trimmed* range is the actual want, and Finder cannot produce one.

**Keeping the name "Lossless"** on a 24-bit rung was rejected outright. It would be a claim the file does not honour.

## Consequences

**24 bits is inaudible against this material.** ~144 dB of range, applied to post-mix consumer audio that has already been through a system mixer. The eight bits dropped are not reachable by any condition this app will meet.

**The rung costs 46% of the master, about 633 MB per hour.** That is the number any future disk-space or duration policy should use for Export, distinct from the master's own 1.4 GB/hour.

**The float→int24 conversion can clip, and this rung does not own the fix.** [ADR-0003](0003-immutable-lossless-caf-master.md) records that the tap hands us post-mix float which can exceed 0 dBFS. Rather than inventing a local scaling rule, this rung rides whatever the Export loudness contract settles, so that a single place decides what happens to signal above full scale.

**"Master quality" claims something true.** It names the quality of the thing that was captured, which is exactly what 24 bits delivers here, and it makes no assertion about bit-exactness.

Settled in issue #9.
