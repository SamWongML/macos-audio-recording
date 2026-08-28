//
//  ExportNotifier.swift
//  AppTape
//

import Foundation
import UserNotifications

/// A failed Export is told **louder** than a success (ADR-0012): in-window always, and — when the
/// app is **not frontmost** — also as a system notification, because a silent failure at second 40
/// while the user is in another app is the one outcome that must not be missable. Where notification
/// authorization was denied the in-window telling still carries it, so this is strictly additive and
/// entirely best-effort: nothing here ever affects whether the export itself is reported.
enum ExportNotifier {
    /// Posts a failure notification for `recordingName`. No-op-safe: it requests authorization
    /// lazily and swallows every error, since the inspector has already told the story in-window.
    static func exportFailed(recordingName: String, detail: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Export failed"
            content.body = "Couldn’t export “\(recordingName).” \(detail)"
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString,
                                                content: content, trigger: nil)
            center.add(request)
        }
    }
}
