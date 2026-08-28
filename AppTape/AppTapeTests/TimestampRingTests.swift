//
//  TimestampRingTests.swift
//  AppTapeTests
//

import Testing
@testable import AppTape

/// The host-time mark ring is a single-producer / single-consumer FIFO: marks come out in the order
/// they went in, peek does not consume, and a full ring drops rather than blocks (the writer has
/// stalled, which the sample ring is already dropping for).
struct TimestampRingTests {
    @Test func marksPopInOrder() {
        let ring = TimestampRing(capacity: 8)
        #expect(ring.push(ringFrame: 0, hostSeconds: 1.0, valid: true))
        #expect(ring.push(ringFrame: 512, hostSeconds: 1.01, valid: true))
        #expect(ring.pop() == .init(ringFrame: 0, hostSeconds: 1.0, valid: true))
        #expect(ring.pop() == .init(ringFrame: 512, hostSeconds: 1.01, valid: true))
        #expect(ring.pop() == nil)
    }

    @Test func peekDoesNotConsume() {
        let ring = TimestampRing(capacity: 8)
        ring.push(ringFrame: 100, hostSeconds: 2.0, valid: false)
        #expect(ring.peekFrame() == 100)
        #expect(ring.peekFrame() == 100)   // still there
        #expect(ring.pop()?.ringFrame == 100)
        #expect(ring.peekFrame() == nil)
    }

    @Test func aFullRingDropsTheNewMark() {
        let ring = TimestampRing(capacity: 2)
        #expect(ring.push(ringFrame: 0, hostSeconds: 0, valid: true))
        #expect(ring.push(ringFrame: 1, hostSeconds: 0, valid: true))
        #expect(ring.push(ringFrame: 2, hostSeconds: 0, valid: true) == false)   // full → dropped
        // Draining one makes room again.
        _ = ring.pop()
        #expect(ring.push(ringFrame: 3, hostSeconds: 0, valid: true))
    }

    @Test func invalidFlagRoundTrips() {
        let ring = TimestampRing(capacity: 4)
        ring.push(ringFrame: 7, hostSeconds: 9.5, valid: false)
        let mark = ring.pop()
        #expect(mark?.valid == false)
        #expect(mark?.hostSeconds == 9.5)
    }
}
