//
//  CaptureEngine.swift
//  AppTape
//

import CoreAudio
import Foundation
import Synchronization

/// The result of a Recording that captured something. Nil is the arm-then-never-play case:
/// no first sound, no file, nothing to open (ADR-0016).
struct CaptureResult {
    let url: URL
    let frameCount: Int
    let sampleRate: Double
    var duration: TimeInterval { sampleRate > 0 ? Double(frameCount) / sampleRate : 0 }
}

/// Drives one Recording end to end: it owns the tap, a non-realtime writer thread, the
/// observation→decision reducer, and the lazily-created CAF master, and it holds off idle
/// system sleep for the Recording's lifetime (ADR-0014).
///
/// The division of labour is the whole point. The realtime IOProc (in `ProcessTap`) only
/// copies samples into the ring. This writer thread — deliberately *not* realtime, so it
/// does not join the audio workgroup (ADR-0003) — drains the ring, scans each chunk for its
/// first sound, asks the reducer what to do, and writes. The main thread only reads a
/// published frame count to drive the menu-bar timer. So the one place that touches the file
/// is a plain thread that may block, and the one place that must not block never does.
///
/// Once the master has begun, this thread also carries fault recovery (ADR-0007, ADR-0010): it
/// reconciles every host-time gap into a padded **Seam** via `SeamReconciler`, and it splits a
/// dead tap from a quiet Source via `FaultReducer` — a soft fault gets one rebuild that never ends
/// the Recording, a hard fault spends one of three attempts, and a rebuild destroys and recreates
/// the tap, re-resolving the Source's processes. All of it runs *after* the first sound; the
/// bring-up window (denial inference, head elision) is untouched.
final class CaptureEngine: @unchecked Sendable {
    let sampleRate: Double
    private let channels: Int
    private let format: AudioStreamBasicDescription
    private let sourceName: String
    private let startDate: Date

    /// The Source's HAL client objects, kept for the writer thread's
    /// `kAudioProcessPropertyIsRunningOutput` reads while the denial detector is armed, and as the
    /// fallback aim if a rebuild's re-resolution turns up nothing.
    private let processObjectIDs: [AudioObjectID]
    /// The bundle IDs those objects belong to, captured at start so a rebuild can re-resolve the
    /// Source's live processes even after it relaunched under new object IDs (ADR-0007).
    private let sourceBundleIDs: Set<String>

    /// The active tap. Swapped by the writer thread on a rebuild; touched by no other thread, so the
    /// swap needs no lock. The writer stops it on exit, so shutdown never races the swap.
    private var tap: ProcessTap
    private var writerThread: Thread?
    private let running = Atomic<Bool>(true)
    private let finished = DispatchSemaphore(value: 0)
    private var activityToken: (any NSObjectProtocol)?

    /// Invoked at most once, from the writer thread, when a denied grant is inferred (ADR-0008).
    /// Passed in at init so it is set before the writer thread starts (no cross-thread race) and
    /// never written again. It hops to the main actor and tears the engine down via `discard()`;
    /// it must not call back synchronously into the engine, which would deadlock the writer thread
    /// against its own `finished` wait.
    private let onDenialInferred: (@Sendable () -> Void)?

    /// Invoked at most once, from the writer thread, when the master file is created at the first
    /// sound — so the shell can learn which Library file is currently growing and refuse to export
    /// it (ADR-0012: the capturing Recording is not itself exportable). Best-effort like the denial
    /// hook; it hops to the main actor and must not call back synchronously into the engine.
    private let onMasterCreated: (@Sendable (URL) -> Void)?

    /// Invoked at most once, from the writer thread after the file is finalized, when the Recording
    /// **ended itself** — recovery exhausted, a format mismatch, or a >30 s gap (the sleep end by
    /// another route). One of the four unrequested ends (ADR-0010). Best-effort; it hops to the main
    /// actor, which then reclaims the finalized file via `stop()` and notifies. It must not call back
    /// synchronously into the engine.
    private let onEnded: (@Sendable (RecordingEndReason) -> Void)?

    /// Master frames committed so far, published by the writer thread for the main-thread
    /// timer. Sits at 0 through the armed window, so the timer reads `00:00` until the first
    /// sound (ADR-0016). Once begun it counts padded Seams too, so the timeline stays wall-clock true.
    private let publishedFrames = Atomic<Int>(0)
    var masterFrameCount: Int { publishedFrames.load(ordering: .acquiring) }
    var elapsed: TimeInterval { sampleRate > 0 ? Double(masterFrameCount) / sampleRate : 0 }

