//
//  CoreAudioProperties.swift
//  AppTape
//

import CoreAudio

/// Thin typed readers over the `AudioObjectGetPropertyData` C API — the plumbing every
/// Core Audio touch in the app goes through, so the raw pointer dance lives in exactly
/// one place. Promoted verbatim from the issue #12 capture spike.
enum CAProperty {
    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    static func objectIDs(of object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var a = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var out = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let status = out.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0.baseAddress!)
        }
        return status == noErr ? out : []
    }

    static func string(of object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var a = address(selector)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }

    static func int32(of object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Int32? {
        var a = address(selector)
        var size = UInt32(MemoryLayout<Int32>.size)
        var value: Int32 = 0
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0)
        }
        return status == noErr ? value : nil
    }

    static func uint32(of object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var a = address(selector)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var value: UInt32 = 0
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0)
        }
        return status == noErr ? value : nil
    }

    /// The tap's own stream format (`kAudioTapPropertyFormat`) — the ASBD the CAF master
    /// is written with, read at tap creation and never assumed (ADR-0003).
    static func streamFormat(of object: AudioObjectID,
                             _ selector: AudioObjectPropertySelector,
                             scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioStreamBasicDescription? {
        var a = address(selector, scope: scope)
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = withUnsafeMutablePointer(to: &asbd) {
            AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0)
        }
        return status == noErr ? asbd : nil
    }

    static func defaultOutputDevice() -> AudioObjectID {
        var a = address(kAudioHardwarePropertyDefaultOutputDevice)
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        _ = withUnsafeMutablePointer(to: &device) {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, $0)
        }
        return device
    }
}
