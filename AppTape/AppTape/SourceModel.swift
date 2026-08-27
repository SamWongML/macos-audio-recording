//
//  SourceModel.swift
//  AppTape
//

import AppKit
import CoreAudio
import Observation

/// Scans the live HAL process table and the workspace, and resolves them into the panel's
/// list of Sources (via the pure `SourceResolution`). Icons are attached here, at the
/// AppKit edge, so the resolution itself stays a pure function.
@MainActor
@Observable
final class SourceModel {
    /// Every `.regular` app as a Source: playing first, then alphabetical.
    private(set) var sources: [Source] = []
    /// Per-Source app icon, keyed by bundle ID — kept out of `Source` so the value type
    /// stays `Equatable`/`Hashable` and testable.
    private(set) var icons: [String: NSImage] = [:]

    func icon(for source: Source) -> NSImage? { icons[source.bundleID] }

    /// Re-reads the world. Cheap enough to call on a timer while the panel is open.
    func refresh() {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let apps = running.compactMap { app -> RunningApp? in
            guard let bundleID = app.bundleIdentifier, let name = app.localizedName else { return nil }
            return RunningApp(bundleID: bundleID, name: name)
        }
        sources = SourceResolution.sources(from: Self.scanAudioProcesses(running: running), apps: apps)

        var icons: [String: NSImage] = [:]
        for app in running {
            if let bundleID = app.bundleIdentifier, let icon = app.icon { icons[bundleID] = icon }
        }
        self.icons = icons
    }

    /// The raw HAL client table. `running` is threaded in so the localized-name lookup
    /// shares the workspace snapshot `refresh()` already took.
    private static func scanAudioProcesses(running: [NSRunningApplication]) -> [AudioProcess] {
        CAProperty.objectIDs(of: AudioObjectID(kAudioObjectSystemObject),
                             kAudioHardwarePropertyProcessObjectList).map { object in
            let pid = CAProperty.int32(of: object, kAudioProcessPropertyPID) ?? -1
            return AudioProcess(
                id: object,
                pid: pid,
                bundleID: CAProperty.string(of: object, kAudioProcessPropertyBundleID) ?? "",
                isRunningOutput: (CAProperty.uint32(of: object, kAudioProcessPropertyIsRunningOutput) ?? 0) != 0,
                appName: running.first { $0.processIdentifier == pid }?.localizedName)
        }
    }
}
