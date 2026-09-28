import Foundation

/// The Source remembered for the next Record: its bundle identifier, and the name it had, so an app
/// that is no longer running can still be named.
struct SourceChoice: Equatable {
    var bundleID: String
    var name: String
}

extension SourceChoice {
    private static let bundleIDKey = "com.apptape.chosenSource.bundleID"
    private static let nameKey = "com.apptape.chosenSource.name"

    /// The choice `defaults` remembers, or nil before the first one.
    init?(defaults: UserDefaults) {
        guard let bundleID = defaults.string(forKey: Self.bundleIDKey), !bundleID.isEmpty else { return nil }
        self.init(bundleID: bundleID, name: defaults.string(forKey: Self.nameKey) ?? bundleID)
    }

    func save(to defaults: UserDefaults) {
        defaults.set(bundleID, forKey: Self.bundleIDKey)
        defaults.set(name, forKey: Self.nameKey)
    }
}

/// Whether the remembered Source can be recorded now, found among the running apps by its bundle
/// identifier and never replaced by another app.
enum SourceReadiness: Equatable {
    /// Nothing has been chosen yet.
    case unchosen
    /// The chosen app is not running.
    case notRunning(SourceChoice)
    /// The chosen app is running but has opened no audio for a tap to follow.
    case noAudioYet(Source)
    /// The chosen app can be recorded.
    case ready(Source)

    init(choice: SourceChoice?, among sources: [Source]) {
        guard let choice else {
            self = .unchosen
            return
        }
        guard let source = sources.first(where: { $0.bundleID == choice.bundleID }) else {
            self = .notRunning(choice)
            return
        }
        self = source.processObjectIDs.isEmpty ? .noAudioYet(source) : .ready(source)
    }
}
