#if DEBUG

    import AVFoundation
    import Foundation

    /// What the previews are made of, and nothing else: this whole file is `#if DEBUG`, so none of it
    /// ships.

    /// The second conformance of `CaptureState`, and the reason that protocol exists: the capture states
    /// the running app can only reach through Core Audio, a live tap, and a Source making noise on cue.
    struct PreviewCapture: CaptureState {
        /// The file being written, if any. `isCapturing` is `url` equality, exactly as the run's is.
        var capturingURL: URL?
        var elapsed: TimeInterval = 0
        var masterByteCount: Int64?

        func isCapturing(_ recording: Recording) -> Bool { capturingURL == recording.url }

        /// Nothing is being captured: every Recording in the Library is settled, and the editor states
        /// the figures it read at adoption.
        static let settled = PreviewCapture()

        /// This Recording is the master being written right now — the state is about: a live
        /// clock, a growing figure, no waveform and no Play.
        static func capturing(
            _ recording: Recording,
            elapsed: TimeInterval = 93,
            bytes: Int64 = 44_640_000
        ) -> PreviewCapture {
            PreviewCapture(capturingURL: recording.url, elapsed: elapsed, masterByteCount: bytes)
        }

        /// Capture is armed but the Source has made no sound, so there is no file yet — the
        /// window where the clock reads `00:00` and the `Master` row is an em dash.
        static let armed = PreviewCapture()
    }

    /// A Recording with no file behind it, and the same fixture the suite uses — one definition, so a
    /// preview and a test cannot disagree about what an ordinary Recording looks like.
    extension Recording {
        /// Stands for *unstated* in `stub(byteCount:)`, so `nil` there can mean what it means on a real
        /// file — the length could not be read — rather than "give me the default".
        static let lengthFromFrameCount: Int64 = -1

        static func stub(
            _ name: String = "Google Chrome 2026-09-13 at 21.51.03",
            seconds: Double = 90,
            sampleRate: Double = 48_000,
            storedSource: String? = "Google Chrome",
            recordedAt: Date? = nil,
            byteCount: Int64? = Recording.lengthFromFrameCount,
            identity: FileIdentity? = nil,
            storedTrim: Trim? = nil,
            gain: Double = 0,
            dropouts: [Dropout] = [],
            isOpenable: Bool = true,
            in directory: URL = URL(filePath: "/Library")
        ) -> Recording {
            let frameCount = AVAudioFramePosition((seconds * sampleRate).rounded())
            return Recording(
                url: directory.appendingPathComponent("\(name).caf"),
                frameCount: frameCount,
                sampleRate: sampleRate,
                isOpenable: isOpenable,
                // Unstated means the master's own 8 bytes a frame: interleaved stereo
                // Float32.
                openedByteCount: byteCount == Recording.lengthFromFrameCount
                    ? frameCount * 8 : byteCount,
                fileIdentity: identity,
                storedSource: storedSource,
                recordedAt: recordedAt,
                storedTrim: storedTrim,
                gain: gain,
                dropouts: dropouts)
        }
    }

    extension Envelope {
        /// A drawable envelope with no audio behind it: speech-shaped, so the lane has phrases and gaps
        /// rather than a slab, and `complete` so the lane draws it as a finished scan rather than a
        /// partial one.
        static func preview(seconds: Double = 90, sampleRate: Double = 48_000) -> Envelope {
            let framesPerBucket = 256
            let buckets = Int(seconds * sampleRate) / framesPerBucket
            var peaks = [Float]()
            peaks.reserveCapacity(buckets)
            for i in 0..<buckets {
                let t = Double(i) / Double(buckets)
                // Four phrases with quiet between them, riding a slow swell.
                let phrase = max(0, sin(t * .pi * 8))
                let syllable = 0.55 + 0.45 * abs(sin(t * .pi * 220))
                let swell = 0.45 + 0.55 * sin(t * .pi)
                peaks.append(Float(phrase * syllable * swell * 0.92))
            }
            return Envelope(
                framesPerBucket: framesPerBucket,
                sampleRate: sampleRate,
                mins: peaks.map { -$0 },
                maxs: peaks,
                rms: peaks.map { $0 * 0.62 },
                complete: true)
        }
    }

    /// A Library that is not a folder: the Recordings a preview was handed, answered from memory.
    struct PreviewLibraryReader: RecordingReading {
        var recordings: [Recording]

        func audioFiles(in directory: URL) -> [URL] { recordings.map(\.url) }
        func adopt(_ url: URL) -> Recording? { recordings.first { $0.url == url } }
        func byteCount(of url: URL) -> Int64? { adopt(url)?.openedByteCount }
        func identity(of url: URL) -> FileIdentity? { adopt(url)?.fileIdentity }
    }

    extension EditorModel {
        /// The editor over a Library that does not exist, with Export objects nothing else is watching
        /// and a defaults suite of its own, so a preview can never write the user's sticky Quality
        /// Preset.
        static func preview() -> EditorModel { preview(recordings: Recording.previewLibrary()) }

        static func preview(recordings: [Recording]) -> EditorModel {
            let model = EditorModel(
                store: LibraryStore(
                    directory: URL(filePath: "/PreviewLibrary"),
                    reader: PreviewLibraryReader(recordings: recordings)),
                player: AudioPlayer(),
                correction: LoudnessCorrectionModel(),
                coordinator: ExportCoordinator(),
                preference: ExportPreference(
                    defaults: UserDefaults(suiteName: "com.apptape.previews")
                        ?? .standard))
            model.activate()
            return model
        }
    }

    extension Recording {
        /// A few days of Recordings from a handful of Sources, newest last so the store's own sort has
        /// something to do.
        static func previewLibrary() -> [Recording] {
            let sources = ["Google Chrome", "Music", "Zoom", "Podcasts"]
            let day: TimeInterval = 86_400
            let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
            return (0..<12).map { i in
                let source = sources[i % sources.count]
                return .stub(
                    "\(source) 2026-09-\(10 + i / 4) at 21.\(10 + i).03",
                    seconds: Double(30 + i * 37),
                    storedSource: source,
                    recordedAt: base.addingTimeInterval(Double(i / 4) * day + Double(i) * 900))
            }
        }
    }

#endif
