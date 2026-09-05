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

// MARK: - Renaming (ADR-0020)

extension LibraryLocation {
    /// Why a name the user typed cannot become a Recording's filename. ADR-0020 **refuses rather
    /// than fixes**: there is a human here to ask, and quietly turning the "Interview" they typed
    /// into "Interview 2" is a lie about what they asked for. (Capture has no human to ask, which
    /// is why `uniqueFileName` above resolves a clash silently instead — the same question, a
    /// different answer, for the reason ADR-0006 gives.)
    enum NameRefusal: Equatable {
        /// Empty, or nothing but whitespace.
        case empty
        /// `/` or `:` — the only two characters an APFS filename cannot hold.
        case illegalCharacter(Character)
        /// A leading dot. Not merely unconventional: `audioFiles(in:)` lists with
        /// `.skipsHiddenFiles`, so a dotted name would drop the Recording out of the Library
        /// entirely and close the editor on it — a rename that reads as a deletion.
        case wouldHide
        /// Another file in the Library already has this name.
        case alreadyTaken(String)
        /// The name was legal and free, but the move itself failed — a permissions problem, a
        /// read-only volume, a file that vanished between the check and the move.
        case diskRefused

        /// The one line the row's refusal popover shows. Written as the reason, not as an
        /// instruction: the field is still open and still focused, so what to do next is evident.
        var message: String {
            switch self {
            case .empty:
                "A Recording needs a name."
            case .illegalCharacter(let character):
                "A name can't contain \"\(character)\"."
            case .wouldHide:
                "A name can't begin with a dot — the Library wouldn't show it."
            case .alreadyTaken(let name):
                "\"\((name as NSString).deletingPathExtension)\" is already in the Library."
            case .diskRefused:
                "The file couldn't be renamed."
            }
        }
    }

    /// What renaming `currentFileName` to `proposed` should do. Pure over its inputs — the caller
    /// supplies the folder's filenames — so every rule below is tested without the disk.
    enum RenameOutcome: Equatable {
        /// The name resolved to the file's existing one. Nothing to write.
        case unchanged
        /// Rename the file to this full filename, extension included.
        case rename(to: String)
        case refused(NameRefusal)
    }

    /// Resolve a rename. `proposed` is the **base name** the user typed — the extension is never
    /// theirs to edit (ADR-0020: an edited extension fails `Recording.init?`'s adoption gate and
    /// vanishes the Recording, the same failure as a leading dot), so it is carried over from
    /// `currentFileName` unchanged.
    ///
    /// Leading and trailing whitespace is trimmed rather than refused. That is not a violation of
    /// refuse-don't-fix: whitespace at the ends carries no meaning, so trimming it changes nothing
    /// the user meant, where suffixing a collision or dropping a character would.
    static func rename(_ currentFileName: String,
                       to proposed: String,
                       existingFileNames: [String]) -> RenameOutcome {
        let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .refused(.empty) }
        if let illegal = trimmed.first(where: { $0 == "/" || $0 == ":" }) {
            return .refused(.illegalCharacter(illegal))
        }
        guard !trimmed.hasPrefix(".") else { return .refused(.wouldHide) }

        let ext = (currentFileName as NSString).pathExtension
        let newFileName = ext.isEmpty ? trimmed : "\(trimmed).\(ext)"
        guard newFileName != currentFileName else { return .unchanged }

        // Both comparisons are case-insensitive because the default APFS volume is. Excluding the
        // current file case-insensitively is what lets a **case-only** rename through
        // ("podcast.caf" → "Podcast.caf"): it is the same file, so it cannot collide with itself.
        if let taken = existingFileNames.first(where: {
            $0.caseInsensitiveCompare(currentFileName) != .orderedSame
                && $0.caseInsensitiveCompare(newFileName) == .orderedSame
        }) {
            return .refused(.alreadyTaken(taken))
        }
        return .rename(to: newFileName)
    }

    /// Whether `baseName` still looks like a name **this app generated at capture** — the
    /// `baseName(source:date:)` pattern above, optionally carrying `uniqueFileName`'s ` 2` suffix.
    ///
    /// This is the predicate behind ADR-0020's display rule: while it holds, the Library shows the
    /// Recording's Source, because the filename says nothing the row isn't already showing; once
    /// the user has named the file themselves it stops holding, and the Library shows their name.
    static func isGeneratedName(_ baseName: String) -> Bool {
        baseName.range(of: #"^.+ \d{4}-\d{2}-\d{2} at \d{2}\.\d{2}\.\d{2}( \d+)?$"#,
                       options: .regularExpression) != nil
    }
}
