//
//  DiskSpace.swift
//  AppTape
//

import Foundation

/// The Export pre-flight (ADR-0012): before a byte is written, the estimate is compared against
/// the free space on the **destination** volume — which can be any volume, not the Library's, so
/// this is a `statfs` on the destination, deliberately a **byte comparison and not a Runway
/// clock** (ADR-0009). Export is bounded work of known size; the argument that sent capture to a
/// time unit does not apply. This turns the ugliest failure — the disk filling mid-encode, leaving
/// a partial temp and an unclear message — into a refusal that names the problem up front.
enum DiskSpace {
    /// Free bytes on the volume containing `url`, via `statfs`. `url` need not exist yet — the
    /// save panel hands back a not-yet-created path — so this stats the containing directory,
    /// which does. Nil when even that cannot be stat'd, which the caller treats as "cannot verify"
    /// rather than "no space".
    static func freeBytes(forVolumeContaining url: URL) -> Int64? {
        let directory = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        var info = statfs()
        let ok = directory.withUnsafeFileSystemRepresentation { path -> Bool in
            path != nil && statfs(path, &info) == 0
        }
        guard ok else { return nil }
        return Int64(info.f_bavail) * Int64(info.f_bsize)
    }

    /// Whether an export estimated at `estimatedBytes` should be allowed against `freeBytes` of
    /// free space. ADR-0012 makes this a **plain byte comparison**, not a Runway clock — the only
    /// slack is the estimate's own stated ±3.5% band, so the check demands the estimate rounded up
    /// by that band and nothing more (no invented floor: numeric policy beyond the estimate's
    /// error would be an ADR-worthy decision this ticket does not make). `freeBytes == nil` (could
    /// not stat) returns `true` — an unverifiable volume is not refused, and a genuine `ENOSPC`
    /// slipping past the band still surfaces as a plain failure with the temp discarded (ADR-0012).
    static func hasRoom(estimatedBytes: Double, freeBytes: Int64?) -> Bool {
        guard let freeBytes else { return true }
        guard estimatedBytes.isFinite, estimatedBytes > 0 else { return true }
        return Double(freeBytes) >= estimatedBytes * marginMultiplier
    }

    /// The estimate's own ±3.5% error band (ADR-0012): a low estimate against a nearly-full volume
    /// is refused rather than allowed to slip into an `ENOSPC` mid-encode.
    static let marginMultiplier = 1.035

    /// Free bytes on the volume that would hold `url`, **after resolving symlinks** — the Runway
    /// guard's read (ADR-0009). Two things separate it from `freeBytes(forVolumeContaining:)`: it
    /// resolves the path so a Library symlinked onto an external volume measures *that* volume, not
    /// the boot disk; and it climbs to the nearest existing ancestor, because the Library folder is
    /// created lazily at the first sound and a not-yet-created path cannot be stat'd. Nil only when
    /// even the root cannot be stat'd, which the caller treats as "cannot verify" — never as "no
    /// space" — so an unverifiable volume never ends a Recording.
    static func freeBytes(forVolumeHolding url: URL) -> Int64? {
        var directory = url.resolvingSymlinksInPath()
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        while !(fm.fileExists(atPath: directory.path, isDirectory: &isDirectory) && isDirectory.boolValue) {
            let parent = directory.deletingLastPathComponent()
            if parent == directory { break }   // reached the root without finding one
            directory = parent
        }
        return freeBytes(forVolumeContaining: directory)
    }

    /// Free bytes on the Library's volume, resolving symlinks (ADR-0009). The one input the Runway
    /// guard polls every 5 s.
    static func freeBytesForLibraryVolume() -> Int64? {
        freeBytes(forVolumeHolding: LibraryLocation.directory)
    }
}
