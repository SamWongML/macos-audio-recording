import Foundation

/// The Export pre-flight: before a byte is written, the estimate is compared against the free space
/// on the destination volume — which can be any volume, not the Library's, so this is a
/// `statfs` on the destination, deliberately a byte comparison and not a Runway clock.
enum DiskSpace {
    /// Free bytes on the volume containing `url`, via `statfs`.
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
    /// free space. makes this a plain byte comparison, not a Runway clock — the only slack is
    /// the estimate's own stated ±3.5% band, so the check demands the estimate rounded up by that
    /// band and nothing more (no invented floor: numeric policy beyond the estimate's error would
    /// be an ADR-worthy decision this ticket does not make).
    static func hasRoom(estimatedBytes: Double, freeBytes: Int64?) -> Bool {
        guard let freeBytes else { return true }
        guard estimatedBytes.isFinite, estimatedBytes > 0 else { return true }
        return Double(freeBytes) >= estimatedBytes * marginMultiplier
    }

    /// The estimate's own ±3.5% error band: a low estimate against a nearly-full volume
    /// is refused rather than allowed to slip into an `ENOSPC` mid-encode.
    static let marginMultiplier = 1.035

    /// Free bytes on the volume that would hold `url`, after resolving symlinks — the Runway
    /// guard's read.
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

    /// Free bytes on the Library's volume, resolving symlinks. The one input the Runway
    /// guard polls every 5 s.
    static func freeBytesForLibraryVolume() -> Int64? {
        freeBytes(forVolumeHolding: LibraryLocation.directory)
    }
}
