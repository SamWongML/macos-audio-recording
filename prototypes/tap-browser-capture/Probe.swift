//  PROTOTYPE — throwaway. One tap, built four different ways, fully instrumented.
//
//  The whole point of issue #12 is that `CATapDescription.bundleIDs` is undocumented
//  beyond a one-line header comment, so this deliberately does NOT wrap it in anything
//  clever: every strategy is spelled out, every property of the description is logged
//  back after construction, and every counter the IOProc can produce is exposed.

import CoreAudio
import Foundation
import Synchronization

// MARK: - Strategies

/// The four ways of aiming a tap that issue #12 has to tell apart.
enum TapStrategy: String, CaseIterable, Identifiable {
    /// The baseline the source-picker prototype already proved works: name the helper
    /// processes by their `AudioObjectID`, which means enumerating them by hand.
    case processObjectIDs
    /// The interesting one: start from the refined stereo-mixdown init with an empty
    /// process list, then set `bundleIDs`.
    case bundleIDsOnMixdownInit
    /// The same, but from a bare `CATapDescription()` with the mixdown flags set by hand
    /// — in case the empty process array in the other path is what breaks it.
    case bundleIDsOnBareInit
    /// A control: tap everything. If this reads zero too, the problem is the grant or the
    /// audio, not the aiming.
    case globalControl

    var id: String { rawValue }

    var label: String {
        switch self {
        case .processObjectIDs: "Process object IDs (baseline)"
        case .bundleIDsOnMixdownInit: "bundleIDs, stereoMixdownOfProcesses([]) init"
        case .bundleIDsOnBareInit: "bundleIDs, bare CATapDescription() init"
        case .globalControl: "Global tap — control"
        }
    }

    var usesBundleIDs: Bool { self == .bundleIDsOnMixdownInit || self == .bundleIDsOnBareInit }
}

// MARK: - What the realtime thread reports

/// Counters written on the IOProc thread and read by the UI. Lock-free by construction:
/// a torn read costs one wrong number in a log line, a lock would cost a dropout.
final class TapCounters: @unchecked Sendable {
    let callbacks = Atomic<Int>(0)
    let frames = Atomic<Int>(0)
    /// Buffers whose every sample was exactly zero. The silent-failure signal.
    let zeroBuffers = Atomic<Int>(0)
    let nonZeroBuffers = Atomic<Int>(0)
    /// Shape of the last buffer list to arrive — this is how a format change under the
    /// app's feet shows up even if nobody fires a property listener.
    let lastBufferCount = Atomic<Int>(0)
    let lastBytesPerBuffer = Atomic<Int>(0)
    private let peakBits = Atomic<UInt32>(0)

    func recordPeak(_ value: Float) {
        // Non-negative Float bit patterns order the same way as the floats, so a plain
        // unsigned max works.
        let bits = value.bitPattern
        var current = peakBits.load(ordering: .relaxed)
        while bits > current {
            let (exchanged, original) = peakBits.compareExchange(expected: current, desired: bits,
                                                                 ordering: .relaxed)
            if exchanged { return }
            current = original
        }
    }

    /// Peak since the last read, and reset — the once-a-second window.
    func takePeak() -> Float { Float(bitPattern: peakBits.exchange(0, ordering: .relaxed)) }
}

struct CounterSnapshot {
    var callbacks = 0
    var frames = 0
    var zeroBuffers = 0
    var nonZeroBuffers = 0
    var lastBufferCount = 0
    var lastBytesPerBuffer = 0
}

// MARK: - One tap run

/// Owns a tap, its private aggregate device and its IOProc, from creation to teardown.
/// Deliberately one-shot: "recreate" in the UI throws the whole object away and builds a
/// new one, because that is exactly the recovery the ticket asks about.
final class TapRun {
    let counters = TapCounters()
    let strategy: TapStrategy
    let bundleIDs: [String]
    let processRestoreEnabled: Bool

    private(set) var tapID = AudioObjectID(0)
    private(set) var aggregateID = AudioObjectID(0)
    private var ioProc: AudioDeviceIOProcID?
    private(set) var startStatus: OSStatus = -1
    private(set) var failure: String?
    private(set) var lastKnownFormat: AudioStreamBasicDescription?

    private var formatListener: AudioObjectPropertyListenerBlock?
    private var formatAddress = address(kAudioTapPropertyFormat)

    var isRunning: Bool { ioProc != nil && failure == nil && startStatus == noErr }

