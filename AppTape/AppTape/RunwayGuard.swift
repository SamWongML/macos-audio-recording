//
//  RunwayGuard.swift
//  AppTape
//

import Foundation

/// The disk guard as a **Runway** clock (ADR-0009): a pure value reducer, off the realtime IOProc
/// and the writer thread, that turns a `statfs` free-space reading and the master's byte rate into
/// three advisory tiers measured in *time to a 2 GB floor* rather than in bytes.
///
/// The whole decision lives here so it can be tested without a disk, a clock, or a Recording. The
/// Capture Engine's coordinator polls free space every 5 s, folds each reading in, and acts on the
/// `Decision`: paint the menu bar amber, post the 30-minute warning once, or end at the floor. ENOSPC
/// — the guard firing late between polls — is the engine's own write failure and ends by the same
/// `.diskGuard` route, so ADR-0007's six ends stay six.
///
/// **Runway is `(free − 2 GB) ÷ rate`.** Dividing plain free space by the rate would measure time to
/// *zero* and overstate every tier by the floor's own ~87 minutes (ADR-0009); the floor is subtracted
/// first so the number is honestly "time until we stop." The rate is not a constant — 8 bytes/frame
/// at 48 kHz is 1.38 GB/hour against 1.27 at 44.1 — so it is an input, never baked in.
nonisolated struct RunwayGuard {
    /// The hard floor on the Library's volume. Plain available capacity, not
    /// `…ForImportantUsage` (ADR-0009). Decimal GB, matching how Finder reports free space and how
    /// the refusal names it, so "2 GB" on screen is the same 2 GB enforced here.
    static let floorBytes: Int64 = 2_000_000_000

    /// The menu bar turns amber at 3 hours of Runway — late enough that a healthy disk never shows
    /// it, since an advisory that is always on is decoration (ADR-0009).
    static let amberThreshold: TimeInterval = 3 * 60 * 60

    /// The 30-minute warning: enough time to delete something and keep recording, which is the only
    /// action the warning asks for (ADR-0009).
    static let warnThreshold: TimeInterval = 30 * 60

    /// A 15-minute Runway hysteresis band on both the tier and its notification, so a Recording
    /// hovering on a boundary does not flap the menu bar every 5 s or warn twice (ADR-0009).
    static let hysteresis: TimeInterval = 15 * 60

    /// A pre-tap estimate of the master's byte rate — 48 kHz stereo Float32 — used only for the
    /// start-amber decision, before a tap exists to report its real format. The first real poll a few
    /// seconds later corrects the tier with the true rate, so an off estimate costs nothing.
    static let nominalRatePerSecond: Double = 8 * 48_000

    /// Whether the menu bar item is drawn amber (ADR-0009). Colour is the sole signal at this tier —
    /// a conscious accessibility trade, since the 30-minute tier is text and reaches a colour-blind
    /// user intact.
    enum Tier: Sendable { case nominal, amber }

    /// What the coordinator should do after folding in one reading.
    struct Decision: Equatable {
        /// The menu bar tier, after hysteresis.
        var tier: Tier
        /// True on exactly the reading that first crosses into the 30-minute band — the one warning.
        /// Never true twice without a 45-minute recovery first, and never asks for a retraction.
        var shouldWarn: Bool
        /// True once free space is at or below the floor: end the Recording as `.diskGuard`.
        var shouldEnd: Bool
    }

    /// The start decision, a pure function of the same inputs (ADR-0009): refused below the floor,
    /// begun amber between the floor and the 3-hour tier, begun plain above it.
    enum StartDecision: Equatable { case allow, allowAmber, refuse }

    /// Runway in seconds: `(free − floor) ÷ rate`. Negative below the floor; `+∞` when the rate is
    /// unknown (no tap yet, or a zero-rate format), which reads as "no bound" so nothing fires early.
    static func runwaySeconds(freeBytes: Int64, ratePerSecond: Double) -> TimeInterval {
        guard ratePerSecond > 0 else { return .infinity }
        return Double(freeBytes - floorBytes) / ratePerSecond
    }

    /// The start policy. The refusal depends only on the floor; the amber split uses the Runway, so a
    /// Recording the guard would paint amber within seconds begins amber rather than flashing green
    /// first (ADR-0009).
    static func startDecision(freeBytes: Int64, ratePerSecond: Double) -> StartDecision {
        guard freeBytes > floorBytes else { return .refuse }
        return runwaySeconds(freeBytes: freeBytes, ratePerSecond: ratePerSecond) <= amberThreshold
            ? .allowAmber : .allow
    }

    /// The amber latch, held across readings so hysteresis has memory. Public read for a coordinator
    /// that wants to pre-seed it from a `.allowAmber` start.
    private(set) var tier: Tier = .nominal
    /// The warning one-shot: true once the 30-minute warning has fired, cleared only by a 45-minute
    /// recovery. A posted warning is never retracted, so this never drives an all-clear — only
    /// re-arms the single future warning (ADR-0009).
    private var warned = false

    init(tier: Tier = .nominal) { self.tier = tier }

    /// Fold in one free-space reading and decide. The tier moves to amber the moment Runway reaches
    /// 3 hours and back to nominal only once it recovers past 3h15m; the warning fires the moment
    /// Runway reaches 30 minutes and re-arms only past 45 minutes. End wins outright at the floor.
    mutating func receive(freeBytes: Int64, ratePerSecond: Double) -> Decision {
        // The floor: end outright. No warning on this reading — "will stop soon" chased by an
        // immediate stop is noise; the end's own notification is the telling.
        guard freeBytes > Self.floorBytes else {
            return Decision(tier: tier, shouldWarn: false, shouldEnd: true)
        }

        let runway = Self.runwaySeconds(freeBytes: freeBytes, ratePerSecond: ratePerSecond)

        // Amber tier, with the 15-minute band on the way back up.
        switch tier {
        case .nominal where runway <= Self.amberThreshold: tier = .amber
        case .amber where runway > Self.amberThreshold + Self.hysteresis: tier = .nominal
        default: break
        }

        // The one warning, with the same band on its re-arm. Recovery only re-arms; it never posts.
        var shouldWarn = false
        if !warned, runway <= Self.warnThreshold {
            warned = true
            shouldWarn = true
        } else if warned, runway > Self.warnThreshold + Self.hysteresis {
            warned = false
        }

        return Decision(tier: tier, shouldWarn: shouldWarn, shouldEnd: false)
    }
}
