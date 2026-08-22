//  PROTOTYPE — throwaway. Answers issue #6: how does the user choose a Source?
//  Not production code. No tests, no error handling.

import AppKit
import CoreAudio
import Observation

// MARK: - Raw Core Audio process objects

/// One HAL client process, straight out of `kAudioHardwarePropertyProcessObjectList`.
struct AudioProcess: Identifiable, Hashable {
    var id: AudioObjectID
    var pid: pid_t
    var bundleID: String
    var isRunningOutput: Bool
    /// `NSRunningApplication.localizedName`, when the OS admits one exists. Often nil
    /// for exactly the process that is producing the audio.
    var appName: String?
}

private func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector,
                               mScope: kAudioObjectPropertyScopeGlobal,
                               mElement: kAudioObjectPropertyElementMain)
}

private func objectIDs(of object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
    var a = address(selector)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(object, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
    var out = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    let status = out.withUnsafeMutableBytes {
        AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0.baseAddress!)
    }
    return status == noErr ? out : []
}

private func string(of object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var a = address(selector)
    var size = UInt32(MemoryLayout<CFString?>.size)
    var value: CFString?
    let status = withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0)
    }
    guard status == noErr, let value else { return nil }
    return value as String
}

private func int32(of object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Int32? {
    var a = address(selector)
    var size = UInt32(MemoryLayout<Int32>.size)
    var value: Int32 = 0
    let status = withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0)
    }
    return status == noErr ? value : nil
}

private func uint32(of object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
    var a = address(selector)
    var size = UInt32(MemoryLayout<UInt32>.size)
    var value: UInt32 = 0
    let status = withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0)
    }
    return status == noErr ? value : nil
}

func scanAudioProcesses() -> [AudioProcess] {
    let running = NSWorkspace.shared.runningApplications
    return objectIDs(of: AudioObjectID(kAudioObjectSystemObject),
                     kAudioHardwarePropertyProcessObjectList).map { object in
        let pid = int32(of: object, kAudioProcessPropertyPID) ?? -1
        return AudioProcess(
            id: object,
            pid: pid,
            bundleID: string(of: object, kAudioProcessPropertyBundleID) ?? "",
            isRunningOutput: (uint32(of: object, kAudioProcessPropertyIsRunningOutput) ?? 0) != 0,
            appName: running.first { $0.processIdentifier == pid }?.localizedName
        )
    }
}

// MARK: - Source: what the user actually picks

/// A user-facing application the user could choose to capture. One Source fans out to
/// zero or more `AudioProcess`es — the helper processes that own the real HAL clients.
struct Source: Identifiable, Hashable {
    var id: String { bundleID }
    var bundleID: String
    var name: String
    var icon: NSImage?
    /// True when any process belonging to this Source is pushing audio out right now.
    var isPlaying: Bool
    /// The HAL clients this Source resolves to. Empty means "the app is running but has
    /// not touched Core Audio yet" — a tap by bundle ID would find nothing to attach to.
    var processes: [AudioProcess]

    static func == (a: Source, b: Source) -> Bool {
        a.bundleID == b.bundleID && a.isPlaying == b.isPlaying && a.processes == b.processes
    }
    func hash(into hasher: inout Hasher) { hasher.combine(bundleID) }
}

/// Maps a HAL client's bundle ID back to the app a user would name.
///
/// The plain prefix rule (`com.google.Chrome.helper` → `com.google.Chrome`) covers Chrome
/// and Claude. WebKit is the exception the rule cannot reach: every WebKit client's audio
/// runs through `com.apple.WebKit.GPU`, whose bundle ID says nothing about who owns it —
/// only its `NSRunningApplication.localizedName` ("Safari Graphics and Media") does.
func owningBundleID(of process: AudioProcess, among apps: [NSRunningApplication]) -> String? {
    if process.bundleID == "com.apple.WebKit.GPU" {
        // "Safari Graphics and Media" → find the app whose name is that prefix.
        guard let name = process.appName else { return nil }
        let owner = name.replacingOccurrences(of: " Graphics and Media", with: "")
        return apps.first { $0.localizedName == owner }?.bundleIdentifier
    }
    // Longest matching prefix wins, so `com.google.Chrome.helper` picks Chrome, not
    // some shorter `com.google` if one ever existed.
    return apps
        .compactMap(\.bundleIdentifier)
        .filter { process.bundleID == $0 || process.bundleID.hasPrefix($0 + ".") }
        .max { $0.count < $1.count }
}

@Observable
final class SourceModel {
    /// Every user-facing app, playing first, then alphabetical.
    private(set) var sources: [Source] = []
    /// The raw table, for the debug drawer — this is the evidence, not the design.
    private(set) var processes: [AudioProcess] = []
    var selectedID: String?

    var selected: Source? { sources.first { $0.id == selectedID } }
    var playing: [Source] { sources.filter(\.isPlaying) }

    func refresh() {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let scanned = scanAudioProcesses()
        processes = scanned

        var byOwner: [String: [AudioProcess]] = [:]
        for process in scanned {
            guard let owner = owningBundleID(of: process, among: apps) else { continue }
            byOwner[owner, default: []].append(process)
        }

        sources = apps.compactMap { app -> Source? in
            guard let bundleID = app.bundleIdentifier, let name = app.localizedName else { return nil }
            let mine = byOwner[bundleID] ?? []
            return Source(bundleID: bundleID,
                          name: name,
                          icon: app.icon,
                          isPlaying: mine.contains(where: \.isRunningOutput),
                          processes: mine)
        }
        .sorted {
            $0.isPlaying == $1.isPlaying
                ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                : $0.isPlaying
        }

        if selectedID == nil { selectedID = sources.first(where: \.isPlaying)?.id ?? sources.first?.id }
    }
}
