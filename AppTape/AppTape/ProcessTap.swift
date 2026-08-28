//
//  ProcessTap.swift
//  AppTape
//

import CoreAudio
import Foundation

/// Owns one Core Audio process tap, its private tap-only aggregate device, and the realtime
/// IOProc that reads it — aimed at a Source's helper processes **by object ID** (ADR-0001).
/// The IOProc does one thing: copy the delivered samples into the ring buffer and return.
/// It never blocks, never allocates, never logs (ADR-0003).
///
/// The tap is requested as a stereo mixdown, so a 6-channel output device does not silently
/// yield 6-channel Recordings; its actual `format` is read back from `kAudioTapPropertyFormat`
/// and is the format the master is written with — never assumed (ADR-0003). The ring is sized
/// from that format at ~10 s. Aiming by object ID keeps `processRestoreEnabled` (assigned
/// explicitly; it defaults on), so a Source that quits and relaunches is picked up again
/// within about a second with no re-aiming (ADR-0001).
final class ProcessTap {
    /// The tap's delivered stream format — interleaved Float32 stereo in practice, but read,
    /// not assumed.
    let format: AudioStreamBasicDescription
    /// The realtime→writer seam. The writer thread drains this.
    let ring: AudioRingBuffer
    /// The parallel host-time channel: one mark per delivered buffer, so the writer can reconcile
    /// wall-clock gaps into Seams (ADR-0010).
    let timestampRing = TimestampRing()

    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioObjectID = 0
    private var ioProc: AudioDeviceIOProcID?

    enum TapError: Error {
        case createTap(OSStatus)
        case noFormat
        case noTapUID
        case noOutputDevice
        case createAggregate(OSStatus)
        case createIOProc(OSStatus)
        case permissionDenied
        case start(OSStatus)
    }

    /// Builds and starts the tap. Blocking, and the call that can put up the TCC prompt, so
    /// it must run off the main thread (issue #12 saw `AudioDeviceStart` block 90 s while the
    /// prompt was up).
    init(processObjectIDs: [AudioObjectID], ringCapacitySeconds: Double = 10) throws {
        // Stereo mixdown of exactly the resolved helper processes, aimed by object ID.
        let description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        description.name = "AppTape capture"
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true
        // Always assign, never assign-only-when-true: the property reads back `true` on an
        // untouched description, so skipping the write silently leaves restore enabled.
        description.isProcessRestoreEnabled = true

        // Everything below works in locals; a half-built tap must be destroyed on any throw,
        // and `stop()` cannot run before the stored `let`s exist. One `defer` unwinds whatever
        // was created unless `committed` flips true once the tap is running — so each guard
        // just throws, and the teardown is written once.
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

        let created = AudioHardwareCreateProcessTap(description, &tap)
        guard created == noErr, tap != 0 else { throw TapError.createTap(created) }

        guard let asbd = CAProperty.streamFormat(of: tap, kAudioTapPropertyFormat) else {
            throw TapError.noFormat
        }
        let channels = max(1, Int(asbd.mChannelsPerFrame))
        let capacity = max(1, Int(asbd.mSampleRate * Double(channels) * ringCapacitySeconds))
        let ringBuffer = AudioRingBuffer(capacitySamples: capacity)

        guard let tapUID = CAProperty.string(of: tap, kAudioTapPropertyUID) else {
            throw TapError.noTapUID
        }
        let output = CAProperty.defaultOutputDevice()
        guard let outputUID = CAProperty.string(of: output, kAudioDevicePropertyDeviceUID) else {
            throw TapError.noOutputDevice
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AppTape capture",
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
        let madeAggregate = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate)
        guard madeAggregate == noErr, aggregate != 0 else {
            throw TapError.createAggregate(madeAggregate)
        }

        // Host time (`mHostTime`) arrives in mach absolute-time units; this scale turns it into
        // seconds once, so the realtime block only multiplies.
        var timebase = mach_timebase_info()
        mach_timebase_info(&timebase)
        let hostClockScale = Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000.0
        let marks = timestampRing

        let madeProc = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, nil) { _, inputData, inInputTime, _, _ in
            // Realtime context: copy in and return. The ring drops-with-a-count on overrun,
            // so a stalled writer costs a counted seam, never a blocked audio thread.
            let firstFrame = ringBuffer.writtenSamples / channels
            var wroteAny = false
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                if ringBuffer.write(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count)) {
                    wroteAny = true
                }
            }
            // One mark per callback, stamping this buffer's first frame with its host time — but
            // only when the write landed, so a dropped buffer leaves the host-time jump the writer
            // reads as an overrun Seam (ADR-0010).
            if wroteAny {
                let ts = inInputTime.pointee
                let valid = ts.mFlags.contains(.hostTimeValid)
                marks.push(ringFrame: firstFrame, hostSeconds: Double(ts.mHostTime) * hostClockScale, valid: valid)
            }
        }
        guard madeProc == noErr, let proc else { throw TapError.createIOProc(madeProc) }

        let started = AudioDeviceStart(aggregate, proc)
        guard started == noErr else {
            throw started == kAudioDevicePermissionsError ? TapError.permissionDenied : TapError.start(started)
        }

        // Running — commit, so the defer leaves everything standing.
        format = asbd
        ring = ringBuffer
        tapID = tap
        aggregateID = aggregate
        ioProc = proc
        committed = true
    }

    /// Tears the whole thing down. Destroying and recreating tap and aggregate is the clean
    /// recovery issue #12 verified; this is one half of it.
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

    /// The bundle IDs the given HAL client object IDs belong to, read at capture start. A rebuild
    /// holds these rather than the object IDs, which are dead if the Source relaunched (ADR-0007).
    static func bundleIDs(of objectIDs: [AudioObjectID]) -> Set<String> {
        Set(objectIDs.compactMap { CAProperty.string(of: $0, kAudioProcessPropertyBundleID) }
            .filter { !$0.isEmpty })
    }

    /// Re-resolve the Source's live HAL clients by bundle ID — the re-resolution a rebuild performs,
    /// so a Source that quit and relaunched is picked up again at its new object IDs (ADR-0007).
    /// Pure Core Audio, no workspace: it re-scans the process table and keeps the clients whose
    /// bundle ID the Recording started from, which covers a relaunched helper (same bundle, new ID)
    /// and WebKit's GPU process (always `com.apple.WebKit.GPU`).
    static func resolveObjectIDs(matchingBundleIDs bundleIDs: Set<String>) -> [AudioObjectID] {
        guard !bundleIDs.isEmpty else { return [] }
        return CAProperty.objectIDs(of: AudioObjectID(kAudioObjectSystemObject),
                                    kAudioHardwarePropertyProcessObjectList)
            .filter { bundleIDs.contains(CAProperty.string(of: $0, kAudioProcessPropertyBundleID) ?? "") }
    }

    deinit { stop() }
}
