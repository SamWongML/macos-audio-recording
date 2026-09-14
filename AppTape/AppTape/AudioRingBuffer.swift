import Synchronization

/// A lock-free single-producer / single-consumer ring of `Float` samples: the realtime
/// IOProc writes, the non-realtime writer thread reads. It is the reason the IOProc never
/// blocks — the tap thread copies its buffer in and returns, and a stalled disk
/// can never reach into the audio callback.
nonisolated final class AudioRingBuffer: @unchecked Sendable {
    private let storage: UnsafeMutableBufferPointer<Float>
    private let capacity: Int

    /// Total samples ever written / read. The difference is what is available; each is
    /// written by exactly one thread.
    private let written = Atomic<Int>(0)
    private let read = Atomic<Int>(0)
    /// Samples the producer had to drop on overrun. Only the producer writes it.
    private let dropped = Atomic<Int>(0)

    init(capacitySamples: Int) {
        precondition(capacitySamples > 0)
        capacity = capacitySamples
        storage = UnsafeMutableBufferPointer<Float>.allocate(capacity: capacitySamples)
        storage.initialize(repeating: 0)
    }

    deinit {
        storage.deinitialize()
        storage.deallocate()
    }

    /// Samples dropped so far (a torn read here costs one stale diagnostic number, never
    /// data), and its frame count for a given channel layout.
    var droppedSamples: Int { dropped.load(ordering: .relaxed) }
    func droppedFrames(channels: Int) -> Int { channels > 0 ? droppedSamples / channels : 0 }

    /// Total samples ever written. Read by the **producer** (the IOProc) to stamp each host-time
    /// mark with the ring-frame position its buffer lands at — the producer owns this counter, so
    /// its own read is exact, not a race.
    var writtenSamples: Int { written.load(ordering: .relaxed) }

    /// Producer side, realtime-safe: copy a whole block in, or drop it whole. Returns
    /// `false` when the block did not fit (and was dropped). No allocation, no locks.
    @discardableResult
    func write(_ samples: UnsafeBufferPointer<Float>) -> Bool {
        let count = samples.count
        guard count > 0 else { return true }
        let writeCount = written.load(ordering: .relaxed)   // only this thread writes `written`
        let readCount = read.load(ordering: .acquiring)
        let free = capacity - (writeCount - readCount)
        guard count <= free else {
            dropped.wrappingAdd(count, ordering: .relaxed)
            return false
        }
        let start = writeCount % capacity
        let firstChunk = min(count, capacity - start)
        storage.baseAddress!.advanced(by: start).update(from: samples.baseAddress!, count: firstChunk)
        if firstChunk < count {
            storage.baseAddress!.update(from: samples.baseAddress!.advanced(by: firstChunk),
                                        count: count - firstChunk)
        }
        written.store(writeCount + count, ordering: .releasing)
        return true
    }

    /// Consumer side: copy up to `destination.count` available samples out, and report how
    /// many. Zero means the ring is currently empty.
    func read(into destination: UnsafeMutableBufferPointer<Float>) -> Int {
        let readCount = read.load(ordering: .relaxed)       // only this thread writes `read`
        let writeCount = written.load(ordering: .acquiring)
        let available = writeCount - readCount
        let count = min(available, destination.count)
        guard count > 0 else { return 0 }
        let start = readCount % capacity
        let firstChunk = min(count, capacity - start)
        destination.baseAddress!.update(from: storage.baseAddress!.advanced(by: start), count: firstChunk)
        if firstChunk < count {
            destination.baseAddress!.advanced(by: firstChunk)
                .update(from: storage.baseAddress!, count: count - firstChunk)
        }
        read.store(readCount + count, ordering: .releasing)
        return count
    }
}
