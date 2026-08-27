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
