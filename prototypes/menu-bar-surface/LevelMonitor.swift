//  PROTOTYPE — throwaway. Real per-Source amplitude, by installing an actual Core Audio
//  process tap on each app that is currently playing.
//
//  This is the expensive answer to "show a real waveform in the row". It costs the TCC
//  grant: `AudioDeviceStart` is where macOS prompts for System Audio Recording, so this
//  variant asks for permission *before* the user has asked to record anything. That is a
//  real product question, not just an implementation detail — see the README.

import CoreAudio
import Foundation
import Observation
import Synchronization

// MARK: - Ring of recent amplitudes

/// A fixed-size ring the realtime IOProc writes and the UI reads without locking.
///
/// Deliberately racy: a torn read costs one wrong pixel in a waveform, and taking a lock
/// on a realtime audio thread costs a dropout. For a prototype that trade is obvious;
/// production would use a proper single-producer/single-consumer ring.
final class LevelRing: @unchecked Sendable {
    static let capacity = 220

    private let storage = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
    private let cursor = Atomic<Int>(0)

    init() { storage.initialize(repeating: 0, count: Self.capacity) }
    deinit { storage.deallocate() }

    /// Called on the realtime thread. No allocation, no locks, no Swift runtime calls.
    func append(_ value: Float) {
        let index = cursor.wrappingAdd(1, ordering: .relaxed).newValue
        storage[index % Self.capacity] = value
    }

    /// Oldest-to-newest snapshot, for drawing.
    func snapshot() -> [Float] {
        let end = cursor.load(ordering: .relaxed)
        return (0..<Self.capacity).map { storage[(end + $0 + 1) % Self.capacity] }
    }
}

// MARK: - Core Audio plumbing

private func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector,
                               mScope: kAudioObjectPropertyScopeGlobal,
                               mElement: kAudioObjectPropertyElementMain)
}

private func defaultOutputDeviceUID() -> String? {
    var a = address(kAudioHardwarePropertyDefaultOutputDevice)
    var device = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    guard withUnsafeMutablePointer(to: &device, {
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, $0)
    }) == noErr else { return nil }

    var uidAddress = address(kAudioDevicePropertyDeviceUID)
    var uid: CFString?
    var uidSize = UInt32(MemoryLayout<CFString?>.size)
    guard withUnsafeMutablePointer(to: &uid, {
        AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &uidSize, $0)
    }) == noErr, let uid else { return nil }
    return uid as String
}

private func tapUID(_ tap: AudioObjectID) -> String? {
    var a = address(kAudioTapPropertyUID)
    var uid: CFString?
    var size = UInt32(MemoryLayout<CFString?>.size)
    guard withUnsafeMutablePointer(to: &uid, {
        AudioObjectGetPropertyData(tap, &a, 0, nil, &size, $0)
    }) == noErr, let uid else { return nil }
    return uid as String
}

private func tapFormat(_ tap: AudioObjectID) -> AudioStreamBasicDescription? {
    var a = address(kAudioTapPropertyFormat)
    var asbd = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    guard withUnsafeMutablePointer(to: &asbd, {
        AudioObjectGetPropertyData(tap, &a, 0, nil, &size, $0)
    }) == noErr else { return nil }
    return asbd
}

// MARK: - One tap per playing Source

/// Owns a tap + private aggregate device + IOProc for a single Source, and fills a ring
/// with the peak amplitude of every buffer that comes through.
final class SourceTap {
    let ring = LevelRing()
    private var tap = AudioObjectID(0)
    private var aggregate = AudioObjectID(0)
    private var ioProc: AudioDeviceIOProcID?
    private(set) var failure: String?

