//
//  SourceLevelMonitor.swift
//  AppTape
//

import CoreAudio
import Foundation
import Observation
import Synchronization

/// Live per-Source amplitude for the panel's row waveforms (issue #6, variant H): a real
/// waveform painted behind every *playing* row, fed by an actual Core Audio process tap on
/// each app currently making sound.
///
/// This is the expensive answer to "show a real waveform in the row", and it is a **deliberate
/// product choice** to run it: `AudioDeviceStart` is where macOS prompts for System Audio
/// Recording, so opening these probes asks for the grant when the panel is opened over playing
/// audio — *before* the user has pressed record. That trades spec story #14's "prompt on first
/// record" for the prototype's live per-app waveforms, chosen knowingly.
///
/// The monitor runs only while the panel is on screen (`sync` on appear, `stopAll` on disappear),
/// so at rest the app holds no taps. The Source being recorded is **excluded**: its live level
/// already comes from the recording tap (`RecordingController.meterColumns`), so a second tap on
/// the same process is never opened.

// MARK: - Lock-free ring of recent amplitudes

/// A fixed-size ring the realtime IOProc writes and the main thread reads without locking.
/// Deliberately racy: a torn read costs one wrong pixel in a scrolling waveform, and a lock on a
/// realtime audio thread costs a dropout — the wrong trade. This never touches the recording path.
private final class LevelRing: @unchecked Sendable {
    static let capacity = 220

    private let storage = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
    private let cursor = Atomic<Int>(0)

    init() { storage.initialize(repeating: 0, count: Self.capacity) }
    deinit { storage.deallocate() }

    /// Realtime thread. No allocation, no locks, no Swift runtime calls.
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

// MARK: - One probe tap per playing Source

/// Owns a private tap + aggregate + IOProc for a single Source, filling a ring with the peak
/// amplitude of every delivered buffer. Separate from `ProcessTap`, which owns the *recording*
/// path: this one keeps no ring buffer of samples and no timestamps — it only needs a peak.
private final class SourceLevelProbe {
    let ring = LevelRing()
    private var tapID = AudioObjectID(0)
    private var aggregateID = AudioObjectID(0)
    private var ioProc: AudioDeviceIOProcID?
    private(set) var failure: String?

    /// Builds and starts the probe. Blocking, and the *first* call is where macOS puts up the
    /// System Audio Recording prompt — so never call this on the main thread.
    init(processObjectIDs: [AudioObjectID], name: String) {
        let description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        description.name = "AppTape level probe — \(name)"
        description.uuid = UUID()
        // Never mute the app we are listening to, and keep the probe out of every other
        // process's device list.
        description.muteBehavior = .unmuted
        description.isPrivate = true

        var tap = AudioObjectID(0)
        var aggregate = AudioObjectID(0)
        var proc: AudioDeviceIOProcID?
        var committed = false
        defer {
            if !committed {
                if let proc { AudioDeviceDestroyIOProcID(aggregate, proc) }
                if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate) }
                if tap != 0 { AudioHardwareDestroyProcessTap(tap) }
            }
        }

        guard AudioHardwareCreateProcessTap(description, &tap) == noErr, tap != 0 else {
            failure = "tap creation failed"; return
        }
        guard let tapUID = CAProperty.string(of: tap, kAudioTapPropertyUID) else {
            failure = "no tap UID"; return
        }
        let output = CAProperty.defaultOutputDevice()
        guard let outputUID = CAProperty.string(of: output, kAudioDevicePropertyDeviceUID) else {
            failure = "no output UID"; return
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AppTape probe \(name)",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: tapUID]
            ],
        ]
        guard AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate) == noErr,
              aggregate != 0 else {
            failure = "aggregate creation failed"; return
        }

        let channels = max(1, Int(CAProperty.streamFormat(of: tap, kAudioTapPropertyFormat)?.mChannelsPerFrame ?? 2))
        let ring = self.ring
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, nil) { _, inputData, _, _, _ in
            // Realtime context: peak of the delivered Float32 buffers, then return.
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
        guard status == noErr, let proc else { failure = "IOProc creation failed"; return }

        // The permission gate.
        let started = AudioDeviceStart(aggregate, proc)
        if started != noErr {
            failure = started == kAudioDevicePermissionsError ? "permission denied" : "start failed (\(started))"
            return
        }

        tapID = tap
        aggregateID = aggregate
        ioProc = proc
        committed = true
    }

    func stop() {
        if let ioProc {
            AudioDeviceStop(aggregateID, ioProc)
            AudioDeviceDestroyIOProcID(aggregateID, ioProc)
        }
        ioProc = nil
        if aggregateID != 0 { AudioHardwareDestroyAggregateDevice(aggregateID) }
        if tapID != 0 { AudioHardwareDestroyProcessTap(tapID) }
        aggregateID = 0
        tapID = 0
    }

    deinit { stop() }
}

// MARK: - The monitor

/// Keeps exactly one `SourceLevelProbe` alive per currently-playing Source, and publishes a
/// drawable waveform trace per bundle ID for the panel to read.
@MainActor
@Observable
final class SourceLevelMonitor {
    private var probes: [String: SourceLevelProbe] = [:]
    private var starting: Set<String> = []
    /// Bundle IDs whose probe failed, so a hard failure is not retried every half second.
    private var failures: [String: String] = [:]

