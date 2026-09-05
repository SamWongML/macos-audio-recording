//
//  LibraryLocationTests.swift
//  AppTapeTests
//

import Testing
import Foundation
@testable import AppTape

/// The Library filename is the Recording's name, formed from the Source and the start time,
/// and a collision resolves by appending ` 2` rather than overwriting (ADR-0006).
struct LibraryLocationTests {
    // 2026-08-27 20:05:03 UTC, read in UTC so the test is timezone-independent.
    private let date = Date(timeIntervalSince1970: 1_787_861_103)
    private let utc = TimeZone(identifier: "UTC")!

    @Test func nameCarriesSourceDateAndTime() {
        #expect(LibraryLocation.baseName(source: "Google Chrome", date: date, timeZone: utc)
                == "Google Chrome 2026-08-27 at 20.05.03")
    }

    @Test func firstNameWinsWhenNothingCollides() {
        let name = LibraryLocation.uniqueFileName(source: "Safari", date: date, timeZone: utc) { _ in false }
        #expect(name == "Safari 2026-08-27 at 20.05.03.caf")
    }

    @Test func collisionAppendsTwo() {
        let taken = "Safari 2026-08-27 at 20.05.03.caf"
        let name = LibraryLocation.uniqueFileName(source: "Safari", date: date, timeZone: utc) { $0 == taken }
        #expect(name == "Safari 2026-08-27 at 20.05.03 2.caf")
    }

    @Test func secondCollisionAppendsThree() {
        let taken: Set = ["Safari 2026-08-27 at 20.05.03.caf", "Safari 2026-08-27 at 20.05.03 2.caf"]
        let name = LibraryLocation.uniqueFileName(source: "Safari", date: date, timeZone: utc) { taken.contains($0) }
        #expect(name == "Safari 2026-08-27 at 20.05.03 3.caf")
    }

    @Test func pathSeparatorsInSourceAreMadeLegal() {
        #expect(LibraryLocation.baseName(source: "Read/Write: Demo", date: date, timeZone: utc)
                == "Read-Write- Demo 2026-08-27 at 20.05.03")
    }

    @Test func directoryIsMusicAppTape() {
        #expect(LibraryLocation.directory.lastPathComponent == "AppTape")
        #expect(LibraryLocation.directory.deletingLastPathComponent().lastPathComponent == "Music")
    }
}

/// Renaming a Recording from inside the app (ADR-0020). The Library is an ordinary folder, so a
/// rename *is* a file rename — and unlike capture, which resolves a collision silently because
/// there is no one to ask, these rules **refuse rather than fix**.
struct LibraryRenameTests {
    private func rename(_ current: String, to proposed: String, existing: [String] = [])
        -> LibraryLocation.RenameOutcome {
        LibraryLocation.rename(current, to: proposed, existingFileNames: existing)
    }

    @Test func theExtensionIsCarriedOverNotEdited() {
        // An edited extension fails `Recording.init?`'s adoption gate and vanishes the Recording,
        // so the user only ever types the base name.
        #expect(rename("Google Chrome 2026-08-27 at 20.05.03.caf", to: "Interview")
                == .rename(to: "Interview.caf"))
    }

    @Test func anAdoptedFileKeepsItsOwnExtension() {
        #expect(rename("podcast.mp3", to: "Episode 12") == .rename(to: "Episode 12.mp3"))
    }

    @Test func theSameNameIsUnchangedNotARename() {
        #expect(rename("Interview.caf", to: "Interview") == .unchanged)
    }

    @Test func surroundingWhitespaceIsTrimmedRatherThanRefused() {
        // Not a violation of refuse-don't-fix: whitespace at the ends carries no meaning, so
        // trimming it changes nothing the user meant.
        #expect(rename("A.caf", to: "  Interview  ") == .rename(to: "Interview.caf"))
    }

    @Test func anEmptyNameIsRefused() {
        #expect(rename("A.caf", to: "") == .refused(.empty))
    }

    @Test func aWhitespaceOnlyNameIsRefused() {
        #expect(rename("A.caf", to: "   ") == .refused(.empty))
    }

    @Test(arguments: ["Read/Write", "Notes: draft"])
    func anIllegalCharacterIsRefused(_ proposed: String) {
        // `/` and `:` are the only two characters an APFS filename cannot hold. Capture folds them
        // to a hyphen because a Source name is not the user's to type; a name the user typed is.
        guard case .refused(.illegalCharacter) = rename("A.caf", to: proposed) else {
            Issue.record("expected an illegalCharacter refusal for \(proposed)")
            return
        }
    }

    @Test func aLeadingDotIsRefusedBecauseItWouldVanishTheRecording() {
        // `audioFiles(in:)` lists with `.skipsHiddenFiles`, so a dotted name would drop the
        // Recording out of the Library and close the editor on it — a rename that reads as a
        // deletion. This is the reason the case exists at all.
        #expect(rename("A.caf", to: ".hidden") == .refused(.wouldHide))
    }

    @Test func aCollisionIsRefusedNotSuffixed() {
        #expect(rename("A.caf", to: "B", existing: ["A.caf", "B.caf"])
                == .refused(.alreadyTaken("B.caf")))
    }

    @Test func aCollisionIsCaseInsensitiveBecauseTheVolumeIs() {
        #expect(rename("A.caf", to: "b", existing: ["A.caf", "B.caf"])
                == .refused(.alreadyTaken("B.caf")))
    }

    @Test func aCaseOnlyRenameIsNotACollisionWithItself() {
        // "podcast.caf" → "Podcast.caf" is the same file, so it cannot collide with itself. This
        // is why the current file is excluded from the collision scan case-insensitively.
        #expect(rename("podcast.caf", to: "Podcast", existing: ["podcast.caf"])
                == .rename(to: "Podcast.caf"))
    }

    @Test func aGeneratedNameIsRecognised() {
        #expect(LibraryLocation.isGeneratedName("Google Chrome 2026-08-27 at 20.05.03"))
    }

    @Test func aGeneratedNameCarryingTheCollisionSuffixIsStillRecognised() {
        #expect(LibraryLocation.isGeneratedName("Safari 2026-08-27 at 20.05.03 2"))
    }

    @Test(arguments: ["Interview", "Google Chrome", "Standup 2026-08-27", "Chrome 2026-08-27 at 20.05"])
    func aNameTheUserChoseIsNotAGeneratedName(_ name: String) {
        #expect(!LibraryLocation.isGeneratedName(name))
    }
}
