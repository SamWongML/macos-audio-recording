//  PROTOTYPE — throwaway instrument for issue #14.
//
//  One question: is a TCC *denial* of kTCCServiceAudioCapture observable from inside the
//  app, or does AudioDeviceStart return noErr and hand back digital silence — which is
//  indistinguishable from a Source that happens to be quiet?
//
//  Deliberately unattended: it builds a global tap, plays its own tone so there is
//  guaranteed audio to capture, times AudioDeviceStart, samples for a few seconds, writes
//  one log line per fact, and quits. The only human input is the TCC prompt itself.
//
//  It runs under its OWN bundle id (…​.PermProbe), never AppTape's, so denying it costs
//  nothing that AppTape's real grant depends on.

import AppKit
import CoreAudio
import Foundation
import Synchronization

// MARK: - Logging

final class Log: @unchecked Sendable {
    static let shared = Log()
    private let handle: FileHandle?
    private let start = Date()
    let path: String

    init() {
        let dir = (Bundle.main.object(forInfoDictionaryKey: "ProbeLogDirectory") as? String)
            ?? NSTemporaryDirectory()
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        path = "\(dir)/perm-\(stamp).txt"
        FileManager.default.createFile(atPath: path, contents: nil)
        handle = FileHandle(forWritingAtPath: path)
    }

    func event(_ message: String) {
        let line = String(format: "%7.3f  %@\n", Date().timeIntervalSince(start), message)
        handle?.write(Data(line.utf8))
        FileHandle.standardError.write(Data(line.utf8))
    }
}

// MARK: - Core Audio plumbing (trimmed from the issue #12 probe)

func address(_ selector: AudioObjectPropertySelector,
             scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func objectIDs(of object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
    var a = address(selector)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(object, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
    var out = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    let status = out.withUnsafeMutableBytes {
        AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0.baseAddress!)
    }
    return status == noErr ? out : []
}

func stringValue(of object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var a = address(selector)
    var size = UInt32(MemoryLayout<CFString?>.size)
    var value: CFString?
    let status = withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0)
    }
    guard status == noErr, let value else { return nil }
    return value as String
}

func uint32Value(of object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
    var a = address(selector)
    var size = UInt32(MemoryLayout<UInt32>.size)
    var value: UInt32 = 0
    let status = withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0)
    }
    return status == noErr ? value : nil
}

func int32Value(of object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Int32? {
    var a = address(selector)
    var size = UInt32(MemoryLayout<Int32>.size)
    var value: Int32 = 0
    let status = withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0)
    }
    return status == noErr ? value : nil
}

func formatValue(of object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                 scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioStreamBasicDescription? {
    var a = address(selector, scope: scope)
    var asbd = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    let status = withUnsafeMutablePointer(to: &asbd) {
        AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0)
    }
    return status == noErr ? asbd : nil
}

func describe(_ asbd: AudioStreamBasicDescription) -> String {
    String(format: "rate=%.0f ch=%u flags=0x%x", asbd.mSampleRate, asbd.mChannelsPerFrame, asbd.mFormatFlags)
}

func defaultOutputDevice() -> AudioObjectID {
    var a = address(kAudioHardwarePropertyDefaultOutputDevice)
    var device = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    _ = withUnsafeMutablePointer(to: &device) {
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, $0)
    }
    return device
}