    // Writer-thread-only state. Reached by the main thread only after `finished` is signalled.
    private var reducer = CaptureReducer()
    private var writer: CAFMasterWriter?
    private var denial = DenialDetector()
    /// Reconciles host-time gaps into padded Seams; created once the format is known (ADR-0010).
    private var reconciler: SeamReconciler
    /// The soft/hard fault policy (ADR-0010).
    private var fault = FaultReducer()

    /// Frames drained from the **current** tap's ring, for correlating host-time marks. Reset to 0
    /// on every rebuild, because a new tap's ring numbering restarts at 0; the absolute host time in
    /// the marks carries the gap across the rebuild instead (ADR-0007).
    private var tapConsumedFrames = 0
    /// The most recent host-time mark not past the frame being written — the interpolation reference.
    private var refMark: TimestampRing.Mark?
    /// True from the start of a rebuild until the next chunk is accounted, so the gap it opened is
    /// tagged `rebuild` rather than `overrun`. The reconciler sees only the gap; this names its cause.
    private var pendingRebuildSeam = false

    /// Whether any callback has ever produced frames — the famine detector arms only after the first
    /// (ADR-0010: a detector armed at start reads the first-run TCC prompt as a fault).
    private var firstCallbackSeen = false
    /// Monotonic time of the last non-empty drain; a famine is no frames for 500 ms past it.
    private var lastProducedAt: TimeInterval = 0
    /// Whether the last drained chunk was wholly silent — fed to the soft detector.
    private var lastChunkAllZero = false
    /// Throttled cache of the Source's output state, refreshed ~10 Hz for the soft detector.
    private var cachedRunningOutput = false
    private var lastRunningOutputCheck: TimeInterval = 0

    /// Set by the writer thread when the Recording ends itself; read after `finished` to notify.
    private var selfEndReason: RecordingEndReason?

    /// A famine is 500 ms with no callback at all — ~47 missed 512-frame buffers in a row, which no
    /// healthy tap does under any load (ADR-0010).
    private static let famineWindow: TimeInterval = 0.5

    /// Arms capture: holds the idle-sleep token, creates and starts the tap (blocking, may
    /// raise the TCC prompt — call off the main thread), and spins up the writer thread. No
    /// file yet: the master is created lazily at the first sound.
    init(processObjectIDs: [AudioObjectID],
         sourceName: String,
         onDenialInferred: (@Sendable () -> Void)? = nil,
         onMasterCreated: (@Sendable (URL) -> Void)? = nil,
         onEnded: (@Sendable (RecordingEndReason) -> Void)? = nil) throws {
        self.sourceName = sourceName
        self.startDate = Date()
        self.processObjectIDs = processObjectIDs
        self.sourceBundleIDs = ProcessTap.bundleIDs(of: processObjectIDs)
        self.onDenialInferred = onDenialInferred
        self.onMasterCreated = onMasterCreated
        self.onEnded = onEnded

        // Hold off the involuntary idle-sleep timer for the whole Recording (ADR-0014). The
        // system may still sleep for lid close, the Apple menu, or low battery — each an
        // honest end — but not the idle timer the user did not choose in this moment.
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .idleSystemSleepDisabled, reason: "AppTape is recording")

        do {
            tap = try ProcessTap(processObjectIDs: processObjectIDs)
        } catch {
            if let activityToken { ProcessInfo.processInfo.endActivity(activityToken) }
            activityToken = nil
            throw error
        }
        format = tap.format
        sampleRate = tap.format.mSampleRate
        channels = max(1, Int(tap.format.mChannelsPerFrame))
        reconciler = SeamReconciler(sampleRate: sampleRate)

