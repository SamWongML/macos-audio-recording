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
final class CaptureEngine: @unchecked Sendable {
    let sampleRate: Double
    private let channels: Int
    private let format: AudioStreamBasicDescription
    private let sourceName: String
    private let startDate: Date

    /// The Source's HAL client objects, kept for the writer thread's
    /// `kAudioProcessPropertyIsRunningOutput` reads while the denial detector is armed.
    private let processObjectIDs: [AudioObjectID]

    private let tap: ProcessTap
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

    /// Master frames committed so far, published by the writer thread for the main-thread
    /// timer. Sits at 0 through the armed window, so the timer reads `00:00` until the first
    /// sound (ADR-0016).
    private let publishedFrames = Atomic<Int>(0)
    var masterFrameCount: Int { publishedFrames.load(ordering: .acquiring) }
    var elapsed: TimeInterval { sampleRate > 0 ? Double(masterFrameCount) / sampleRate : 0 }

    // Writer-thread-only state. Reached by the main thread only after `finished` is signalled.
    private var reducer = CaptureReducer()
    private var writer: CAFMasterWriter?
    private var denial = DenialDetector()

    /// Arms capture: holds the idle-sleep token, creates and starts the tap (blocking, may
    /// raise the TCC prompt — call off the main thread), and spins up the writer thread. No
    /// file yet: the master is created lazily at the first sound.
    init(processObjectIDs: [AudioObjectID],
         sourceName: String,
         onDenialInferred: (@Sendable () -> Void)? = nil,
         onMasterCreated: (@Sendable (URL) -> Void)? = nil) throws {
        self.sourceName = sourceName
        self.startDate = Date()
        self.processObjectIDs = processObjectIDs
        self.onDenialInferred = onDenialInferred
        self.onMasterCreated = onMasterCreated

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

        let thread = Thread { [weak self] in self?.runWriterLoop() }
        thread.name = "com.apptape.master-writer"
        thread.stackSize = 512 * 1024
        writerThread = thread
        thread.start()
    }

    /// Stops the tap, lets the writer drain the tail and finalize the file, and returns what
    /// was saved — or nil if the Source never made a sound. A left-click on the status item
    /// lands here; the file it returns is already playable.
    @discardableResult
    func stop() -> CaptureResult? {
        shutdown()
        guard let writer, writer.framesWritten > 0 else { return nil }
        return CaptureResult(url: writer.url, frameCount: Int(writer.framesWritten), sampleRate: sampleRate)
    }

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

    /// Stops the tap, lets the writer drain the tail and finalize, and releases the sleep token.
    /// Idempotent enough for either exit: `stop()` keeps the file, `discard()` removes it.
    private func shutdown() {
        // Stop the tap first, so no new frames arrive while the writer drains the tail.
        tap.stop()
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
            if drainOnce(into: &scratch) == 0 {
                usleep(5_000)   // 5 ms nap when the ring is empty — this thread may block
            }
            // Denial watch, active only through the arming window (before the first sound) and
            // fired at most once. Throttled off the 5 ms loop so the HAL property read is not
            // hammered; the 3 s threshold is coarse enough that ~10 Hz sampling is ample.
            if !reducer.hasBegun && !denial.inferred {
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastDenialCheck >= 0.1 {
                    lastDenialCheck = now
                    if denial.receive(hasBegun: false, isRunningOutput: anyRunningOutput(), now: now) {
                        onDenialInferred?()
                    }
                }
            }
        }
        // Tap is stopped by now, so the ring only shrinks: drain whatever remains.
        while drainOnce(into: &scratch) > 0 {}

        writer?.close()
        finished.signal()
    }

    /// Drains one chunk, decides via the reducer, and writes. Returns samples drained.
    private func drainOnce(into scratch: inout [Float]) -> Int {
        let produced = scratch.withUnsafeMutableBufferPointer { tap.ring.read(into: $0) }
        guard produced > 0 else { return 0 }
        let frames = produced / channels
        let firstNonSilent = Self.firstNonSilentFrame(in: scratch, sampleCount: produced, channels: channels)

        switch reducer.receive(frameCount: frames, firstNonSilentFrame: firstNonSilent) {
        case .elide:
            break   // leading silence — write nothing, create no file
        case .begin(let skip):
            createWriterIfNeeded()
            writeChunk(&scratch, sampleCount: produced, skipFrames: skip)
        case .append:
            writeChunk(&scratch, sampleCount: produced, skipFrames: 0)
        }
        publishedFrames.store(reducer.masterFrames, ordering: .releasing)
        return produced
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

    /// Whether any of the Source's HAL clients reports output right now — the discriminator the
    /// denial inference turns on (ADR-0008). A plain property read, done on this non-realtime
    /// thread, never in the IOProc.
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