/// Every HAL process the OS currently believes is producing output. This is the free signal
/// the app can cross-check an all-zero tap against — the whole point of #14's heuristic.
func processesRunningOutput() -> [String] {
    objectIDs(of: AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
        .filter { (uint32Value(of: $0, kAudioProcessPropertyIsRunningOutput) ?? 0) != 0 }
        .map { "\(stringValue(of: $0, kAudioProcessPropertyBundleID) ?? "(none)")#\(int32Value(of: $0, kAudioProcessPropertyPID) ?? -1)" }
}

// MARK: - The tone, so there is guaranteed audio to capture

/// Plays a 440 Hz sine **from a separate process** (`afplay`) for the life of the probe.
///
/// The separate process is the whole point, found the hard way: a first cut emitted the tone
/// from the probe itself with `AVAudioEngine`, and a global tap captured it at peak exactly
/// 0.1000 with **no grant and no prompt** — a process hearing its own audio back is not a
/// TCC-gated act, so granted and denied looked identical and the instrument proved nothing.
/// Audio from another process is what actually requires the grant.
final class Tone {
    private var player: Process?
    private let file = NSTemporaryDirectory() + "apptape-probe-tone.wav"

    /// Written by hand rather than with AVFoundation so the probe's own process never opens
    /// an audio graph at all — anything the tap hears must have come from `afplay`.
    private func writeWAV(seconds: Double = 60, rate: Double = 44100, frequency: Double = 440) {
        let frames = Int(seconds * rate)
        var data = Data()
        func le32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func le16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); le32(UInt32(36 + frames * 2))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); le32(16); le16(1); le16(1)
        le32(UInt32(rate)); le32(UInt32(rate) * 2); le16(2); le16(16)
        data.append(contentsOf: Array("data".utf8)); le32(UInt32(frames * 2))
        for frame in 0..<frames {
            let value = sin(2 * Double.pi * frequency * Double(frame) / rate) * 0.1
            le16(UInt16(bitPattern: Int16(value * 32767)))
        }
        try? data.write(to: URL(fileURLWithPath: file))
    }

    func start() {
        writeWAV()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        process.arguments = [file]
        do {
            try process.run()
            player = process
            Log.shared.event("tone.start afplay pid=\(process.processIdentifier)   (separate process — the capture genuinely needs the grant)")
        } catch {
            Log.shared.event("tone.start FAILED \(error)")
        }
    }

    func stop() { player?.terminate() }
}

// MARK: - Counters written on the realtime thread

final class Counters: @unchecked Sendable {
    let callbacks = Atomic<Int>(0)
    let zeroBuffers = Atomic<Int>(0)
    let nonZeroBuffers = Atomic<Int>(0)
    private let peakBits = Atomic<UInt32>(0)

    func recordPeak(_ value: Float) {
        let bits = value.bitPattern
        var current = peakBits.load(ordering: .relaxed)
        while bits > current {
            let (exchanged, original) = peakBits.compareExchange(expected: current, desired: bits, ordering: .relaxed)
            if exchanged { return }
            current = original
        }
    }

    func peak() -> Float { Float(bitPattern: peakBits.load(ordering: .relaxed)) }
}

// MARK: - The run