    /// Builds and starts the tap. Blocking, and the *first* call is where macOS puts up
    /// the System Audio Recording prompt — so never call this on the main thread.
    init(processes: [AudioObjectID], name: String, global: Bool = false) {
        let description = global
            ? CATapDescription(stereoGlobalTapButExcludeProcesses: [])
            : CATapDescription(stereoMixdownOfProcesses: processes)
        description.name = "AppTape Level Probe — \(name)"
        description.uuid = UUID()
        // Never mute the app we are listening to, and keep the tap out of every other
        // process's device list.
        description.muteBehavior = CATapMuteBehavior.unmuted
        description.isPrivate = true

        guard AudioHardwareCreateProcessTap(description, &tap) == noErr, tap != 0 else {
            failure = "tap creation failed"; return
        }
        guard let uid = tapUID(tap), let output = defaultOutputDeviceUID() else {
            failure = "no tap/output UID"; return
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AppTape Probe \(name)",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: output,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: uid]
            ],
        ]
        guard AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate) == noErr,
              aggregate != 0 else {
            failure = "aggregate creation failed"; return
        }

        let channels = Int(tapFormat(tap)?.mChannelsPerFrame ?? 2)
        let ring = self.ring
        let status = AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, nil) {
            _, inputData, _, _, _ in
            // Realtime context. Peak of the interleaved-or-not Float32 buffers.
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            var peak: Float = 0
            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                let samples = data.assumingMemoryBound(to: Float.self)
                for index in stride(from: 0, to: count, by: max(1, channels)) {
                    peak = max(peak, abs(samples[index]))
                }
            }
            ring.append(min(peak, 1))
        }
        guard status == noErr, let ioProc else { failure = "IOProc creation failed"; return }

        // The permission gate, and the call observed to hang in issue #11.
        let start = AudioDeviceStart(aggregate, ioProc)
        if start != noErr {
            failure = start == kAudioDevicePermissionsError ? "permission denied" : "start failed (\(start))"
        }
    }

    func stop() {
        if let ioProc { AudioDeviceStop(aggregate, ioProc); AudioDeviceDestroyIOProcID(aggregate, ioProc) }
        if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate) }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap) }
        ioProc = nil; aggregate = 0; tap = 0
    }

    deinit { stop() }
}

/// Keeps exactly one `SourceTap` alive per currently-playing Source.
@MainActor
@Observable
final class LevelMonitor {
    static let shared = LevelMonitor()

    private var taps: [String: SourceTap] = [:]
    private var starting: Set<String> = []
    /// Bundle IDs whose tap failed, so a hard failure is not retried every half second.
    private(set) var failures: [String: String] = [:]

    /// True once any tap has produced a working stream — i.e. the grant exists.
    var isMonitoring: Bool { !taps.isEmpty }

    /// Set the first time any tap delivers a non-zero sample.
    private(set) var hasSeenSignal = false
    private var firstStart: Date?

    /// There is no API to query the System Audio Recording permission (see issue #3), and
    /// an ungranted tap returns silence rather than an error — so "several seconds of
    /// taps running, every sample zero" is the only signal that the grant is missing.
    /// It is a heuristic, and it is indistinguishable from genuinely silent playback.
    var looksUnpermitted: Bool {
        guard let firstStart, !hasSeenSignal, !taps.isEmpty else { return false }
        return Date().timeIntervalSince(firstStart) > 4
    }

    private func noteSignalIfAny() {
        guard !hasSeenSignal else { return }
        if taps.values.contains(where: { ($0.ring.snapshot().max() ?? 0) > 0.0001 }) { hasSeenSignal = true }
    }

    func ring(for bundleID: String) -> LevelRing? { taps[bundleID]?.ring }

    /// Smoothed 0...1 level per bundle ID, resampled on a slow timer rather than read
    /// per render frame.
    ///
    /// The research is explicit about this: Apple's own frame-rate guidance puts "small,
    /// low-speed animations... progress bar" in an 8-24 Hz tier, and reserves high rates
    /// for high-impact animation "used sparingly to minimize power consumption". A level
    /// readout in a list row is squarely the former, so it is sampled at 12 Hz and the
    /// view redraws on the value, not on a display link.
    private(set) var levels: [String: Float] = [:]

    /// Drawable waveform samples per bundle ID, oldest to newest.
    ///
    /// This is published as observable *data* rather than read out of the ring by a
    /// `TimelineView`, and that is the whole point: the ring is mutated by the realtime
    /// audio thread, which SwiftUI cannot see. A `Canvas` whose closure only reads the
    /// ring has unchanging inputs, so SwiftUI elides the redraw and the waveform freezes
    /// until something else in the view invalidates. Measured: the timeline ticked 48/s
    /// while the canvas actually drew 4/s and then 0/s. Publishing the samples makes the
    /// view's input genuinely change, so the redraw is guaranteed.
    private(set) var waveforms: [String: [Float]] = [:]

    /// Un-smoothed history, kept so each tick extends the envelope rather than
    /// re-deriving it from a smoothed copy (which would compound the smoothing).
    private var traces: [String: [Float]] = [:]

