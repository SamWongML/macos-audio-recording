//
//  RunwayGuardTests.swift
//  AppTapeTests
//

import Testing
import Foundation
@testable import AppTape

/// The disk guard's Runway math (ADR-0009), tested as a pure function with no disk and no clock:
/// the `(free − 2 GB) ÷ rate` formula, the 3-hour amber tier and 30-minute warning, the 15-minute
/// hysteresis that stops flapping and double-warning, the end at the floor, and the start policy
/// (refuse below the floor, begin amber up to the 3-hour tier).
struct RunwayGuardTests {
    /// 48 kHz stereo Float32 → 8 bytes/frame → 384,000 B/s. The ADR's worked rate.
    static let rate: Double = 8 * 48_000
    static let floor = RunwayGuard.floorBytes

    /// Free bytes that put Runway exactly `seconds` from the floor at `rate`.
    static func freeBytes(runway seconds: TimeInterval, rate: Double = rate) -> Int64 {
        floor + Int64(seconds * rate)
    }

    // MARK: - The formula

    @Test func runwaySubtractsTheFloorBeforeDividingByRate() {
        // 4 GB free above a 2 GB floor is 2 GB of Runway; at 384 KB/s that is ~5461 s, not the
        // ~15,625 s that dividing plain free space by the rate would claim.
        let runway = RunwayGuard.runwaySeconds(freeBytes: Self.floor + 2_000_000_000, ratePerSecond: Self.rate)
        #expect(abs(runway - 2_000_000_000 / Self.rate) < 1)
    }

    @Test func belowTheFloorRunwayIsNegative() {
        #expect(RunwayGuard.runwaySeconds(freeBytes: Self.floor - 1, ratePerSecond: Self.rate) < 0)
    }

    @Test func anUnknownRateIsUnboundedRunway() {
        // No tap yet / zero-rate format: infinite Runway, so nothing fires before a real reading.
        #expect(RunwayGuard.runwaySeconds(freeBytes: 0, ratePerSecond: 0) == .infinity)
    }

    // MARK: - Tiers

    @Test func staysNominalAboveThreeHoursAndTurnsAmberAtIt() {
        var g = RunwayGuard()
        // Just over 3 h: nominal.
        #expect(g.receive(freeBytes: Self.freeBytes(runway: 3 * 3600 + 60), ratePerSecond: Self.rate).tier == .nominal)
        // At 3 h: amber.
        #expect(g.receive(freeBytes: Self.freeBytes(runway: 3 * 3600), ratePerSecond: Self.rate).tier == .amber)
    }

    @Test func amberHoldsThroughTheHysteresisBandAndRecoversAboveIt() {
        var g = RunwayGuard()
        // Drop to amber.
        #expect(g.receive(freeBytes: Self.freeBytes(runway: 2 * 3600), ratePerSecond: Self.rate).tier == .amber)
        // Recover to just inside the 15-min band above 3 h — still amber, no flapping.
        #expect(g.receive(freeBytes: Self.freeBytes(runway: 3 * 3600 + 14 * 60), ratePerSecond: Self.rate).tier == .amber)
        // Past 3h15m: back to nominal, silently.
        #expect(g.receive(freeBytes: Self.freeBytes(runway: 3 * 3600 + 16 * 60), ratePerSecond: Self.rate).tier == .nominal)
    }

    // MARK: - The warning

    @Test func theWarningFiresOnceOnCrossingIntoThirtyMinutes() {
        var g = RunwayGuard()
        // Amber but above 30 min: no warning.
        #expect(g.receive(freeBytes: Self.freeBytes(runway: 40 * 60), ratePerSecond: Self.rate).shouldWarn == false)
        // Crossing 30 min: the one warning.
        #expect(g.receive(freeBytes: Self.freeBytes(runway: 30 * 60), ratePerSecond: Self.rate).shouldWarn == true)
        // Still low: never a second warning.
        #expect(g.receive(freeBytes: Self.freeBytes(runway: 20 * 60), ratePerSecond: Self.rate).shouldWarn == false)
        #expect(g.receive(freeBytes: Self.freeBytes(runway: 10 * 60), ratePerSecond: Self.rate).shouldWarn == false)
    }

