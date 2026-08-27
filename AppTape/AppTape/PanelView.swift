//
//  PanelView.swift
//  AppTape
//

import AppKit
import Combine
import SwiftUI

/// The hand-rolled panel's transport surface: the list *is* the panel and a row *is* the
/// record control — no button chrome (issue #6, variant H). Pressing a Source aims the tap
/// at its helper processes and starts a Recording; while one runs, the row shows it, and the
/// one-click stop lives on the status item itself (issue #8).
struct PanelView: View {
    /// Closes the popover — handed in by the `MenuBarController` that owns it.
    var dismiss: () -> Void

    @Environment(\.openWindow) private var openWindow
    @State private var model = SourceModel()
    private var recorder: RecordingController { .shared }
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            recoveryBanner
            sourceList
            Divider()
            footer
        }
        .frame(width: 280)
        .onAppear {
            // Capture the SwiftUI open-window action so a status-item stop-click can open the
            // editor from AppKit (EditorPresenter).
            EditorPresenter.shared.bind(openWindow)
            model.refresh()
        }
        .onReceive(tick) { _ in model.refresh() }
        // An unrelated key handler, exactly the kind a real control adds: it silently takes
        // the popover's free Escape away (ADR-0011), which is why the app owns Escape in
        // MenuBarController. Kept to hold that guarantee honest as the panel grows.
        .onKeyPress(.space) { .ignored }
    }

    // MARK: - Header

    @ViewBuilder private var header: some View {
        if recorder.isRecording {
            HStack(spacing: 8) {
                Circle().fill(.red).frame(width: 9, height: 9)
                Text(recordingName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text(recorder.elapsedText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        } else {
            Text("Record")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)
        }
    }

    private var recordingName: String {
        model.sources.first { $0.bundleID == recorder.recordingSourceID }?.name ?? "Recording"
    }

    // MARK: - Recovery banner

    /// Shown when a denied System Audio Recording grant was inferred (ADR-0008). It names
    /// "System Audio Recording Only" — not the pane's own broader heading — and the deep-link
    /// button lands on the audio-capture pane. Retry is not a button here: it is pressing record
    /// again, which is where the copy sends the user.
    @ViewBuilder private var recoveryBanner: some View {
        if recorder.permissionRecovery {
            VStack(alignment: .leading, spacing: 6) {
                Text(PermissionRecovery.title)
                    .font(.callout.weight(.semibold))
                Text(PermissionRecovery.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open System Settings") {
                    if let url = PermissionRecovery.settingsURL { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.link)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))
            Divider()
        }
    }

    // MARK: - Source list

    private var sourceList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if model.sources.isEmpty {
                    Text("No applications running.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                } else {
                    ForEach(model.sources) { source in
                        // A Source with no HAL clients yet cannot be aimed at by object ID, so
                        // pressing it could do nothing. Show it dimmed and inert rather than
                        // swallow the press silently.
                        let capturable = !source.processObjectIDs.isEmpty
                        SourceRow(source: source, icon: model.icon(for: source))
                            .opacity(capturable ? 1 : 0.4)
                            .contentShape(Rectangle())
                            .onTapGesture { if capturable { pick(source) } }
                        Divider().padding(.leading, 44)
                    }
                }
            }
        }
        .frame(maxHeight: 320)
    }

    /// While recording, the transport is busy: a press cannot start a second Recording (one
    /// Source at a time), so rows are inert until stop.
    private func pick(_ source: Source) {
        guard !recorder.isRecording else { return }
        recorder.start(source)
        dismiss()
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Open Editor") { openWindow(id: AppTapeApp.editorWindowID) }
                .buttonStyle(.link)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.link)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// One Source in the list: icon, name, and — when it is pushing audio out — a small dot, the
/// only signal the panel gives that a press will actually catch something (issue #6).
private struct SourceRow: View {
    let source: Source
    let icon: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let icon { Image(nsImage: icon).resizable() }
                else { Image(systemName: "app.dashed").resizable() }
            }
            .frame(width: 22, height: 22)

            Text(source.name)
                .font(.callout)
                .lineLimit(1)

            Spacer()

            if source.isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}
