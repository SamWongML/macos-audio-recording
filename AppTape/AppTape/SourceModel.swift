import AppKit
import CoreAudio
import Observation

/// Scans the live HAL process table and the workspace, and resolves them into the panel's list of
/// Sources (via the pure `SourceResolution`).
@MainActor
@Observable
final class SourceModel {
    /// Every `.regular` app as a Source: playing first, then alphabetical.
    private(set) var sources: [Source] = []
    /// Per-Source app icon, keyed by bundle ID — kept out of `Source` so the value type
    /// stays `Equatable`/`Hashable` and testable.
    private(set) var icons: [String: NSImage] = [:]

    func icon(for source: Source) -> NSImage? { icons[source.bundleID] }

    /// Icons drawn at a fixed point size, which is how a menu item and a borderless button draw
    /// one. Derived once per app and size.
    @ObservationIgnored private var sizedIcons: [String: NSImage] = [:]

    /// An app's icon at `size` points — a remembered Source that is not running included.
    func icon(forBundleID bundleID: String, size: CGFloat) -> NSImage? {
        let key = "\(bundleID)@\(size)"
        if let cached = sizedIcons[key] { return cached }
        guard let base = icons[bundleID] ?? installedIcon(bundleID),
            let sized = base.copy() as? NSImage
        else { return nil }
        sized.size = NSSize(width: size, height: size)
        sizedIcons[key] = sized
        return sized
    }

    /// Opens a remembered Source that is not running, the strip's recovery for it.
    func launch(_ choice: SourceChoice) {
        let workspace = NSWorkspace.shared
        guard let url = workspace.urlForApplication(withBundleIdentifier: choice.bundleID) else { return }
        workspace.openApplication(
            at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    private func installedIcon(_ bundleID: String) -> NSImage? {
        let workspace = NSWorkspace.shared
        guard let url = workspace.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return workspace.icon(forFile: url.path)
    }

    /// Re-reads the world. Cheap enough to call on a timer while the panel is open.
    func refresh() {
        // AppTape is a regular app too, and never its own Source.
        let this = ProcessInfo.processInfo.processIdentifier
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != this
        }
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
    /// shares the workspace snapshot `refresh` already took.
    private static func scanAudioProcesses(running: [NSRunningApplication]) -> [AudioProcess] {
        CAProperty.objectIDs(
            of: AudioObjectID(kAudioObjectSystemObject),
            kAudioHardwarePropertyProcessObjectList
        ).map { object in
            let pid = CAProperty.int32(of: object, kAudioProcessPropertyPID) ?? -1
            return AudioProcess(
                id: object,
                pid: pid,
                bundleID: CAProperty.string(of: object, kAudioProcessPropertyBundleID) ?? "",
                isRunningOutput: (CAProperty.uint32(of: object, kAudioProcessPropertyIsRunningOutput) ?? 0)
                    != 0,
                appName: running.first { $0.processIdentifier == pid }?.localizedName)
        }
    }
}
