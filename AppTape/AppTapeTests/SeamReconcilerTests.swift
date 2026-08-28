//
//  SeamReconcilerTests.swift
//  AppTapeTests
//

import Testing
@testable import AppTape

/// The writer reconciles host-time gaps into padded Seams: integer frames, cause `overrun` or
/// `rebuild`, trusting `mHostTime` only when valid, and a gap beyond 30 s ends the Recording
/// (ADR-0010).
struct SeamReconcilerTests {
    private let rate = 48_000.0
    private func seconds(ofFrames frames: Int) -> Double { Double(frames) / 48_000.0 }

    /// A contiguous stream: each chunk's host time advances by exactly its own duration. No Seams.
    @Test func aContiguousStreamPadsNothing() {
        var r = SeamReconciler(sampleRate: rate)
        let chunk = 512
        var host = 100.0   // arbitrary anchor
        for _ in 0..<50 {
            let d = r.account(hostTimeSeconds: host, hostTimeValid: true, newFrames: chunk, rebuildInFlight: false)
            #expect(d == .append)
            host += seconds(ofFrames: chunk)
        }
        #expect(r.seams.isEmpty)
        #expect(r.masterFrames == 512 * 50)
    }

    /// A dropped buffer opens a gap the wall clock accounts for but the master does not: it pads an
    /// `overrun` Seam (no rebuild was in flight).
    @Test func aDroppedBufferPadsAnOverrunSeam() {
        var r = SeamReconciler(sampleRate: rate)
        let chunk = 512
        var host = 0.0
        _ = r.account(hostTimeSeconds: host, hostTimeValid: true, newFrames: chunk, rebuildInFlight: false)
        host += seconds(ofFrames: chunk)
        // The next buffer was dropped by the ring: the following chunk arrives one buffer late.
        host += seconds(ofFrames: chunk)   // wall clock advanced by the lost buffer
        let d = r.account(hostTimeSeconds: host, hostTimeValid: true, newFrames: chunk, rebuildInFlight: false)
        #expect(d == .pad(frames: chunk, cause: .overrun))
        #expect(r.seams == [Seam(start: 512, frames: 512, cause: .overrun)])
        #expect(r.masterFrames == 512 + 512 + 512)   // first chunk + pad + late chunk
    }

    /// A rebuild's ~1 s host-time delta pads a `rebuild` Seam when a rebuild was in flight.
    @Test func aRebuildGapPadsARebuildSeam() {
        var r = SeamReconciler(sampleRate: rate)
        _ = r.account(hostTimeSeconds: 0, hostTimeValid: true, newFrames: 48_000, rebuildInFlight: false)
        // A rebuild took ~1 s; the next chunk's host time is ~2 s in (1 s of audio + 1 s gap).
        let d = r.account(hostTimeSeconds: 2.0, hostTimeValid: true, newFrames: 512, rebuildInFlight: true)
        #expect(d == .pad(frames: 48_000, cause: .rebuild))
        #expect(r.seams.count == 1)
        #expect(r.seams[0].cause == .rebuild)
        #expect(r.seams[0].start == 48_000)
        #expect(r.seams[0].frames == 48_000)
    }

    /// An untrusted timestamp cannot be reconciled: no Seam even when the host times imply a gap.
    @Test func anInvalidHostTimeIsNotReconciled() {
        var r = SeamReconciler(sampleRate: rate)
        _ = r.account(hostTimeSeconds: 0, hostTimeValid: true, newFrames: 512, rebuildInFlight: false)
        // Host time jumps a full second ahead, but the flag says it cannot be trusted.
        let d = r.account(hostTimeSeconds: 1.0, hostTimeValid: false, newFrames: 512, rebuildInFlight: false)
        #expect(d == .append)
        #expect(r.seams.isEmpty)
        #expect(r.masterFrames == 1024)
    }

    /// A gap beyond 30 s ends the Recording rather than padding ~12 GB of zeros — the sleep end
    /// arriving by another route (ADR-0010). The chunk is discarded; nothing is padded.
    @Test func aGapBeyondThirtySecondsEnds() {
        var r = SeamReconciler(sampleRate: rate)
        _ = r.account(hostTimeSeconds: 0, hostTimeValid: true, newFrames: 48_000, rebuildInFlight: false)
        let before = r.masterFrames
        // A 5-minute host-time jump (an overnight sleep would be far worse).
        let d = r.account(hostTimeSeconds: 300, hostTimeValid: true, newFrames: 512, rebuildInFlight: false)
        #expect(d == .end)
        #expect(r.seams.isEmpty)
        #expect(r.masterFrames == before)   // nothing padded, nothing appended
    }

    /// A gap just under 30 s is still padded, not ended — it is the backstop, not a load-bearing path.
    @Test func aGapJustUnderThirtySecondsPads() {
        var r = SeamReconciler(sampleRate: rate)
        _ = r.account(hostTimeSeconds: 0, hostTimeValid: true, newFrames: 48_000, rebuildInFlight: true)
        let d = r.account(hostTimeSeconds: 1 + 29, hostTimeValid: true, newFrames: 512, rebuildInFlight: true)
        if case .pad(let f, let cause) = d {
            #expect(cause == .rebuild)
            #expect(abs(f - 29 * 48_000) < 5)
        } else {
            Issue.record("expected a pad, got \(d)")
        }
    }

    /// Sub-frame host-time jitter must not manufacture a one-frame Seam on every chunk.
    @Test func subThresholdJitterPadsNothing() {
        var r = SeamReconciler(sampleRate: rate)
        let chunk = 512
        var host = 0.0
        for i in 0..<100 {
            // A few frames of wobble either way, always under `minSeamFrames`.
            let wobble = seconds(ofFrames: (i % 3) - 1)
            _ = r.account(hostTimeSeconds: host + wobble, hostTimeValid: true, newFrames: chunk, rebuildInFlight: false)
            host += seconds(ofFrames: chunk)
        }
        #expect(r.seams.isEmpty)
    }

    /// Two separate faults record two Seams, each starting at the right master frame.
    @Test func multipleSeamsCarryTheirOwnStarts() {
        var r = SeamReconciler(sampleRate: rate)
        var host = 0.0
        _ = r.account(hostTimeSeconds: host, hostTimeValid: true, newFrames: 48_000, rebuildInFlight: false)
        host += 1.0
        // First gap: 0.5 s overrun.
        host += 0.5
        _ = r.account(hostTimeSeconds: host, hostTimeValid: true, newFrames: 48_000, rebuildInFlight: false)
        host += 1.0
        // Second gap: 0.5 s rebuild.
        host += 0.5
        _ = r.account(hostTimeSeconds: host, hostTimeValid: true, newFrames: 512, rebuildInFlight: true)

        #expect(r.seams.count == 2)
        #expect(r.seams[0].cause == .overrun)
        #expect(r.seams[0].start == 48_000)
        #expect(r.seams[1].cause == .rebuild)
        // Second Seam begins after: chunk1 + gap1(0.5s) + chunk2.
        #expect(r.seams[1].start == 48_000 + 24_000 + 48_000)
    }
}
