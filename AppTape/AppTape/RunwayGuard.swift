import Foundation

/// The disk guard as a Runway clock: a pure value reducer, off the realtime IOProc and the
/// writer thread, that turns a `statfs` free-space reading and the master's byte rate into three
/// advisory tiers measured in *time to a 2 GB floor* rather than in bytes.
nonisolated struct RunwayGuard {
    /// The hard floor on the Library's volume.
    static let floorBytes: Int64 = 2_000_000_000

    /// The menu bar turns amber at 3 hours of Runway — late enough that a healthy disk never shows
    /// it, since an advisory that is always on is decoration.
    static let amberThreshold: TimeInterval = 3 * 60 * 60

    /// The 30-minute warning: enough time to delete something and keep recording, which is the only
    /// action the warning asks for.
    static let warnThreshold: TimeInterval = 30 * 60

    /// A 15-minute Runway hysteresis band on both the tier and its notification, so a Recording
    /// hovering on a boundary does not flap the menu bar every 5 s or warn twice.
    static let hysteresis: TimeInterval = 15 * 60

    /// A pre-tap estimate of the master's byte rate — 48 kHz stereo Float32 — used only for the
    /// start-amber decision, before a tap exists to report its real format.
    static let nominalRatePerSecond: Double = 8 * 48_000

    /// Whether the menu bar item is drawn amber.
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

    /// The start decision, a pure function of the same inputs: refused below the floor,
    /// begun amber between the floor and the 3-hour tier, begun plain above it.
    enum StartDecision: Equatable { case allow, allowAmber, refuse }

    /// Runway in seconds: `(free − floor) ÷ rate`. Negative below the floor; `+∞` when the rate is
    /// unknown (no tap yet, or a zero-rate format), which reads as "no bound" so nothing fires early.
    static func runwaySeconds(freeBytes: Int64, ratePerSecond: Double) -> TimeInterval {
        guard ratePerSecond > 0 else { return .infinity }
        return Double(freeBytes - floorBytes) / ratePerSecond
    }

    /// The start policy.
    static func startDecision(freeBytes: Int64, ratePerSecond: Double) -> StartDecision {
        guard freeBytes > floorBytes else { return .refuse }
        return runwaySeconds(freeBytes: freeBytes, ratePerSecond: ratePerSecond) <= amberThreshold
            ? .allowAmber : .allow
    }

    /// The amber latch, held across readings so hysteresis has memory. Public read for a coordinator
    /// that wants to pre-seed it from a `.allowAmber` start.
    private(set) var tier: Tier = .nominal
    /// The warning one-shot: true once the 30-minute warning has fired, cleared only by a 45-minute
    /// recovery.
    private var warned = false

    init(tier: Tier = .nominal) { self.tier = tier }

    /// Fold in one free-space reading and decide.
    mutating func receive(freeBytes: Int64, ratePerSecond: Double) -> Decision {
        // The floor: end outright.
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
