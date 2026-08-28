//
//  RecordingEndReason.swift
//  AppTape
//

import Foundation

/// A Recording ends for **exactly six reasons** and no more (ADR-0007). Everything else is a Seam
/// to pad or an event to ignore. The six split in two: *you asked for it* — a user stop, an app
/// quit or logout — and *you didn't* — the disk guard, rebuilding exhausted, a format mismatch, or
/// sleep. The four unrequested ends each post a notification naming their reason, because they ask
/// different things of the user and a generic "Recording stopped" makes them open the app to find
/// out which (ADR-0010).
nonisolated enum RecordingEndReason: Equatable, Sendable, CaseIterable {
    /// The user pressed stop.
    case userStopped
    /// The disk guard fired — the Runway ran out (issue #17, ADR-0009).
    case diskGuard
    /// Three rebuild attempts were spent and the tap still faults (ADR-0007).
    case recoveryExhausted
    /// A rebuilt tap's format did not match the master's ASBD, so the timeline cannot continue
    /// (ADR-0007). Not a retry — it ends at once without spending an attempt.
    case formatMismatch
    /// System sleep, or fast user switching folded into it (ADR-0007). Caught on notification while
    /// still awake, so there is no gap to reconcile and the master ends at its last real sample.
    case sleep
    /// App quit or logout. Stops and saves unwarned, as ADR-0004 already accepts for a left-click.
    case quit

    /// The four ends the user did not choose. Only these notify (ADR-0010).
    var isUnrequested: Bool {
        switch self {
        case .userStopped, .quit: return false
        case .diskGuard, .recoveryExhausted, .formatMismatch, .sleep: return true
        }
    }

    /// The notification title. Constant across the four — the *body* names the reason, so the title
    /// stays a plain, calm "Recording stopped."
    var notificationTitle: String { "Recording stopped" }

    /// The body names the reason and, where there is one, the action: free up space, or nothing.
    /// Nil for the two requested ends, which never notify.
    var notificationBody: String? {
        switch self {
        case .userStopped, .quit:
            return nil
        case .diskGuard:
            return "Your disk is almost full, so recording stopped. Free up space to record again."
        case .recoveryExhausted:
            return "Audio capture couldn’t recover and recording stopped. Try recording again."
        case .formatMismatch:
            return "The audio format changed while recording, so recording stopped."
        case .sleep:
            return "Your Mac went to sleep, so recording stopped."
        }
    }
}
