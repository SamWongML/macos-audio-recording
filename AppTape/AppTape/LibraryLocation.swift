import Foundation

/// Where a Recording's master lands and what it is called.
nonisolated enum LibraryLocation {
    /// `~/Music/AppTape/`. Not created here — the directory is made lazily at the first
    /// frame, alongside the file, so an arm-then-never-play leaves no trace.
    static var directory: URL {
        let music =
            FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music")
        return music.appendingPathComponent("AppTape", isDirectory: true)
    }

    /// The base name (no extension) for a Recording, e.g. `Google Chrome 2026-08-27 at 20.05.03`.
    static func baseName(source: String, date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(sanitize(source)) \(formatter.string(from: date))"
    }

    /// A `.caf` filename that does not collide with anything `exists` reports, resolving a clash by
    /// appending ` 2`, ` 3`, … rather than overwriting — a master overwritten is unrecoverable.
    static func uniqueFileName(
        source: String,
        date: Date,
        timeZone: TimeZone = .current,
        exists: (String) -> Bool
    ) -> String {
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

// MARK: - Renaming

extension LibraryLocation {
    /// Why a name the user typed cannot become a Recording's filename.
    enum NameValidationError: Equatable {
        /// Empty, or nothing but whitespace.
        case empty
        /// `/` or `:` — the only two characters an APFS filename cannot hold.
        case illegalCharacter(Character)
        /// A leading dot.
        case wouldHide
        /// Another file in the Library already has this name.
        case alreadyTaken(String)
        /// The name was legal and free, but the move itself failed — a permissions problem, a
        /// read-only volume, a file that vanished between the check and the move.
        case diskRefused

        /// The one line the row's blocker popover shows. Written as the reason, not as an
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
        case refused(NameValidationError)
    }

    /// Resolve a rename.
    static func rename(
        _ currentFileName: String,
        to proposed: String,
        existingFileNames: [String]
    ) -> RenameOutcome {
        let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .refused(.empty) }
        if let illegal = trimmed.first(where: { $0 == "/" || $0 == ":" }) {
            return .refused(.illegalCharacter(illegal))
        }
        guard !trimmed.hasPrefix(".") else { return .refused(.wouldHide) }

        let ext = (currentFileName as NSString).pathExtension
        let newFileName = ext.isEmpty ? trimmed : "\(trimmed).\(ext)"
        guard newFileName != currentFileName else { return .unchanged }

        // Both comparisons are case-insensitive because the default APFS volume is.
        if let taken = existingFileNames.first(where: {
            $0.caseInsensitiveCompare(currentFileName) != .orderedSame
                && $0.caseInsensitiveCompare(newFileName) == .orderedSame
        }) {
            return .refused(.alreadyTaken(taken))
        }
        return .rename(to: newFileName)
    }

    /// Whether `baseName` still looks like a name this app generated at capture — the
    /// `baseName(source:date:)` pattern above, optionally carrying `uniqueFileName`'s ` 2` suffix.
    static func isGeneratedName(_ baseName: String) -> Bool {
        baseName.range(
            of: #"^.+ \d{4}-\d{2}-\d{2} at \d{2}\.\d{2}\.\d{2}( \d+)?$"#,
            options: .regularExpression) != nil
    }
}
