//
//  ExportPreferenceTests.swift
//  AppTapeTests
//

import Testing
import Foundation
@testable import AppTape

/// The Quality Preset is sticky **app-wide** (issue #9): a choice about how to export, not a
/// property of any Recording, so it persists across launches in `UserDefaults`.
@MainActor
struct ExportPreferenceTests {
    private func scratchDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "apptape-tests-\(UUID().uuidString)")!
        return defaults
    }

    @Test func defaultsToHighWhenNothingIsStored() {
        let preference = ExportPreference(defaults: scratchDefaults())
        #expect(preference.preset == .high)
    }

    @Test func aChosenPresetSurvivesANewInstance() {
        let defaults = scratchDefaults()
        let first = ExportPreference(defaults: defaults)
        first.preset = .master

        // A fresh instance over the same defaults reads the sticky choice back.
        let second = ExportPreference(defaults: defaults)
        #expect(second.preset == .master)
    }

    @Test func aGarbageStoredValueFallsBackToTheDefault() {
        let defaults = scratchDefaults()
        defaults.set("nonsense", forKey: "com.apptape.exportPreset")
        #expect(ExportPreference(defaults: defaults).preset == .high)
    }

    // MARK: - Normalize toggle (ADR-0013): sticky app-wide, off on first use.

    @Test func normalizationIsOffOnFirstUse() {
        #expect(ExportPreference(defaults: scratchDefaults()).normalizeLoudness == false)
    }

    @Test func theNormalizeChoiceSurvivesANewInstance() {
        let defaults = scratchDefaults()
        let first = ExportPreference(defaults: defaults)
        first.normalizeLoudness = true

        let second = ExportPreference(defaults: defaults)
        #expect(second.normalizeLoudness == true)
    }
}
