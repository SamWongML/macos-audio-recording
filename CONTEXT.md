# AppTape

AppTape records the audio of one running application and lets the user trim and export it.
This glossary names the concepts used across capture, the Library and Export.

## Language

**Source**:
The single running application whose audio is captured. Chosen once and remembered.

**Recording**:
The audio captured in one continuous run and saved automatically, beginning at the Source's first
sound; if the Source never makes a sound, nothing is saved. A file placed in the Library by hand is
adopted as a Recording and behaves identically.

**Dropout**:
A stretch of silence inside a Recording standing in for audio that never arrived, because capture was interrupted or a buffer was lost under load. It keeps the Recording true against the clock, so everything after it still sits where it was heard.

**Library**:
The folder of Recordings the app lists — an ordinary visible folder, so the user can rearrange it in Finder and the app follows.

**Trim**:
The start and end points selecting which part of a Recording is Exported. Choosing them never alters the Recording.

**Trimmed-away**:
The part of a Recording outside its Trim. Still audio and still shown, quieter than the kept part rather than removed from the picture.

**Export**:
Producing a finished audio file from a Recording at a chosen Quality Preset.

**Quality Preset**:
A named audio-quality setting offered at Export. It determines the file's size, which is only ever estimated, never promised.

**Runway**:
How much longer a Recording could keep capturing before the disk runs short. Always a length of time, never free bytes.

**Loudness**:
How loud a Recording sounds over time, measured to BS.1770 rather than read off its peaks. Export can correct it to a fixed target.

**Gain**:
A manual decibel offset for one Recording, applied on top of any Loudness correction. Like Trim, it never alters the Recording.

**Ceiling**:
The highest true peak an Export lets the audio reach while correcting Loudness.

**Amplification cap**:
The largest boost a Loudness correction will apply, so a very quiet, noisy Recording is left below target rather than having its noise floor lifted into audibility.
