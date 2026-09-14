import CoreAudio

/// One HAL client process, straight out of `kAudioHardwarePropertyProcessObjectList`.
struct AudioProcess: Identifiable, Hashable {
    var id: AudioObjectID
    var pid: pid_t
    var bundleID: String
    var isRunningOutput: Bool
    /// `NSRunningApplication.localizedName`, when the OS admits one exists — often the only
    /// thread back to the owning app for a WebKit GPU process, whose bundle ID
    /// (`com.apple.WebKit.GPU`) names no app.
    var appName: String?
}

/// A running `.regular` application, reduced to what Source resolution needs.
struct RunningApp: Hashable {
    var bundleID: String
    var name: String
}

/// A user-facing application the user can choose to capture.
struct Source: Identifiable, Hashable {
    var id: String { bundleID }
    var bundleID: String
    var name: String
    /// True when any process belonging to this Source is pushing audio out right now.
    var isPlaying: Bool
    /// The object IDs of the HAL clients this Source resolves to — what the tap is aimed at.
    var processObjectIDs: [AudioObjectID]
}

/// The pure mapping from raw HAL processes onto the apps a user would name.
enum SourceResolution {
    /// Maps a HAL client's bundle ID back to the app a user would name, or `nil` if it
    /// belongs to no visible `.regular` app.
    static func owningBundleID(of process: AudioProcess, among apps: [RunningApp]) -> String? {
        if process.bundleID == "com.apple.WebKit.GPU" {
            guard let name = process.appName else { return nil }
            let owner = name.replacingOccurrences(of: " Graphics and Media", with: "")
            return apps.first { $0.name == owner }?.bundleID
        }
        // Longest matching prefix wins, so `com.google.Chrome.helper` picks Chrome, not some
        // shorter `com.google` if one ever existed.
        return
            apps
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
            return Source(
                bundleID: app.bundleID,
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