func runProbe() {
    let log = Log.shared
    log.event("probe.start bundle=\(Bundle.main.bundleIdentifier ?? "?") pid=\(ProcessInfo.processInfo.processIdentifier)")
    log.event("probe.note log=\(log.path)")

    let tone = Tone()
    tone.start()
    // Let the engine actually reach the device before anything is measured.
    Thread.sleep(forTimeInterval: 1.0)
    log.event("output.running.before \(processesRunningOutput())")

    let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
    description.name = "AppTape issue-14 permission probe"
    description.uuid = UUID()
    description.muteBehavior = .unmuted
    description.isPrivate = true

    var tapID = AudioObjectID(0)
    var status = AudioHardwareCreateProcessTap(description, &tapID)
    log.event("tap.create status=\(status) tapID=\(tapID)")
    guard status == noErr, tapID != 0 else { return }

    // #11 found this succeeds ungranted and reads back a plausible format. Logged so the
    // claim is re-tested on every run rather than trusted.
    if let asbd = formatValue(of: tapID, kAudioTapPropertyFormat) {
        log.event("tap.format READABLE \(describe(asbd))   <<< readable without a grant?")
    } else {
        log.event("tap.format UNREADABLE")
    }

    guard let uid = stringValue(of: tapID, kAudioTapPropertyUID),
          let outputUID = stringValue(of: defaultOutputDevice(), kAudioDevicePropertyDeviceUID) else {
        log.event("setup.FAILED no UID"); return
    }

    var aggregateID = AudioObjectID(0)
    let aggregate: [String: Any] = [
        kAudioAggregateDeviceNameKey: "AppTape issue-14 permission probe",
        kAudioAggregateDeviceUIDKey: UUID().uuidString,
        kAudioAggregateDeviceMainSubDeviceKey: outputUID,
        kAudioAggregateDeviceIsPrivateKey: true,
        kAudioAggregateDeviceIsStackedKey: false,
        kAudioAggregateDeviceTapAutoStartKey: true,
        kAudioAggregateDeviceSubDeviceListKey: [],
        kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: uid]],
    ]
    status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
    log.event("aggregate.create status=\(status) id=\(aggregateID)")
    guard status == noErr, aggregateID != 0 else { return }

    let counters = Counters()
    var ioProc: AudioDeviceIOProcID?
    status = AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateID, nil) { _, inputData, _, _, _ in
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        var peak: Float = 0
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            for index in 0..<(Int(buffer.mDataByteSize) / MemoryLayout<Float>.size) {
                peak = max(peak, abs(samples[index]))
            }
        }
        counters.callbacks.wrappingAdd(1, ordering: .relaxed)
        if peak == 0 {
            counters.zeroBuffers.wrappingAdd(1, ordering: .relaxed)
        } else {
            counters.nonZeroBuffers.wrappingAdd(1, ordering: .relaxed)
            counters.recordPeak(peak)
        }
    }
    log.event("ioproc.create status=\(status)")
    guard status == noErr, let ioProc else { return }

    // THE measurement. If the prompt appears, this call blocks until it is answered — so
    // the elapsed time separates "prompted" from "settled" without needing to see a screen.
    log.event("device.start CALLING …")
    let began = Date()
    let startStatus = AudioDeviceStart(aggregateID, ioProc)
    let elapsed = Date().timeIntervalSince(began)
    let verdict: String
    switch startStatus {
    case noErr: verdict = "noErr"
    case kAudioDevicePermissionsError: verdict = "kAudioDevicePermissionsError ('!hog')   <<< DENIAL IS OBSERVABLE"
    default: verdict = "status=\(startStatus)"
    }
    log.event(String(format: "device.start RETURNED %@ after %.3fs%@", verdict, elapsed,
                     elapsed > 1.5 ? "   <<< blocked — a prompt was almost certainly on screen" : ""))

    for second in 1...6 {
        Thread.sleep(forTimeInterval: 1.0)
        log.event(String(format: "tick %d callbacks=%d zero=%d nonZero=%d peak=%.4f",
                         second,
                         counters.callbacks.load(ordering: .relaxed),
                         counters.zeroBuffers.load(ordering: .relaxed),
                         counters.nonZeroBuffers.load(ordering: .relaxed),
                         counters.peak()))
    }

    let zero = counters.zeroBuffers.load(ordering: .relaxed)
    let nonZero = counters.nonZeroBuffers.load(ordering: .relaxed)
    let running = processesRunningOutput()
    log.event("output.running.after \(running)")
    log.event("VERDICT startStatus=\(verdict) callbacks=\(counters.callbacks.load(ordering: .relaxed)) nonZero=\(nonZero) peak=\(counters.peak())")
    if nonZero == 0 && !running.isEmpty {
        log.event("VERDICT all-zero while \(running.count) process(es) report output   <<< THE SILENT FAILURE")
    }
    if nonZero == 0 && zero == 0 {
        log.event("VERDICT no buffers at all — the device never called us")
    }

    AudioDeviceStop(aggregateID, ioProc)
    AudioDeviceDestroyIOProcID(aggregateID, ioProc)
    AudioHardwareDestroyAggregateDevice(aggregateID)
    AudioHardwareDestroyProcessTap(tapID)
    tone.stop()
    log.event("probe.done")
}

@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Thread.detachNewThread {
            runProbe()
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        app.run()
    }
}
