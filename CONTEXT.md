# macOS Audio Recording

A locally-run macOS utility that captures the audio of a single running application and lets you trim and export it.

## Language

**Source**:
The single running application whose audio is captured. Chosen once and remembered.
_Avoid_: Target, input, device, channel

**Recording**:
The audio captured in one continuous run from start to stop, saved automatically. An audio file the user places in the Library by hand is treated as a Recording too, since everything the app offers applies to it identically.
_Avoid_: Take, clip, session, capture

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

**Loudness**:
How loud a Recording sounds over time, measured to a modern standard rather than read off its peaks. Exporting can correct it to a fixed target, so Recordings captured from different Sources play back at the same level.
_Avoid_: Volume, level, amplitude, loudness units

**Gain**:
A level offset, in decibels, chosen by hand for one Recording. It applies on top of any Loudness correction and, like Trim, never alters the Recording itself.
_Avoid_: Volume, boost, makeup, adjustment
