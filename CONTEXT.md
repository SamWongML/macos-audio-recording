# macOS Audio Recording

A locally-run macOS utility that captures the audio of a single running application and lets you trim and export it.

## Language

**Source**:
The single running application whose audio is captured. Chosen once and remembered.
_Avoid_: Target, input, device, channel

**Recording**:
The audio captured in one continuous run from start to stop, saved automatically. Its content begins at the first sound the Source produces, not at the moment recording was started, so silence before playback is never part of it — and if the Source never makes a sound, no Recording is saved. An audio file the user places in the Library by hand is adopted as a Recording too and behaves identically — listed, played, Trimmed, Exported — except that which Quality Presets are available depends on the file's own format, since the app never resamples or downmixes audio it did not capture.
_Avoid_: Take, clip, session, capture

**Seam**:
A stretch of silence inside a Recording standing in for audio that never reached it — because capture was interrupted and rebuilt, or because a moment's audio was dropped under load. It keeps the Recording's place against the clock, so everything after it still sits where it was heard, and a Recording that has one says so.
_Avoid_: Gap, glitch, dropout, discontinuity

**Library**:
The folder of Recordings the app lists. It is an ordinary visible folder rather than a private store, so the user can rearrange it in Finder and the app follows.
_Avoid_: Archive, history, gallery

**Trim**:
The start and end points that select which part of a Recording is Exported. Choosing them never alters the Recording, so a Trim can be widened, narrowed, or undone at any time.
_Avoid_: Cut, crop, edit, splice

**Export**:
Producing a finished audio file from a Recording at a chosen Quality Preset.
_Avoid_: Save, render, bounce, share

**Quality Preset**:
A named audio-quality setting offered at Export. The quality it names is what determines how large the exported file will be, so choosing a Quality Preset is how the size is chosen — but that size is only ever estimated, never promised.
_Avoid_: Profile, format, bitrate setting

**Runway**:
How much longer a Recording could keep capturing before the disk runs short and the app stops it. Always spoken as a length of time, never as free bytes, because the time is what the user can act on.
_Avoid_: Headroom (that means dB below the ceiling), free space, disk space, capacity

**Loudness**:
How loud a Recording sounds over time, measured to a modern standard rather than read off its peaks. Exporting can correct it to a fixed target, so Recordings captured from different Sources play back at the same level.
_Avoid_: Volume, level, amplitude, loudness units

**Gain**:
A level offset, in decibels, chosen by hand for one Recording. It applies on top of any Loudness correction and, like Trim, never alters the Recording itself.
_Avoid_: Volume, boost, makeup, adjustment
