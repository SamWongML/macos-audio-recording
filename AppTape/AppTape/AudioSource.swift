//
//  AudioSource.swift
//  AppTape
//

import CoreAudio

/// One HAL client process, straight out of `kAudioHardwarePropertyProcessObjectList`.
/// The tap is aimed at these **by object ID** (`id`), never by bundle ID: `bundleIDs`
/// resolves app bundles only and misses WebKit's XPC audio service, which is half the
/// reason this app exists (ADR-0001, issue #12).
struct AudioProcess: Identifiable, Hashable {
    var id: AudioObjectID
    var pid: pid_t
    var bundleID: String
    var isRunningOutput: Bool
    /// `NSRunningApplication.localizedName`, when the OS admits one exists — often the
    /// only thread back to the owning app for a WebKit GPU process, whose bundle ID
    /// (`com.apple.WebKit.GPU`) names no app.
    var appName: String?
}

/// A running `.regular` application, reduced to what Source resolution needs. An
/// abstraction over `NSRunningApplication` so the mapping is a pure function testable
/// without a live workspace.
struct RunningApp: Hashable {
    var bundleID: String
    var name: String
}

/// A user-facing application the user can choose to capture. One Source fans out to the
/// helper processes that own its real HAL clients — Chrome's audio service, WebKit's GPU
/// process — mapped back up onto the visible app (ADR-0001).
struct Source: Identifiable, Hashable {
    var id: String { bundleID }
    var bundleID: String
    var name: String
    /// True when any process belonging to this Source is pushing audio out right now.
    var isPlaying: Bool
    /// The object IDs of the HAL clients this Source resolves to — what the tap is aimed
    /// at. Empty means the app is running but has not touched Core Audio yet, so there is
    /// nothing to tap until it does.
    var processObjectIDs: [AudioObjectID]
}

/// The pure mapping from raw HAL processes onto the apps a user would name. No Core Audio,
/// no AppKit — the whole resolution is a function of its inputs, so it is unit-tested
/// directly (issue #6's heuristics, promoted out of the prototype).
enum SourceResolution {
    /// Maps a HAL client's bundle ID back to the app a user would name, or `nil` if it
    /// belongs to no visible `.regular` app.
    ///
    /// The plain prefix rule (`com.google.Chrome.helper` → `com.google.Chrome`) covers
    /// Chrome and other helper-bundle apps. WebKit is the exception the rule cannot reach:
    /// every WebKit client's audio runs through `com.apple.WebKit.GPU`, whose bundle ID
    /// says nothing about who owns it — only its localized name ("Safari Graphics and
    /// Media") does.
    static func owningBundleID(of process: AudioProcess, among apps: [RunningApp]) -> String? {
        if process.bundleID == "com.apple.WebKit.GPU" {
            guard let name = process.appName else { return nil }
            let owner = name.replacingOccurrences(of: " Graphics and Media", with: "")
            return apps.first { $0.name == owner }?.bundleID
        }
        // Longest matching prefix wins, so `com.google.Chrome.helper` picks Chrome, not
        // some shorter `com.google` if one ever existed.
        return apps
            .map(\.bundleID)
            .filter { process.bundleID == $0 || process.bundleID.hasPrefix($0 + ".") }
            .max { $0.count < $1.count }
    }

    /// Every `.regular` app as a Source, each fanned out to its owning processes: playing
    /// first, then alphabetical by name (the panel's order).
    static func sources(from processes: [AudioProcess], apps: [RunningApp]) -> [Source] {
        var byOwner: [String: [AudioProcess]] = [:]
        for process in processes {
            guard let owner = owningBundleID(of: process, among: apps) else { continue }
            byOwner[owner, default: []].append(process)
        }

        return apps.map { app -> Source in
            let mine = byOwner[app.bundleID] ?? []
            return Source(bundleID: app.bundleID,
                          name: app.name,
                          isPlaying: mine.contains(where: \.isRunningOutput),
                          processObjectIDs: mine.map(\.id))
        }
        .sorted {
            $0.isPlaying == $1.isPlaying
                ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                : $0.isPlaying
        }
    }
}
