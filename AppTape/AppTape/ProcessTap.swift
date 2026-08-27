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

        let madeProc = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, nil) { _, inputData, _, _, _ in
            // Realtime context: copy in and return. The ring drops-with-a-count on overrun,
            // so a stalled writer costs a counted seam, never a blocked audio thread.
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                ringBuffer.write(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count))
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

    deinit { stop() }
}
