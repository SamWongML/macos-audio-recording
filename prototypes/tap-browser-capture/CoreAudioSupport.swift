//  PROTOTYPE — throwaway. Core Audio property plumbing plus the live HAL process table.
//  Trimmed from the issue #6 source-picker prototype; the mapping heuristics live there.

import AppKit
import CoreAudio
import Foundation

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

func int32Value(of object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Int32? {
    var a = address(selector)
    var size = UInt32(MemoryLayout<Int32>.size)
    var value: Int32 = 0
    let status = withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0)
    }
    return status == noErr ? value : nil
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

// MARK: - Formats

func formatValue(of object: AudioObjectID,
                 _ selector: AudioObjectPropertySelector,
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
    let id = asbd.mFormatID.bigEndian
    let fourCC = String(bytes: withUnsafeBytes(of: id) { Array($0) }, encoding: .ascii) ?? "????"
    return String(format: "rate=%.0f ch=%u bits=%u fmt=%@ flags=0x%x bytesPerFrame=%u",
                  asbd.mSampleRate, asbd.mChannelsPerFrame, asbd.mBitsPerChannel,
                  fourCC, asbd.mFormatFlags, asbd.mBytesPerFrame)
}

// MARK: - Devices

func defaultOutputDevice() -> AudioObjectID {
    var a = address(kAudioHardwarePropertyDefaultOutputDevice)
    var device = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    _ = withUnsafeMutablePointer(to: &device) {
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, $0)
    }
    return device
}

func nominalSampleRate(of device: AudioObjectID) -> Double? {
    var a = address(kAudioDevicePropertyNominalSampleRate)
    var rate: Double = 0
    var size = UInt32(MemoryLayout<Double>.size)
    let status = withUnsafeMutablePointer(to: &rate) {
        AudioObjectGetPropertyData(device, &a, 0, nil, &size, $0)
    }
    return status == noErr ? rate : nil
}

/// Every discrete rate the device admits to, so the probe offers real buttons rather than
/// guessing that 44.1 and 48 are available.
func availableSampleRates(of device: AudioObjectID) -> [Double] {
    var a = address(kAudioDevicePropertyAvailableNominalSampleRates)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(device, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
    var ranges = [AudioValueRange](repeating: AudioValueRange(), count: Int(size) / MemoryLayout<AudioValueRange>.size)
    let status = ranges.withUnsafeMutableBytes {
        AudioObjectGetPropertyData(device, &a, 0, nil, &size, $0.baseAddress!)
    }
    guard status == noErr else { return [] }
    return Array(Set(ranges.map(\.mMinimum))).sorted()
}

@discardableResult
func setNominalSampleRate(of device: AudioObjectID, to rate: Double) -> OSStatus {
    var a = address(kAudioDevicePropertyNominalSampleRate)
    var value = rate
    return withUnsafeMutablePointer(to: &value) {
        AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<Double>.size), $0)
    }
}

// MARK: - The HAL process table

/// One HAL client process, straight out of `kAudioHardwarePropertyProcessObjectList`.
struct AudioProcess: Identifiable, Hashable {
    var id: AudioObjectID
    var pid: pid_t
    var bundleID: String
    var isRunningOutput: Bool
    var appName: String?

    var line: String {
        "obj=\(id) pid=\(pid) out=\(isRunningOutput ? "Y" : ".") bundle=\(bundleID.isEmpty ? "(none)" : bundleID) name=\(appName ?? "(no NSRunningApplication)")"
    }
}

func scanAudioProcesses() -> [AudioProcess] {
    let running = NSWorkspace.shared.runningApplications
    return objectIDs(of: AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
        .map { object in
            let pid = int32Value(of: object, kAudioProcessPropertyPID) ?? -1
            return AudioProcess(
                id: object,
                pid: pid,
                bundleID: stringValue(of: object, kAudioProcessPropertyBundleID) ?? "",
                isRunningOutput: (uint32Value(of: object, kAudioProcessPropertyIsRunningOutput) ?? 0) != 0,
                appName: running.first { $0.processIdentifier == pid }?.localizedName)
        }
        .sorted { ($0.isRunningOutput ? 0 : 1, $0.bundleID, $0.pid) < ($1.isRunningOutput ? 0 : 1, $1.bundleID, $1.pid) }
}