    /// Drawable waveform samples per bundle ID, oldest to newest. Published as observable *data*
    /// (not read out of the ring by the view) so the row's `Shape` genuinely re-inputs each tick —
    /// the ring is mutated by the audio thread, which SwiftUI cannot observe.
    private(set) var waveforms: [String: [Float]] = [:]

    /// Un-smoothed history, kept so each tick extends the envelope rather than re-deriving it.
    private var traces: [String: [Float]] = [:]

    private var hasSeenSignal = false
    private var firstStart: Date?
    private var sampler: Timer?

    /// 7-second window at the 20 Hz sampler, scrolling one point per tick.
    private static let traceLength = 140

    /// There is no API to query the System Audio Recording permission (issue #3), and an ungranted
    /// tap returns silence rather than an error — so "several seconds of probes running, every
    /// sample zero" is the only signal the grant is missing. A heuristic, indistinguishable from
    /// genuinely silent playback, surfaced as the header's lock (issue #6).
    var looksUnpermitted: Bool {
        guard let firstStart, !hasSeenSignal, !probes.isEmpty else { return false }
        return Date().timeIntervalSince(firstStart) > 4
    }

    /// Fast attack, slow release — the classic meter envelope.
    private static func follow(_ previous: Float, _ target: Float) -> Float {
        let coefficient: Float = target > previous ? 0.6 : 0.12
        return previous + (target - previous) * coefficient
    }

    /// A light spatial pass so neighbouring points do not form hard corners for the curve to fight.
    private static func smoothed(_ trace: [Float]) -> [Float] {
        guard trace.count > 2 else { return trace }
        return trace.indices.map { index in
            let previous = trace[max(0, index - 1)]
            let next = trace[min(trace.count - 1, index + 1)]
            return previous * 0.25 + trace[index] * 0.5 + next * 0.25
        }
    }

    /// Reconcile the live probes to the currently-playing Sources. `excluding` drops one Source —
    /// the one being recorded — because its level already comes from the recording tap, so no
    /// second tap is opened on it.
    func sync(with sources: [Source], excluding excludedBundleID: String? = nil) {
        noteSignalIfAny()
        let wanted = Set(sources
            .filter { $0.isPlaying && !$0.processObjectIDs.isEmpty && $0.bundleID != excludedBundleID }
            .map(\.bundleID))

        for (bundleID, probe) in probes where !wanted.contains(bundleID) {
            probe.stop()
            probes[bundleID] = nil
        }

        for source in sources where wanted.contains(source.bundleID) {
            guard probes[source.bundleID] == nil,
                  !starting.contains(source.bundleID),
                  failures[source.bundleID] == nil else { continue }
            starting.insert(source.bundleID)

            let processObjectIDs = source.processObjectIDs
            let bundleID = source.bundleID
            let name = source.name
            // Off the main thread: this both blocks and can put up the TCC prompt.
            Task.detached(priority: .userInitiated) {
                let probe = SourceLevelProbe(processObjectIDs: processObjectIDs, name: name)
                await MainActor.run {
                    self.starting.remove(bundleID)
                    if let failure = probe.failure {
                        self.failures[bundleID] = failure
                        probe.stop()
                    } else {
                        self.probes[bundleID] = probe
                        if self.firstStart == nil { self.firstStart = Date() }
                        self.startSampling()
                    }
                }
            }
        }
    }

    /// Tears down every probe and stops the sampler. Called when the panel disappears, so the app
    /// holds no taps at rest.
    func stopAll() {
        probes.values.forEach { $0.stop() }
        probes.removeAll()
        starting.removeAll()
        failures.removeAll()
        traces.removeAll()
        waveforms = [:]
        firstStart = nil
        hasSeenSignal = false
        sampler?.invalidate()
        sampler = nil
    }

    private func noteSignalIfAny() {
        guard !hasSeenSignal else { return }
        if probes.values.contains(where: { ($0.ring.snapshot().max() ?? 0) > 0.0001 }) { hasSeenSignal = true }
    }

    private func startSampling() {
        guard sampler == nil else { return }
        // 20 Hz: inside the 8-24 Hz tier Apple's frame-rate guidance gives for small, low-speed
        // animations, and smooth enough for a scrolling trace.
        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }

                // Build both dictionaries locally and assign each exactly once: writing an
                // @Observable property twice per tick publishes two change notifications and
                // draws every frame twice. Rebuilding from `probes` drops departed Sources for free.
                var traces: [String: [Float]] = [:]
                var waveforms: [String: [Float]] = [:]

                for (bundleID, probe) in self.probes {
                    // Only the entries written since the last tick: at 20 Hz, ~the peak of the last 50 ms.
                    let peak = probe.ring.snapshot().suffix(8).max() ?? 0

                    var trace = self.traces[bundleID] ?? [Float](repeating: 0, count: Self.traceLength)
                    trace.append(Self.follow(trace.last ?? 0, peak))
                    if trace.count > Self.traceLength { trace.removeFirst(trace.count - Self.traceLength) }
                    traces[bundleID] = trace
                    waveforms[bundleID] = Self.smoothed(trace)
                }

                self.traces = traces
                self.waveforms = waveforms
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        sampler = timer
    }
}