    /// Blocking, and the call that can put up the TCC prompt — never on the main thread.
    init(strategy: TapStrategy, bundleIDs: [String], processObjects: [AudioObjectID], processRestoreEnabled: Bool) {
        self.strategy = strategy
        self.bundleIDs = bundleIDs
        self.processRestoreEnabled = processRestoreEnabled
        let log = ProbeLog.shared

        log.event("tap.build strategy=\(strategy.rawValue) bundleIDs=\(bundleIDs) processObjects=\(processObjects) processRestoreEnabled=\(processRestoreEnabled)")

        let description: CATapDescription
        switch strategy {
        case .processObjectIDs:
            description = CATapDescription(stereoMixdownOfProcesses: processObjects)
        case .bundleIDsOnMixdownInit:
            description = CATapDescription(stereoMixdownOfProcesses: [])
            description.bundleIDs = bundleIDs
        case .bundleIDsOnBareInit:
            description = CATapDescription()
            description.bundleIDs = bundleIDs
            description.isMono = false
            description.isExclusive = false
            description.isMixdown = true
        case .globalControl:
            description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        }

        description.name = "AppTape issue-12 probe"
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true
        // Always assign, never assign-only-when-true: the property reads back `true` on a
        // description nobody has touched, so the default is ON and skipping the write
        // silently leaves restore enabled.
        description.isProcessRestoreEnabled = processRestoreEnabled

        // Read every property straight back off the description. If a bundle-ID tap
        // silently drops the IDs, or the bare init defaults a flag the wrong way, this is
        // where it shows — before any audio is involved.
        log.event("tap.description mono=\(description.isMono) exclusive=\(description.isExclusive) mixdown=\(description.isMixdown) private=\(description.isPrivate) restore=\(description.isProcessRestoreEnabled) processes=\(description.processes) bundleIDs=\(description.bundleIDs) deviceUID=\(description.deviceUID ?? "nil")")

        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr, tapID != 0 else {
            failure = "AudioHardwareCreateProcessTap failed (\(status))"
            log.event("tap.create FAILED status=\(status)")
            return
        }
        log.event("tap.create ok tapID=\(tapID)")

        if let asbd = formatValue(of: tapID, kAudioTapPropertyFormat) {
            lastKnownFormat = asbd
            log.event("tap.format \(describe(asbd))")
        } else {
            log.event("tap.format UNREADABLE")
        }

        guard let uid = stringValue(of: tapID, kAudioTapPropertyUID) else {
            failure = "tap has no UID"; return
        }
        let output = defaultOutputDevice()
        guard let outputUID = stringValue(of: output, kAudioDevicePropertyDeviceUID) else {
            failure = "no default output device UID"; return
        }
        log.event("output.device id=\(output) uid=\(outputUID) rate=\(nominalSampleRate(of: output) ?? -1)")

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AppTape issue-12 probe",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: uid]
            ],
        ]
        status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID)
        guard status == noErr, aggregateID != 0 else {
            failure = "AudioHardwareCreateAggregateDevice failed (\(status))"
            log.event("aggregate.create FAILED status=\(status)")
            return
        }
        log.event("aggregate.create ok id=\(aggregateID)")
        if let asbd = formatValue(of: aggregateID, kAudioDevicePropertyStreamFormat,
                                  scope: kAudioObjectPropertyScopeInput) {
            log.event("aggregate.inputFormat \(describe(asbd))")
        }

        let counters = self.counters
        status = AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateID, nil) { _, inputData, _, _, _ in
            // Realtime context: no allocation, no locks, no logging.
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            var peak: Float = 0
            var totalFrames = 0
            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                totalFrames = max(totalFrames, count / max(1, Int(buffer.mNumberChannels)))
                let samples = data.assumingMemoryBound(to: Float.self)
                for index in 0..<count { peak = max(peak, abs(samples[index])) }
            }
            counters.callbacks.wrappingAdd(1, ordering: .relaxed)
            counters.frames.wrappingAdd(totalFrames, ordering: .relaxed)
            counters.lastBufferCount.store(buffers.count, ordering: .relaxed)
            counters.lastBytesPerBuffer.store(Int(buffers.first?.mDataByteSize ?? 0), ordering: .relaxed)
            if peak == 0 {
                counters.zeroBuffers.wrappingAdd(1, ordering: .relaxed)
            } else {
                counters.nonZeroBuffers.wrappingAdd(1, ordering: .relaxed)
                counters.recordPeak(peak)
            }
        }
        guard status == noErr, let ioProc else {
            failure = "AudioDeviceCreateIOProcIDWithBlock failed (\(status))"
            log.event("ioproc.create FAILED status=\(status)")
            return
        }

        // The tap's own format can change out from under us — that is the mechanism the
        // ticket suspects behind the all-zero reports, so watch it directly.
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, let asbd = formatValue(of: self.tapID, kAudioTapPropertyFormat) else { return }
            let previous = self.lastKnownFormat
            self.lastKnownFormat = asbd
            let changed = previous.map { $0.mSampleRate != asbd.mSampleRate || $0.mChannelsPerFrame != asbd.mChannelsPerFrame } ?? true
            ProbeLog.shared.event("tap.format.listener \(describe(asbd))\(changed ? "   <<< CHANGED" : "")")
        }
        formatListener = listener
        AudioObjectAddPropertyListenerBlock(tapID, &formatAddress, DispatchQueue.main, listener)

        startStatus = AudioDeviceStart(aggregateID, ioProc)
        log.event("device.start status=\(startStatus)\(startStatus == kAudioDevicePermissionsError ? "  (kAudioDevicePermissionsError — TCC denied)" : "")")
        if startStatus != noErr { failure = "AudioDeviceStart failed (\(startStatus))" }
    }

    func snapshot() -> CounterSnapshot {
        CounterSnapshot(callbacks: counters.callbacks.load(ordering: .relaxed),
                        frames: counters.frames.load(ordering: .relaxed),
                        zeroBuffers: counters.zeroBuffers.load(ordering: .relaxed),
                        nonZeroBuffers: counters.nonZeroBuffers.load(ordering: .relaxed),
                        lastBufferCount: counters.lastBufferCount.load(ordering: .relaxed),
                        lastBytesPerBuffer: counters.lastBytesPerBuffer.load(ordering: .relaxed))
    }

    func stop() {
        if let listener = formatListener, tapID != 0 {
            AudioObjectRemovePropertyListenerBlock(tapID, &formatAddress, DispatchQueue.main, listener)
        }
        formatListener = nil
        if let ioProc {
            AudioDeviceStop(aggregateID, ioProc)
            AudioDeviceDestroyIOProcID(aggregateID, ioProc)
        }
        if aggregateID != 0 { AudioHardwareDestroyAggregateDevice(aggregateID) }
        if tapID != 0 { AudioHardwareDestroyProcessTap(tapID) }
        ProbeLog.shared.event("tap.stop tapID=\(tapID) aggregate=\(aggregateID)")
        ioProc = nil; aggregateID = 0; tapID = 0
    }

    deinit { stop() }
}
