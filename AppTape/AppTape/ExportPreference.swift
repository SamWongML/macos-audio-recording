//
//  ExportPreference.swift
//  AppTape
//

import Foundation
import Observation

/// The chosen Quality Preset, sticky **app-wide** (issue #9): it is a preference about how the
/// user wants to export, not a property of any one Recording, so it lives here rather than in an
/// xattr. Backed by `UserDefaults` so it survives a relaunch, and `@Observable` so the inspector's
/// subtitle and size estimate follow a change immediately. A singleton because every editor open
/// shares the one preference.
@MainActor
@Observable
final class ExportPreference {
    static let shared = ExportPreference()

    private static let key = "com.apptape.exportPreset"
    private static let normalizeKey = "com.apptape.normalizeLoudness"

    var preset: QualityPreset {
        didSet {
            guard preset != oldValue else { return }
            defaults.set(preset.rawValue, forKey: Self.key)
        }
    }

    /// Whether Export normalizes Loudness (ADR-0013). Like the preset, it is a preference about *how*
    /// the user exports rather than a property of any one Recording — the shape of the Quality Preset,
    /// not a per-Recording value like Gain and Trim — so it is sticky **app-wide** and **off on first
    /// use**. Backed by `UserDefaults` so it survives a relaunch.
    var normalizeLoudness: Bool {
        didSet {
            guard normalizeLoudness != oldValue else { return }
            defaults.set(normalizeLoudness, forKey: Self.normalizeKey)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Injectable defaults so a test can drive stickiness without touching the real domain.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.key).flatMap(QualityPreset.init(rawValue:))
        self.preset = stored ?? .defaultPreset
        self.normalizeLoudness = defaults.bool(forKey: Self.normalizeKey)   // absent → false (off)
    }
}
