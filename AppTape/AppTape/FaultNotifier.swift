//
//  FaultNotifier.swift
//  AppTape
//

import AppKit
import Foundation
import UserNotifications

/// The four unrequested ends share ADR-0009's notification channel, and each names its reason
/// (ADR-0010). The reason is named because the four ask different things of the user — free up
/// space, nothing, nothing, start again — and a generic "Recording stopped" would make them open
/// the app to find out which. Clicking the notification opens the editor on that Recording; **when
/// authorization is absent the editor opens directly instead**, without a permission prompt stacked
/// onto a failure (the mistake ADR-0009 avoided by keeping the request off the audio grant).
enum FaultNotifier {
    /// The Recording URL carried in a notification's `userInfo`, read back on click to open the editor.
    static let openEditorURLKey = "com.apptape.fault.recordingURL"

    /// Marks the 30-minute Runway warning, whose click opens Finder at the Library rather than the
    /// editor — the Recording is still running, and freeing space is the only action it asks for.
    static let revealLibraryKey = "com.apptape.fault.revealLibrary"

    /// Requested at the end of the first *completed* Recording (ADR-0009), so a later unrequested end
    /// has a channel — never at a fault, and never as a prompt the user did not invite. Once only.
    @MainActor private static var didRequestAuthorization = false

    @MainActor
    static func requestAuthorizationOnce() {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Tell the user a Recording ended for a reason they did not choose. Posts a notification when
    /// authorized; opens the editor directly when not (ADR-0010). No-op for the two requested ends.
    static func recordingEnded(reason: RecordingEndReason, recordingURL: URL) {
        guard reason.isUnrequested, let body = reason.notificationBody else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                let content = UNMutableNotificationContent()
                content.title = reason.notificationTitle
                content.body = body
                content.sound = .default
                content.userInfo = [openEditorURLKey: recordingURL.absoluteString]
                let request = UNNotificationRequest(identifier: UUID().uuidString,
                                                    content: content, trigger: nil)
                center.add(request)
            case .denied, .notDetermined:
                fallthrough
            @unknown default:
                // No channel: open the editor on that Recording so the unwarned stop is not silent.
                Task { @MainActor in EditorPresenter.shared.open(selecting: recordingURL) }
            }
        }
    }

    /// The 30-minute Runway warning (ADR-0009): posted once when the guard crosses 30 minutes,
    /// telling the user to free space — the only action the warning asks for. Unlike an end it opens
    /// nothing while it goes unheard, because the Recording is still running; so when authorization is
    /// absent there is simply no channel and nothing shows, and amber and the floor still stand.
    /// Authorization is never requested here — that stays at the end of the first completed Recording
    /// (ADR-0009), so a warning during the very first Recording may find no channel yet, by design.
    static func runwayLow() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                // Time-framed to match the Recording's Runway (ADR-0009) and parallel to the
                // `.diskGuard` end's own copy ("Recording stopped" / "Your disk is almost full…"):
                // the title is what happens, the body names the disk and the one action it asks for.
                let content = UNMutableNotificationContent()
                content.title = "Recording will stop soon"
                content.body = "Your disk is almost full. Free up space to keep recording."
                content.sound = .default
                content.userInfo = [revealLibraryKey: true]
                let request = UNNotificationRequest(identifier: UUID().uuidString,
                                                    content: content, trigger: nil)
                center.add(request)
            case .denied, .notDetermined:
                fallthrough
            @unknown default:
                break
            }
        }
    }

    /// Reveal the Library in Finder — the action both the refusal and the warning offer (ADR-0009),
    /// there being no Settings pane to send the user to. Selects the folder when it exists, else opens
    /// its parent, since the Library is created lazily at the first sound.
    @MainActor
    static func revealLibrary() {
        let library = LibraryLocation.directory
        if FileManager.default.fileExists(atPath: library.path) {
            NSWorkspace.shared.activateFileViewerSelecting([library])
        } else {
            NSWorkspace.shared.open(library.deletingLastPathComponent())
        }
    }
}

/// Routes a click on a fault notification back to the editor. Set as the notification centre's
/// delegate at launch. A single shared object, like the other shell pieces.
final class FaultNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = FaultNotificationDelegate()

    /// Show the banner even when the app is frontmost, so a fault end is never swallowed.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// The click: open the editor on the Recording the notification named (ADR-0010), or — for the
    /// 30-minute Runway warning — reveal the Library in Finder so the user can free space (ADR-0009).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        if userInfo[FaultNotifier.revealLibraryKey] != nil {
            await MainActor.run { FaultNotifier.revealLibrary() }
            return
        }
        guard let raw = userInfo[FaultNotifier.openEditorURLKey] as? String,
              let url = URL(string: raw) else { return }
        await MainActor.run { EditorPresenter.shared.open(selecting: url) }
    }
}
