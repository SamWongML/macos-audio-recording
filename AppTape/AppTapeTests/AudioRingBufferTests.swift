//
//  AudioRingBufferTests.swift
//  AppTapeTests
//

import Testing
@testable import AppTape

/// The ring is the seam between the realtime IOProc and the writer thread: it must round-
/// trip samples exactly, wrap correctly, and drop-with-a-count rather than overwrite on
/// overrun (ADR-0003).
struct AudioRingBufferTests {
    private func write(_ ring: AudioRingBuffer, _ samples: [Float]) -> Bool {
        samples.withUnsafeBufferPointer { ring.write($0) }
    }

    private func read(_ ring: AudioRingBuffer, max: Int) -> [Float] {
        var out = [Float](repeating: .nan, count: max)
        let n = out.withUnsafeMutableBufferPointer { ring.read(into: $0) }
        return Array(out.prefix(n))
    }

    @Test func roundTripsSamplesInOrder() {
        let ring = AudioRingBuffer(capacitySamples: 16)
        #expect(write(ring, [1, 2, 3, 4]))
        #expect(read(ring, max: 10) == [1, 2, 3, 4])
    }

    @Test func readOnEmptyReturnsNothing() {
        let ring = AudioRingBuffer(capacitySamples: 16)
        #expect(read(ring, max: 10).isEmpty)
    }

    @Test func partialReadLeavesTheRest() {
        let ring = AudioRingBuffer(capacitySamples: 16)
        #expect(write(ring, [1, 2, 3, 4, 5]))
        #expect(read(ring, max: 2) == [1, 2])
        #expect(read(ring, max: 10) == [3, 4, 5])
    }

    @Test func wrapsAroundTheEndOfStorage() {
        let ring = AudioRingBuffer(capacitySamples: 8)
        #expect(write(ring, [1, 2, 3, 4, 5, 6]))
        #expect(read(ring, max: 6) == [1, 2, 3, 4, 5, 6])   // read pointer now at 6
        // This write straddles the physical end (slots 6,7 then wraps to 0,1).
        #expect(write(ring, [7, 8, 9, 10]))
        #expect(read(ring, max: 10) == [7, 8, 9, 10])
    }

    @Test func overrunDropsTheWholeBlockAndCountsIt() {
        let ring = AudioRingBuffer(capacitySamples: 8)
        #expect(write(ring, [1, 2, 3, 4, 5, 6]))   // 6 of 8 used, 2 free
        // A 4-sample block does not fit in 2 free slots: dropped whole, nothing overwritten.
        #expect(write(ring, [7, 8, 9, 10]) == false)
        #expect(ring.droppedSamples == 4)
        #expect(ring.droppedFrames(channels: 2) == 2)
        // The original data is intact — the drop did not corrupt the ring.
        #expect(read(ring, max: 10) == [1, 2, 3, 4, 5, 6])
    }

    @Test func recoversAfterAConsumerDrainsSpace() {
        let ring = AudioRingBuffer(capacitySamples: 8)
        #expect(write(ring, [1, 2, 3, 4, 5, 6]))
        #expect(write(ring, [7, 8, 9]) == false)   // dropped
        _ = read(ring, max: 6)                       // drain, freeing space
        #expect(write(ring, [7, 8, 9]))              // now fits
        #expect(read(ring, max: 10) == [7, 8, 9])
    }

    @Test func survivesManyWrapCycles() {
        let ring = AudioRingBuffer(capacitySamples: 64)
        var expected: Float = 0
        for _ in 0..<1000 {
            let block = (0..<16).map { _ -> Float in expected += 1; return expected }
            #expect(write(ring, block))
            #expect(read(ring, max: 16) == block)
        }
        #expect(ring.droppedSamples == 0)
    }
}