    @Test func theWarningReArmsOnlyAfterRecoveringPastFortyFiveMinutes() {
        var g = RunwayGuard()
        #expect(g.receive(freeBytes: Self.freeBytes(runway: 30 * 60), ratePerSecond: Self.rate).shouldWarn == true)
        // Recover to inside the band (30 + 15 = 45 min): does not re-arm, so dropping again is silent.
        #expect(g.receive(freeBytes: Self.freeBytes(runway: 44 * 60), ratePerSecond: Self.rate).shouldWarn == false)
        #expect(g.receive(freeBytes: Self.freeBytes(runway: 25 * 60), ratePerSecond: Self.rate).shouldWarn == false)
        // Recover past 45 min: re-armed. A fresh drop warns again.
        #expect(g.receive(freeBytes: Self.freeBytes(runway: 46 * 60), ratePerSecond: Self.rate).shouldWarn == false)
        #expect(g.receive(freeBytes: Self.freeBytes(runway: 29 * 60), ratePerSecond: Self.rate).shouldWarn == true)
    }

    @Test func recoveryNeverPostsAnAllClear() {
        // A recovered reading returns shouldWarn false and moves the tier back silently — a posted
        // warning is never retracted (ADR-0009).
        var g = RunwayGuard()
        _ = g.receive(freeBytes: Self.freeBytes(runway: 20 * 60), ratePerSecond: Self.rate)
        let recovered = g.receive(freeBytes: Self.freeBytes(runway: 4 * 3600), ratePerSecond: Self.rate)
        #expect(recovered.shouldWarn == false)
        #expect(recovered.tier == .nominal)
    }

    // MARK: - The end

    @Test func endsAtTheFloor() {
        var g = RunwayGuard()
        #expect(g.receive(freeBytes: Self.floor, ratePerSecond: Self.rate).shouldEnd == true)
        #expect(g.receive(freeBytes: Self.floor - 500, ratePerSecond: Self.rate).shouldEnd == true)
        #expect(g.receive(freeBytes: Self.floor + 1, ratePerSecond: Self.rate).shouldEnd == false)
    }

    @Test func theEndReadingDoesNotAlsoWarn() {
        // Free space plummeting straight past 30 min to the floor between polls ends without a
        // pointless "will stop soon" first.
        var g = RunwayGuard()
        let d = g.receive(freeBytes: Self.floor - 1, ratePerSecond: Self.rate)
        #expect(d.shouldEnd == true)
        #expect(d.shouldWarn == false)
    }

    // MARK: - The start policy

    @Test func startIsRefusedAtOrBelowTheFloor() {
        #expect(RunwayGuard.startDecision(freeBytes: Self.floor, ratePerSecond: Self.rate) == .refuse)
        #expect(RunwayGuard.startDecision(freeBytes: Self.floor - 1, ratePerSecond: Self.rate) == .refuse)
    }

    @Test func startIsAmberBetweenTheFloorAndThreeHours() {
        #expect(RunwayGuard.startDecision(freeBytes: Self.freeBytes(runway: 60), ratePerSecond: Self.rate) == .allowAmber)
        #expect(RunwayGuard.startDecision(freeBytes: Self.freeBytes(runway: 3 * 3600), ratePerSecond: Self.rate) == .allowAmber)
    }

    @Test func startIsPlainAboveThreeHours() {
        #expect(RunwayGuard.startDecision(freeBytes: Self.freeBytes(runway: 5 * 3600), ratePerSecond: Self.rate) == .allow)
    }

    // MARK: - The refusal copy

    @Test func refusalCopyNamesTheFreeSpaceAndTheFloor() {
        // Assert against the formatter's own output rather than a literal "1.8 GB", since the
        // separator between number and unit is locale/OS-dependent.
        let refusal = DiskGuardRefusal(freeBytes: 1_800_000_000)
        #expect(refusal.message.contains(DiskGuardRefusal.formatted(1_800_000_000)))
        #expect(refusal.message.contains(DiskGuardRefusal.formatted(RunwayGuard.floorBytes)))
        #expect(refusal.message.contains("press record again"))
    }
}
