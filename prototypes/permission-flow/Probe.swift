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
    private func writeWAV(seconds: Double, rate: Double = 44100, frequency: Double = 440) {
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

    func start(seconds: Double = 60) {
        writeWAV(seconds: seconds)
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

// MARK: - One tap, buildable and rebuildable in place

/// Owns a tap, its aggregate device and its IOProc. Separated out from the one-shot probe so
/// the recovery run can tear one down and build another **in the same process** — which is
/// exactly the question: does a Settings toggle reach an existing tap, a new tap, or neither?
final class TapSession {
    let counters = Counters()
    private(set) var tapID = AudioObjectID(0)
    private(set) var aggregateID = AudioObjectID(0)
    private var ioProc: AudioDeviceIOProcID?
    private(set) var startStatus: OSStatus = -1

    @discardableResult
    func build(label: String) -> Bool {
        let log = Log.shared
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "AppTape issue-14 permission probe"
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true

        var status = AudioHardwareCreateProcessTap(description, &tapID)
        log.event("\(label) tap.create status=\(status) tapID=\(tapID)")
        guard status == noErr, tapID != 0 else { return false }

        if let asbd = formatValue(of: tapID, kAudioTapPropertyFormat) {
            log.event("\(label) tap.format READABLE \(describe(asbd))   <<< readable without a grant?")
        } else {
            log.event("\(label) tap.format UNREADABLE")
        }

        guard let uid = stringValue(of: tapID, kAudioTapPropertyUID),
              let outputUID = stringValue(of: defaultOutputDevice(), kAudioDevicePropertyDeviceUID) else {
            log.event("\(label) setup.FAILED no UID"); return false
        }

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
        log.event("\(label) aggregate.create status=\(status) id=\(aggregateID)")
        guard status == noErr, aggregateID != 0 else { return false }

        let counters = self.counters
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
        log.event("\(label) ioproc.create status=\(status)")
        guard status == noErr, let ioProc else { return false }

        log.event("\(label) device.start CALLING …")
        let began = Date()
        startStatus = AudioDeviceStart(aggregateID, ioProc)
        let elapsed = Date().timeIntervalSince(began)
        let verdict = startStatus == noErr ? "noErr"
            : (startStatus == kAudioDevicePermissionsError
               ? "kAudioDevicePermissionsError ('!hog')   <<< DENIAL IS OBSERVABLE" : "status=\(startStatus)")
        log.event(String(format: "%@ device.start RETURNED %@ after %.3fs%@", label, verdict, elapsed,
                         elapsed > 1.5 ? "   <<< blocked — a prompt was almost certainly on screen" : ""))
        return startStatus == noErr
    }

    func teardown() {
        if let ioProc {
            AudioDeviceStop(aggregateID, ioProc)
            AudioDeviceDestroyIOProcID(aggregateID, ioProc)
        }
        if aggregateID != 0 { AudioHardwareDestroyAggregateDevice(aggregateID) }
        if tapID != 0 { AudioHardwareDestroyProcessTap(tapID) }
        ioProc = nil; aggregateID = 0; tapID = 0
    }
}

// MARK: - The run



func runProbe() {
    let log = Log.shared
    log.event("probe.start mode=oneshot bundle=\(Bundle.main.bundleIdentifier ?? "?") pid=\(ProcessInfo.processInfo.processIdentifier)")
    log.event("probe.note log=\(log.path)")

    let tone = Tone()
    tone.start()
    Thread.sleep(forTimeInterval: 1.0)
    log.event("output.running.before \(processesRunningOutput())")

    let session = TapSession()
    guard session.build(label: "tap") else { tone.stop(); log.event("probe.done"); return }

    for second in 1...6 {
        Thread.sleep(forTimeInterval: 1.0)
        log.event(String(format: "tick %d callbacks=%d zero=%d nonZero=%d peak=%.4f", second,
                         session.counters.callbacks.load(ordering: .relaxed),
                         session.counters.zeroBuffers.load(ordering: .relaxed),
                         session.counters.nonZeroBuffers.load(ordering: .relaxed),
                         session.counters.peak()))
    }

    let nonZero = session.counters.nonZeroBuffers.load(ordering: .relaxed)
    let zero = session.counters.zeroBuffers.load(ordering: .relaxed)
    let running = processesRunningOutput()
    log.event("output.running.after \(running)")
    log.event("VERDICT callbacks=\(session.counters.callbacks.load(ordering: .relaxed)) nonZero=\(nonZero) peak=\(session.counters.peak())")
    if nonZero == 0 && !running.isEmpty {
        log.event("VERDICT all-zero while \(running.count) process(es) report output   <<< THE SILENT FAILURE")
    }
    if nonZero == 0 && zero == 0 { log.event("VERDICT no buffers at all — the device never called us") }

    session.teardown()
    tone.stop()
    log.event("probe.done")
}

/// Does flipping the System Settings toggle reach a tap that is already built?
///
/// Three answers are possible and the run distinguishes all of them: the **existing** tap
/// starts delivering audio, only a **rebuilt** tap does, or **neither** does and the app has
/// to be relaunched. A fourth is possible without the probe doing anything — if macOS kills
/// the process on the TCC change, the log simply stops, which is its own answer.
func runRecover() {
    let log = Log.shared
    log.event("probe.start mode=recover bundle=\(Bundle.main.bundleIdentifier ?? "?") pid=\(ProcessInfo.processInfo.processIdentifier)")
    log.event("probe.note log=\(log.path)")

    let tone = Tone()
    tone.start(seconds: 300)
    Thread.sleep(forTimeInterval: 1.0)

    var session = TapSession()
    guard session.build(label: "A") else { tone.stop(); log.event("probe.done"); return }

    var firstNonZeroTick: Int?
    var rebuiltAtTick: Int?
    let rebuildAt = 75      // long enough for a human to walk to System Settings and flip it
    let total = 140

    log.event("PHASE 1 — original tap A is running. Flip the toggle ON in System Settings now.")
    for tick in 1...total {
        Thread.sleep(forTimeInterval: 1.0)
        let nonZero = session.counters.nonZeroBuffers.load(ordering: .relaxed)
        if firstNonZeroTick == nil && nonZero > 0 {
            firstNonZeroTick = tick
            let which = rebuiltAtTick == nil ? "THE ORIGINAL TAP A" : "THE REBUILT TAP B"
            log.event("<<< RECOVERED at tick \(tick), on \(which) — no relaunch needed")
        }
        if tick % 5 == 0 || firstNonZeroTick == tick {
            log.event(String(format: "tick %d callbacks=%d zero=%d nonZero=%d peak=%.4f running=%@", tick,
                             session.counters.callbacks.load(ordering: .relaxed),
                             session.counters.zeroBuffers.load(ordering: .relaxed),
                             nonZero, session.counters.peak(),
                             String(describing: processesRunningOutput().count)))
        }
        if tick == rebuildAt && firstNonZeroTick == nil {
            log.event("PHASE 2 — tap A never recovered. Tearing it down and building tap B in the SAME process.")
            session.teardown()
            session = TapSession()
            rebuiltAtTick = tick
            guard session.build(label: "B") else { break }
        }
        if let first = firstNonZeroTick, tick > first + 4 { break }
    }

    if firstNonZeroTick == nil {
        log.event("<<< NEITHER the original tap nor a rebuilt one recovered — a relaunch is required")
    }
    session.teardown()
    tone.stop()
    log.event("probe.done")
}

@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let recover = CommandLine.arguments.contains("recover")
        Thread.detachNewThread {
            recover ? runRecover() : runProbe()
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        app.run()
    }
}
