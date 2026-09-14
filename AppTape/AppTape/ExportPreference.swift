import Foundation
import Observation

/// The chosen Quality Preset, sticky app-wide: it is a preference about how the user wants to
/// export, not a property of any one Recording, so it lives here rather than in an xattr.
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

    /// Whether Export normalizes Loudness.
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
