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

    var preset: QualityPreset {
        didSet {
            guard preset != oldValue else { return }
            defaults.set(preset.rawValue, forKey: Self.key)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Injectable defaults so a test can drive stickiness without touching the real domain.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.key).flatMap(QualityPreset.init(rawValue:))
        self.preset = stored ?? .defaultPreset
    }
}
