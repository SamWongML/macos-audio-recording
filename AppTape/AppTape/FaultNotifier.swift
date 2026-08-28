//
//  FaultNotifier.swift
//  AppTape
//

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

    /// The click: open the editor on the Recording the notification named (ADR-0010).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let raw = response.notification.request.content.userInfo[FaultNotifier.openEditorURLKey] as? String,
              let url = URL(string: raw) else { return }
        await MainActor.run { EditorPresenter.shared.open(selecting: url) }
    }
}
