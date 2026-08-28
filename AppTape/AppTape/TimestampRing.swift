//
//  TimestampRing.swift
//  AppTape
//

import Synchronization

/// A lock-free single-producer / single-consumer ring of **host-time marks**, parallel to the
/// sample `AudioRingBuffer`. The realtime IOProc pushes one mark per delivered buffer — the buffer's
/// first-frame host time and the ring-frame position it lands at — and the non-realtime writer
/// thread pops them to learn where, in wall-clock time, each drained chunk sits (ADR-0010).
///
/// It carries the timestamps the sample ring cannot: a flat buffer of `Float` has no room for a
/// per-buffer `mHostTime`, and the writer needs exactly that to reconcile gaps into Seams. Same
/// index discipline as `AudioRingBuffer` — each side owns one monotonic index; the payload writes
/// happen-before the release of `written`, so a mark read with acquire ordering is fully published.
///
/// A mark is pushed **only when the sample write succeeded**, with `ringFrame` counting frames
/// actually written. So a dropped buffer pushes no mark and leaves a host-time jump the writer reads
/// as an overrun gap — the sample ring's drop and this ring's silence describe the same event.
final class TimestampRing: @unchecked Sendable {
    struct Mark: Equatable {
        /// Frames written to the sample ring **before** this buffer — the ring-frame position of the
        /// buffer's first frame, in the same counting as the writer's per-tap consumed-frame index.
        var ringFrame: Int
        /// Host time of the buffer's first frame, in seconds (a monotonic machine clock).
        var hostSeconds: Double
        /// Whether the timestamp carried `kAudioTimeStampHostTimeValid`.
        var valid: Bool
    }

    private let capacity: Int
    private var ringFrames: UnsafeMutableBufferPointer<Int>
    private var hostSeconds: UnsafeMutableBufferPointer<Double>
    private var valids: UnsafeMutableBufferPointer<Bool>

    private let written = Atomic<Int>(0)
    private let read = Atomic<Int>(0)

    init(capacity: Int = 2048) {
        precondition(capacity > 0)
        self.capacity = capacity
        ringFrames = .allocate(capacity: capacity); ringFrames.initialize(repeating: 0)
        hostSeconds = .allocate(capacity: capacity); hostSeconds.initialize(repeating: 0)
        valids = .allocate(capacity: capacity); valids.initialize(repeating: false)
    }

    deinit {
        ringFrames.deallocate(); hostSeconds.deallocate(); valids.deallocate()
    }

    /// Producer side, realtime-safe: record one mark, or drop it whole if the ring is full (a full
    /// mark ring means the writer has stalled — already an overrun the sample ring is dropping too).
    @discardableResult
    func push(ringFrame: Int, hostSeconds seconds: Double, valid: Bool) -> Bool {
        let writeCount = written.load(ordering: .relaxed)   // only this thread writes `written`
        let readCount = read.load(ordering: .acquiring)
        guard writeCount - readCount < capacity else { return false }
        let slot = writeCount % capacity
        ringFrames[slot] = ringFrame
        hostSeconds[slot] = seconds
        valids[slot] = valid
        written.store(writeCount + 1, ordering: .releasing)
        return true
    }

    /// Consumer side: the next unread mark's `ringFrame`, without consuming it, or nil when empty.
    /// Lets the writer stop popping once a mark lies past the position it is correlating.
    func peekFrame() -> Int? {
        let readCount = read.load(ordering: .relaxed)       // only this thread writes `read`
        let writeCount = written.load(ordering: .acquiring)
        guard writeCount - readCount > 0 else { return nil }
        return ringFrames[readCount % capacity]
    }

    /// Consumer side: pop the next mark, or nil when empty.
    func pop() -> Mark? {
        let readCount = read.load(ordering: .relaxed)
        let writeCount = written.load(ordering: .acquiring)
        guard writeCount - readCount > 0 else { return nil }
        let slot = readCount % capacity
        let mark = Mark(ringFrame: ringFrames[slot], hostSeconds: hostSeconds[slot], valid: valids[slot])
        read.store(readCount + 1, ordering: .releasing)
        return mark
    }
}
