//
//  DiskGuardRefusal.swift
//  AppTape
//

import Foundation

/// The panel's blocking message when a start is refused below the 2 GB floor (ADR-0009). It reuses
/// the message surface ADR-0008 introduced for a denied grant — the panel carries at most one
/// blocking reason at a time — naming the free space and the floor, and its action opens Finder at
/// the Library rather than a Settings deep link, there being no pane to send the user to.
///
/// Kept beside `PermissionRecovery` as the panel's other pinned copy, so the exact figures and the
/// load-bearing wording are held by a test rather than buried in a view.
struct DiskGuardRefusal: Equatable {
    /// Free space at the moment of refusal, so the copy can name the exact figure the user sees in
    /// Finder.
    let freeBytes: Int64

    var title: String { "Not enough disk space to record" }

    /// Names the free space and the 2 GB floor, and ends on the retry — which is simply pressing
    /// record again, as the denial banner does. "Free space" and "floor" are the refusal's own
    /// bytes-and-floor language, which ADR-0009 sanctions here (the Runway *clock* is never spoken as
    /// free bytes, but the floor a start is refused against is a byte count and named as one).
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