        let thread = Thread { [weak self] in self?.runWriterLoop() }
        thread.name = "com.apptape.master-writer"
        thread.stackSize = 512 * 1024
        writerThread = thread
        thread.start()
    }

    /// Stops the tap, lets the writer drain the tail and finalize the file, and returns what
    /// was saved — or nil if the Source never made a sound. A left-click on the status item
    /// lands here; the file it returns is already playable. Idempotent with a self-end: if the
    /// writer already finalized the file on a fault, this simply reclaims the result.
    @discardableResult
    func stop() -> CaptureResult? {
        shutdown()
        guard let writer, writer.framesWritten > 0 else { return nil }
        return CaptureResult(url: writer.url, frameCount: Int(writer.framesWritten), sampleRate: sampleRate)
    }

    /// The reason the Recording ended itself, if it did — read after `stop()`/`shutdown()`. Nil for a
    /// user stop or a still-open engine.
    var endReason: RecordingEndReason? { selfEndReason }

    /// Ends the Recording as an inferred denial (ADR-0008): tears the tap down and **removes**
    /// any file outright — `removeItem`, not `trashItem`, because a Recording that never held a
    /// non-zero sample is not a Recording and putting pure silence in the Trash asks the user a
    /// question about something they never made. Head elision (ADR-0016) means the master is not
    /// created until the first sound, so a denied Recording has produced no file to remove — this
    /// is the belt-and-braces that guarantees no all-zero file is ever left behind regardless.
    func discard() {
        shutdown()
        if let writer { try? FileManager.default.removeItem(at: writer.url) }
        writer = nil
    }

    /// Stops the writer, lets it drain the tail and finalize, and releases the sleep token. The
    /// writer owns the tap and stops it on exit, so this never races a rebuild's tap swap. Idempotent.
    private let didTeardown = Atomic<Bool>(false)
    private func shutdown() {
        let (exchanged, _) = didTeardown.compareExchange(
            expected: false, desired: true, ordering: .acquiringAndReleasing)
        guard exchanged else { return }

        running.store(false, ordering: .releasing)
        finished.wait()

        if let activityToken { ProcessInfo.processInfo.endActivity(activityToken) }
        activityToken = nil
    }

    // MARK: - Writer thread

    private func runWriterLoop() {
        // ~0.17 s of stereo per drain pass; small enough that the first written chunk carries
        // almost no leading silence, large enough to keep syscalls down.
        let scratchSamples = 16_384 * channels
        var scratch = [Float](repeating: 0, count: scratchSamples)

        var lastDenialCheck: TimeInterval = 0
        while running.load(ordering: .acquiring) {
            let produced = drainOnce(into: &scratch)
            let now = ProcessInfo.processInfo.systemUptime

            if produced == 0 {
                usleep(5_000)   // 5 ms nap when the ring is empty — this thread may block
            } else {
                firstCallbackSeen = true
                lastProducedAt = now
            }

            if !reducer.hasBegun {
                // Denial watch, active only through the arming window (before the first sound) and
                // fired at most once. Throttled off the 5 ms loop so the HAL property read is not
                // hammered; the 3 s threshold is coarse enough that ~10 Hz sampling is ample.
                if !denial.inferred, now - lastDenialCheck >= 0.1 {
                    lastDenialCheck = now
                    if denial.receive(hasBegun: false, isRunningOutput: anyRunningOutput(), now: now) {
                        onDenialInferred?()
                    }
                }
            } else {
                // Fault recovery, from the first sound on (ADR-0007/0010). The reconciler already ran
                // inside `drainOnce`; here we run the soft/hard split and any scheduled rebuild.
                //
                // ADR-0010 arms the famine detector "at the first callback" so the first-run TCC
                // prompt — which blocks *inside* tap creation, delivering no callbacks — is not read
                // as a fault. Gating on the first *sound* satisfies that rationale strictly more: a
                // famine cannot fire while no audio has been heard. The window between first callback
                // and first sound belongs to the denial detector and the cancel gesture (ADR-0008),
                // which own bring-up; a fault there is an arm-then-never-play that saves nothing, not
                // a mid-Recording fault the six ends are about.
                runFaultRecovery(produced: produced, now: now)
            }
        }
        // Tap is stopped here (not in shutdown), so it is only ever touched by this thread and the
        // swap on rebuild never races. Then the ring only shrinks: drain whatever remains.
        tap.stop()
        while drainOnce(into: &scratch) > 0 {}

        writer?.close()
        if let writer, !reconciler.seams.isEmpty {
            // The mark rides in an xattr, written once at finalize (ADR-0010). Best-effort like the
            // other metadata: a lost write reads back as a clean Recording.
            try? RecordingMetadata.writeSeams(reconciler.seams, to: writer.url)
        }
        finished.signal()
        if let reason = selfEndReason { onEnded?(reason) }
    }

    /// Drains one chunk, decides via the reducer, reconciles its host time, and writes. Returns
    /// samples drained.
    private func drainOnce(into scratch: inout [Float]) -> Int {
        let produced = scratch.withUnsafeMutableBufferPointer { tap.ring.read(into: $0) }
        guard produced > 0 else { return 0 }
        let frames = produced / channels
        let firstNonSilent = Self.firstNonSilentFrame(in: scratch, sampleCount: produced, channels: channels)
        lastChunkAllZero = firstNonSilent == nil

        switch reducer.receive(frameCount: frames, firstNonSilentFrame: firstNonSilent) {
        case .elide:
            break   // leading silence — write nothing, create no file
        case .begin(let skip):
            createWriterIfNeeded()
            accountAndWrite(&scratch, sampleCount: produced, skipFrames: skip, writtenFrames: frames - skip)
        case .append:
            accountAndWrite(&scratch, sampleCount: produced, skipFrames: 0, writtenFrames: frames)
        }
        tapConsumedFrames += frames
        publishedFrames.store(reconciler.masterFrames, ordering: .releasing)
        return produced
    }

    /// Reconcile a written chunk against the wall clock, padding a Seam before it if a gap opened,
    /// or ending the Recording if the gap is beyond 30 s (ADR-0010).
    private func accountAndWrite(_ scratch: inout [Float], sampleCount: Int, skipFrames: Int, writtenFrames: Int) {
        let firstTapFrame = tapConsumedFrames + skipFrames
        let (host, valid) = hostTime(forTapFrame: firstTapFrame)
        switch reconciler.account(hostTimeSeconds: host, hostTimeValid: valid,
                                  newFrames: writtenFrames, rebuildInFlight: pendingRebuildSeam) {
        case .append:
            writeChunk(&scratch, sampleCount: sampleCount, skipFrames: skipFrames)
        case .pad(let padFrames, _):
            writeSilence(frames: padFrames)
            writeChunk(&scratch, sampleCount: sampleCount, skipFrames: skipFrames)
        case .end:
            // A gap beyond 30 s: the sleep end arriving by another route, not a seventh end (ADR-0010).
            endSelf(.sleep)
            return
        }
        pendingRebuildSeam = false
    }

    /// The host time (seconds) of a given frame in the current tap's ring, interpolated from the
    /// most recent mark at or before it. Trusted only when the mark says so.
    private func hostTime(forTapFrame frame: Int) -> (seconds: Double, valid: Bool) {
        let marks = tap.timestampRing
        while let next = marks.peekFrame(), next <= frame {
            refMark = marks.pop()
        }
        guard let ref = refMark else { return (0, false) }
        return (ref.hostSeconds + Double(frame - ref.ringFrame) / sampleRate, ref.valid)
    }

    /// The soft/hard split, run once per loop pass after the master has begun.
    private func runFaultRecovery(produced: Int, now: TimeInterval) {
        guard selfEndReason == nil else { return }

        if produced > 0 {
            // A soft fault is all-zero-while-running; a non-zero chunk re-arms it and cancels any
            // pending hard rebuild (restore beating rebuild).
            handle(fault.observe(allZero: lastChunkAllZero,
                                 isRunningOutput: runningOutputThrottled(now: now), now: now))
        } else if firstCallbackSeen, now - lastProducedAt > Self.famineWindow {
            // Callbacks have stopped entirely — a famine, the unambiguous hard fault (ADR-0010).
            handle(fault.hardFault(now: now))
            lastProducedAt = now   // the backoff governs from here; do not re-fire every 5 ms
        }
        handle(fault.poll(now: now))
    }

    /// Apply one fault decision: rebuild the tap, or end the Recording.
    private func handle(_ action: FaultReducer.Action) {
        guard selfEndReason == nil else { return }
        switch action {
        case .none: break
        case .rebuild: rebuild()
        case .end(let reason): endSelf(reason)
        }
    }

    /// Destroy the tap and build a fresh one, re-resolving the Source's processes (ADR-0007). The
    /// host-time gap this opens is padded as a `rebuild` Seam by the reconciler. A rebuilt tap whose
    /// format does not match the master ends the Recording at once; a rebuild that cannot even be
    /// built is reported back as a hard fault, spending an attempt.
    private func rebuild() {
        pendingRebuildSeam = true
        tap.stop()

        let resolved = ProcessTap.resolveObjectIDs(matchingBundleIDs: sourceBundleIDs)
        let targets = resolved.isEmpty ? processObjectIDs : resolved
        guard let newTap = try? ProcessTap(processObjectIDs: targets) else {
            handle(fault.hardFault(now: ProcessInfo.processInfo.systemUptime))
            return
        }
        if !Self.formatsMatch(newTap.format, format) {
            newTap.stop()
            handle(fault.formatMismatch())
            return
        }
        tap = newTap
        // A new tap's ring numbering restarts at 0; the absolute host time carries the gap.
        tapConsumedFrames = 0
        refMark = nil
        lastProducedAt = ProcessInfo.processInfo.systemUptime
    }

    /// Record the end reason and ask the loop to wind down; the writer finalizes on the way out.
    private func endSelf(_ reason: RecordingEndReason) {
        guard selfEndReason == nil else { return }
        selfEndReason = reason
        running.store(false, ordering: .releasing)
    }

    /// Whether a rebuilt tap can continue the master: same rate, channels, and sample layout. A
    /// mismatch cannot be padded onto the master's ASBD (ADR-0007), so it ends the Recording.
    private static func formatsMatch(_ a: AudioStreamBasicDescription, _ b: AudioStreamBasicDescription) -> Bool {
        a.mSampleRate == b.mSampleRate
            && a.mChannelsPerFrame == b.mChannelsPerFrame
            && a.mBitsPerChannel == b.mBitsPerChannel
            && a.mFormatID == b.mFormatID
            && a.mFormatFlags == b.mFormatFlags
    }

    /// Lazily creates the CAF at the first sound, in place at its final Library path.
    private func createWriterIfNeeded() {
        guard writer == nil else { return }
        try? FileManager.default.createDirectory(at: LibraryLocation.directory,
                                                 withIntermediateDirectories: true)
        let name = LibraryLocation.uniqueFileName(source: sourceName, date: startDate) {
            FileManager.default.fileExists(atPath: LibraryLocation.directory.appendingPathComponent($0).path)
        }
        let url = LibraryLocation.directory.appendingPathComponent(name)
        writer = try? CAFMasterWriter(url: url, asbd: format, sourceName: sourceName)
        if writer != nil { onMasterCreated?(url) }
    }

    private func writeChunk(_ scratch: inout [Float], sampleCount: Int, skipFrames: Int) {
        let start = skipFrames * channels
        guard start < sampleCount else { return }
        scratch.withUnsafeBufferPointer { ptr in
            let slice = UnsafeBufferPointer(rebasing: ptr[start..<sampleCount])
            try? writer?.write(slice)
        }
    }

    /// Pad `frames` of silence into the master — a Seam. Written in blocks so a 30 s gap does not
    /// need a 30 s buffer. Seams are rare, so the per-Seam allocation is not a hot path.
    private func writeSilence(frames: Int) {
        guard frames > 0, let writer else { return }
        let blockFrames = 16_384
        var zeros = [Float](repeating: 0, count: blockFrames * channels)
        var remaining = frames
        while remaining > 0 {
            let n = min(remaining, blockFrames)
            zeros.withUnsafeBufferPointer { ptr in
                try? writer.write(UnsafeBufferPointer(rebasing: ptr[0..<(n * channels)]))
            }
            remaining -= n
        }
    }

    /// The Source's output state, cached and refreshed ~10 Hz so the HAL read is not hammered on the
    /// 5 ms loop — 10 Hz resolution over the soft detector's 10 s window is ample.
    private func runningOutputThrottled(now: TimeInterval) -> Bool {
        if now - lastRunningOutputCheck >= 0.1 {
            lastRunningOutputCheck = now
            cachedRunningOutput = anyRunningOutput()
        }
        return cachedRunningOutput
    }

    /// Whether any of the Source's HAL clients reports output right now — the discriminator the
    /// denial inference and the soft fault both turn on (ADR-0008/0010). A plain property read, done
    /// on this non-realtime thread, never in the IOProc.
    private func anyRunningOutput() -> Bool {
        for object in processObjectIDs {
            if (CAProperty.uint32(of: object, kAudioProcessPropertyIsRunningOutput) ?? 0) != 0 {
                return true
            }
        }
        return false
    }

    /// The first frame carrying any non-zero sample, or nil if the chunk is wholly silent.
    /// This is the "first sound" detection that head elision turns on — done here, on the
    /// non-realtime thread, never in the IOProc.
    private static func firstNonSilentFrame(in buffer: [Float], sampleCount: Int, channels: Int) -> Int? {
        var i = 0
        while i < sampleCount {
            if buffer[i] != 0 { return i / channels }
            i += 1
        }
        return nil
    }
}