    private var sampler: Timer?

    /// How many points the trace holds. At the 20 Hz sampler that is a **7 second
    /// window**, and it scrolls exactly one point per tick — roughly a third of the speed
    /// the first version ran at, which read as frantic rather than alive.
    ///
    /// Deriving the window from the sampler rather than from the audio ring is what makes
    /// the motion calm and, more importantly, *predictable*: the IOProc's callback rate
    /// depends on the device's buffer size, so a window measured in ring entries would
    /// scroll at whatever speed the hardware happened to pick.
    private static let traceLength = 140

    /// Fast attack, slow release — the classic meter envelope. A rising edge is followed
    /// almost immediately so transients are not swallowed; a falling edge eases out, which
    /// is what stops the trace looking jittery.
    private static func follow(_ previous: Float, _ target: Float) -> Float {
        let coefficient: Float = target > previous ? 0.6 : 0.12
        return previous + (target - previous) * coefficient
    }

    /// A light spatial pass over the finished trace, so neighbouring points do not form
    /// hard corners for the curve to fight.
    private static func smoothed(_ trace: [Float]) -> [Float] {
        guard trace.count > 2 else { return trace }
        return trace.indices.map { index in
            let previous = trace[max(0, index - 1)]
            let next = trace[min(trace.count - 1, index + 1)]
            return previous * 0.25 + trace[index] * 0.5 + next * 0.25
        }
    }

    private func startSampling() {
        guard sampler == nil else { return }
        // 20 Hz: inside the 8-24 Hz tier Apple's frame-rate guidance gives for "small,
        // low-speed animations", and smooth enough for a scrolling trace.
        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Diag.hit("sampler")

                // Build the three dictionaries locally and assign each exactly once.
                // Writing an @Observable property twice per tick (once in the loop, once
                // to drop stale keys) published two change notifications and drew every
                // frame twice — measured 40 canvas draws against a 20 Hz sampler.
                // Rebuilding from `taps` also drops departed Sources for free.
                var levels: [String: Float] = [:]
                var traces: [String: [Float]] = [:]
                var waveforms: [String: [Float]] = [:]

                for (bundleID, tap) in self.taps {
                    // Only the entries written since the last tick: at 20 Hz that is a
                    // handful of IOProc callbacks, so this is "the peak of the last 50ms".
                    let peak = tap.ring.snapshot().suffix(8).max() ?? 0

                    levels[bundleID] = Self.follow(self.levels[bundleID] ?? 0, peak)

                    var trace = self.traces[bundleID] ?? [Float](repeating: 0, count: Self.traceLength)
                    trace.append(Self.follow(trace.last ?? 0, peak))
                    if trace.count > Self.traceLength { trace.removeFirst(trace.count - Self.traceLength) }
                    traces[bundleID] = trace
                    waveforms[bundleID] = Self.smoothed(trace)
                }

                self.levels = levels
                self.traces = traces
                self.waveforms = waveforms
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        sampler = timer
    }

    func sync(with sources: [Source]) {
        noteSignalIfAny()
        let wanted = Set(sources.filter { $0.isPlaying && !$0.processes.isEmpty }.map(\.bundleID))

        for (bundleID, tap) in taps where !wanted.contains(bundleID) {
            tap.stop()
            taps[bundleID] = nil
        }

        for source in sources where wanted.contains(source.bundleID) {
            guard taps[source.bundleID] == nil,
                  !starting.contains(source.bundleID),
                  failures[source.bundleID] == nil else { continue }
            starting.insert(source.bundleID)

            let processes = source.processes.filter(\.isRunningOutput).map(\.id)
            let bundleID = source.bundleID
            let name = source.name
            // Off the main thread: this both blocks and can put up the TCC prompt.
            Task.detached(priority: .userInitiated) {
                let tap = SourceTap(processes: processes, name: name)
                await MainActor.run {
                    self.starting.remove(bundleID)
                    if let failure = tap.failure {
                        self.failures[bundleID] = failure
                        tap.stop()
                    } else {
                        self.taps[bundleID] = tap
                        if self.firstStart == nil { self.firstStart = Date() }
                        self.startSampling()
                    }
                }
            }
        }
    }

    func stopAll() {
        taps.values.forEach { $0.stop() }
        taps.removeAll()
    }
}
