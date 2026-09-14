import Foundation

/// The panel's blocking message when a start is refused below the 2 GB floor.
struct DiskGuardBlocker: Equatable {
    /// Free space at the moment of blocker, so the copy can name the exact figure the user sees in
    /// Finder.
    let freeBytes: Int64

    var title: String { "Not enough disk space to record" }

    /// Names the free space and the 2 GB floor, and ends on the retry — which is simply pressing
    /// record again, as the denial banner does.
    var message: String {
        "Only \(Self.formatted(freeBytes)) is free. AppTape keeps a "
            + "\(Self.formatted(RunwayGuard.floorBytes)) floor so a recording can’t fill your disk. "
            + "Free up space, then press record again."
    }

    /// Decimal (1000-based) bytes, matching Finder and the floor's own decimal 2 GB.
    static func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
