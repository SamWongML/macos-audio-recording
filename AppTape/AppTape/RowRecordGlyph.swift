//
//  RowRecordGlyph.swift
//  AppTape
//

import Foundation

/// The record glyph a Source row shows, as a pure function of the recording state (issue #59).
/// The row *is* the record control (issue #6, ADR-0011): no button chrome, just this glyph in a
/// reserved trailing lane the waveform insets around. `circle` at rest; a `record.circle.fill`
/// that pulses once the row is the one recording.
///
/// The one subtlety the seam captures is bring-up: the pulsing "in-flight" glyph appears only
/// once bring-up has run past ~500 ms with no first sound, so a snappy start goes straight from
/// `circle` to a recording glyph and never flashes a distinct in-flight state. (A first-ever
/// Recording can block ~90 s behind the TCC prompt, ADR-0008 — there the in-flight glyph is the
/// only sign the press was heard.)
enum RowRecordGlyph {
    enum State: Equatable {
        /// Not this row's Recording: a plain `circle`, no pulse.
        case idle
        /// Pressed, but bring-up is still under the ~500 ms grace and no sound has arrived. Hold
        /// the `circle` so a fast start never flashes an in-flight glyph before its first sound.
        case armed
        /// Bring-up has run past ~500 ms with no first sound yet: the pulsing `record.circle.fill`.
        case inFlight
        /// The first sound has been heard: the pulsing `record.circle.fill`, over a live meter.
        case recording
    }

    /// The grace before a still-building Recording shows its in-flight glyph.
    static let inFlightThreshold: TimeInterval = 0.5

    /// `isRecordingTarget` is whether this row is the Source being recorded; `sincePress` is the
    /// seconds since the record press (nil when this row is not the target); `hasFirstSound` is
    /// whether the master has begun (the first sound heard, ADR-0016).
    static func state(isRecordingTarget: Bool, sincePress: TimeInterval?, hasFirstSound: Bool) -> State {
        guard isRecordingTarget else { return .idle }
        if hasFirstSound { return .recording }
        guard let sincePress, sincePress >= inFlightThreshold else { return .armed }
        return .inFlight
    }

    /// The SF Symbol name for a state: `record.circle.fill` once in-flight or recording, else
    /// the plain `circle` (idle, and the pre-500 ms armed grace).
    static func symbolName(_ state: State) -> String {
        switch state {
        case .idle, .armed: return "circle"
        case .inFlight, .recording: return "record.circle.fill"
        }
    }

    /// Whether the glyph pulses — the in-flight and recording states, subject to Reduce Motion
    /// at the view.
    static func pulses(_ state: State) -> Bool {
        state == .inFlight || state == .recording
    }
}
