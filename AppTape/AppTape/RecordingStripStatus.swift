import Foundation

/// What the recording strip says, as one value. A running capture comes first; then whatever stops
/// the remembered Source being recorded, which is what disables Record; then the last refused press,
/// which pressing Record again retries.
enum RecordingStripStatus: Equatable {
    /// Nothing has been chosen to record.
    case unchosen
    /// The remembered Source is not running.
    case notRunning(SourceChoice)
    /// The remembered Source is running but has opened no audio yet.
    case noAudioYet(Source)
    /// The last press was refused below the disk floor.
    case refusedForSpace(DiskGuardBlocker)
    /// The last press inferred a denied System Audio Recording grant.
    case permissionDenied
    /// Record will capture this Source.
    case ready(Source)
    /// Armed: the Recording begins at the Source's first sound.
    case waitingForAudio
    /// Capturing since the first sound, inside the amber Runway tier when `lowRunway`.
    case recording(lowRunway: Bool)

    init(run: CaptureRun, readiness: SourceReadiness) {
        if run.isRecording {
            self = run.hasFirstSound ? .recording(lowRunway: run.runwayTier == .amber) : .waitingForAudio
            return
        }
        switch readiness {
        case .unchosen: self = .unchosen
        case .notRunning(let choice): self = .notRunning(choice)
        case .noAudioYet(let source): self = .noAudioYet(source)
        case .ready(let source):
            if let blocker = run.startBlocker {
                self = .refusedForSpace(blocker)
            } else if run.permissionRecovery {
                self = .permissionDenied
            } else {
                self = .ready(source)
            }
        }
    }

    /// Whether the strip's Record can be pressed: at rest with a recordable Source, including a
    /// retry after a refusal.
    var canRecord: Bool {
        switch self {
        case .ready, .refusedForSpace, .permissionDenied: true
        case .unchosen, .notRunning, .noAudioYet, .waitingForAudio, .recording: false
        }
    }

    /// What VoiceOver says when the strip changes to this, or nil for a change it leaves unspoken.
    var announcement: String? {
        switch self {
        case .waitingForAudio: "Waiting for audio"
        case .recording(let lowRunway): lowRunway ? "Recording. Disk space running low" : "Recording"
        case .refusedForSpace(let blocker): blocker.title
        case .permissionDenied: PermissionRecovery.title
        case .unchosen, .notRunning, .noAudioYet, .ready: nil
        }
    }
}
