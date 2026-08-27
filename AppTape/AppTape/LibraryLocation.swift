//
//  LibraryLocation.swift
//  AppTape
//

import Foundation

/// Where a Recording's master lands and what it is called. The Library is the ordinary
/// visible folder `~/Music/AppTape/` (ADR-0006); a Recording's **filename is its name**,
/// formed from the Source and the **start** time, and the master is written in place at its
/// final path from the first sample — never temp-then-moved (ADR-0006).
///
/// The naming and collision rules are pure functions over injected inputs so they can be
/// tested without a clock, a timezone, or the disk.
enum LibraryLocation {
    /// `~/Music/AppTape/`. Not created here — the directory is made lazily at the first
    /// frame, alongside the file, so an arm-then-never-play leaves no trace (ADR-0016).
    static var directory: URL {
        let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music")
        return music.appendingPathComponent("AppTape", isDirectory: true)
    }

    /// The base name (no extension) for a Recording, e.g. `Google Chrome 2026-08-27 at 20.05.03`.
    /// Time is dotted, not colon-separated, so it is a legal filename; the Source is
    /// sanitized of path separators for the same reason.
    static func baseName(source: String, date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(sanitize(source)) \(formatter.string(from: date))"
    }

    /// A `.caf` filename that does not collide with anything `exists` reports, resolving a
    /// clash by appending ` 2`, ` 3`, … rather than overwriting — a master overwritten is
    /// unrecoverable (ADR-0006). Collisions cannot arise in practice (one Source, second
    /// resolution), so this is a safety net, not a hot path.
    static func uniqueFileName(source: String,
                               date: Date,
                               timeZone: TimeZone = .current,
                               exists: (String) -> Bool) -> String {
        let base = baseName(source: source, date: date, timeZone: timeZone)
        let first = "\(base).caf"
        guard exists(first) else { return first }
        var suffix = 2
        while exists("\(base) \(suffix).caf") { suffix += 1 }
        return "\(base) \(suffix).caf"
    }

    /// Path separators and colons are the only characters illegal in an HFS+/APFS
    /// filename; fold them to a hyphen so any Source name yields a legal file.
    private static func sanitize(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }
}
