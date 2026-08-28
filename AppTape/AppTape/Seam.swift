//
//  Seam.swift
//  AppTape
//

import Foundation

/// A stretch of silence padded into the master to stand in for audio that never reached it —
/// because a buffer was dropped under load (`overrun`) or capture was interrupted and rebuilt
/// (`rebuild`). It keeps the Recording wall-clock true so every Trim point set after it still
/// lands where the audio was heard (ADR-0007, ADR-0010).
///
/// `start` and `frames` are **master frames** — integers, so no `NaN` can ever reach the file
/// (issue #7 found one doing exactly that). `cause` is one of exactly two values, because every
/// other event either ends the Recording or does not seam.
nonisolated struct Seam: Equatable, Sendable {
    nonisolated enum Cause: String, Sendable, CaseIterable {
        /// A dropped buffer: the realtime ring overran and the writer padded the hole (ADR-0010).
        case overrun
        /// The tap died and was rebuilt: the host-time delta across the fault, padded (ADR-0007).
        case rebuild
    }

    /// The master frame at which the Seam begins.
    var start: Int
    /// The Seam's length in master frames.
    var frames: Int
    var cause: Cause

    func seconds(sampleRate: Double) -> Double { sampleRate > 0 ? Double(frames) / sampleRate : 0 }
    func startSeconds(sampleRate: Double) -> Double { sampleRate > 0 ? Double(start) / sampleRate : 0 }
}

/// When a Recording's Seams are worth telling the user about. Every Seam is recorded; only ones a
/// listener would notice are surfaced — a badge on something inaudible teaches the user to ignore
/// it, which costs exactly the case it exists for (ADR-0010).
enum SeamSurfacing {
    /// A single Seam of 250 ms, **or a total of** 250 ms. The single rule catches one long gap; the
    /// total catches fifty scattered micro-gaps that add up to real damage. It sits cleanly between
    /// the two populations — a dropped buffer is ~10.67 ms and a rebuild Seam is ≥ 1 s by
    /// construction (ADR-0010).
    static let thresholdSeconds: Double = 0.250

    static func totalFrames(_ seams: [Seam]) -> Int { seams.reduce(0) { $0 + $1.frames } }

    static func totalSeconds(_ seams: [Seam], sampleRate: Double) -> Double {
        sampleRate > 0 ? Double(totalFrames(seams)) / sampleRate : 0
    }

    /// Whether the Recording should carry the mark: any single Seam ≥ 250 ms, or the total ≥ 250 ms.
    static func isSurfaced(_ seams: [Seam], sampleRate: Double) -> Bool {
        guard sampleRate > 0, !seams.isEmpty else { return false }
        let threshold = thresholdSeconds * sampleRate
        if seams.contains(where: { Double($0.frames) >= threshold }) { return true }
        return Double(totalFrames(seams)) >= threshold
    }

    /// Seams big enough to draw as a band in the lane — individually at or over the threshold. A
    /// rebuild Seam (≥ 1 s) always qualifies; a dropped-buffer Seam (~11 ms) never does, so it is
    /// summarised in one editor line rather than littering the lane (ADR-0010).
    static func laneVisible(_ seams: [Seam], sampleRate: Double) -> [Seam] {
        guard sampleRate > 0 else { return [] }
        let threshold = thresholdSeconds * sampleRate
        return seams.filter { Double($0.frames) >= threshold }
    }

    /// The rest — recorded but too small to draw, and gathered into the editor's one-line summary.
    static func subThreshold(_ seams: [Seam], sampleRate: Double) -> [Seam] {
        guard sampleRate > 0 else { return seams }
        let threshold = thresholdSeconds * sampleRate
        return seams.filter { Double($0.frames) < threshold }
    }
}
