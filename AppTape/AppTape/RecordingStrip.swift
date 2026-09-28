import AppKit
import Combine
import SwiftUI

/// The window's capture controls — the remembered Source, Record, what capture is doing and Stop —
/// floating above the editor, independent of the selected Recording.
struct RecordingStrip: View {
    /// The capture shell both surfaces command, handed over as it is to the helper's panel.
    var recorder: RecordingController
    /// The running apps the Source menu offers.
    var sources: SourceModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// App launches and quits change the Source menu and whether the remembered Source is running;
    /// audio starting inside an app is announced by nothing, so a slow poll notices that.
    private let launches = NSWorkspace.shared.notificationCenter.publisher(
        for: NSWorkspace.didLaunchApplicationNotification)
    private let terminations = NSWorkspace.shared.notificationCenter.publisher(
        for: NSWorkspace.didTerminateApplicationNotification)

    /// The bar's one-line height, and so its corner radius when a refusal takes two lines.
    private static let barHeight: Double = 40

    /// The point size every app icon in the strip and its menu is drawn at.
    private static let iconSize: Double = 18

    private var run: CaptureRun { recorder.run }

    private var readiness: SourceReadiness {
        SourceReadiness(choice: recorder.source, among: sources.sources)
    }

    var body: some View {
        let status = RecordingStripStatus(run: run, readiness: readiness)
        GlassEffectContainer(spacing: Metrics.sm) {
            HStack(spacing: Metrics.sm) {
                HStack(spacing: Metrics.md) {
                    sourceControl
                    Divider()
                        .frame(height: 18)
                    HStack(spacing: Metrics.sm) {
                        statusContent(status)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(run.isRecording ? 1 : 0)
                }
                .padding(.leading, Metrics.xs)
                .padding(.trailing, Metrics.md)
                .frame(minHeight: Self.barHeight)
                .glassEffect(.regular, in: .rect(cornerRadius: Self.barHeight / 2))

                recordButton(canRecord: status.canRecord)
            }
        }
        .padding(.horizontal, Metrics.lg)
        .padding(.top, Metrics.sm)
        .padding(.bottom, Metrics.xs)
        .task { await keepSourcesCurrent() }
        .onReceive(launches) { _ in sources.refresh() }
        .onReceive(terminations) { _ in sources.refresh() }
        .onChange(of: status.announcement) { _, announcement in
            if let announcement { AccessibilityNotification.Announcement(announcement).post() }
        }
    }

    // MARK: - Source

    /// The Source menu at rest; while a Recording runs, the Source it is capturing, fixed.
    @ViewBuilder
    private var sourceControl: some View {
        if run.isRecording {
            sourceLabel
                .padding(.horizontal, Metrics.sm)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Source")
                .accessibilityValue("\(recorder.source?.name ?? ""), fixed while recording")
                .help("The Source is fixed while recording")
        } else {
            Menu {
                sourceMenu
            } label: {
                sourceLabel
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.visible)
            .accessibilityLabel("Source")
            .accessibilityValue(recorder.source?.name ?? "None")
            .help("Choose the app to record")
        }
    }

    private var sourceLabel: some View {
        Label {
            Text(recorder.source?.name ?? String(localized: "Choose Source"))
                .fontWeight(.medium)
                .lineLimit(1)
        } icon: {
            icon(recorder.source?.bundleID)
        }
        .labelStyle(.titleAndIcon)
    }

    /// Every running app, playing first: choosing one only remembers it, and a remembered app that
    /// is not running stays listed, checked, so the choice is never silently replaced.
    @ViewBuilder
    private var sourceMenu: some View {
        let playing = sources.sources.filter(\.isPlaying)
        let others = sources.sources.filter { !$0.isPlaying }
        Picker("Source", selection: choice) {
            if case .notRunning(let remembered) = readiness {
                sourceItem(bundleID: remembered.bundleID, name: remembered.name, detail: "Not running")
            }
            if !playing.isEmpty {
                Section("Playing") {
                    ForEach(playing) { source in
                        sourceItem(bundleID: source.bundleID, name: source.name, detail: nil)
                    }
                }
            }
            if !others.isEmpty {
                Section("Other Apps") {
                    ForEach(others) { source in
                        sourceItem(
                            bundleID: source.bundleID, name: source.name,
                            detail: source.processObjectIDs.isEmpty ? "No audio yet" : nil)
                    }
                }
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }

    private func sourceItem(bundleID: String, name: String, detail: LocalizedStringKey?) -> some View {
        Label {
            Text(name)
            if let detail { Text(detail) }
        } icon: {
            icon(bundleID)
        }
        .labelStyle(.titleAndIcon)
        .tag(Optional(bundleID))
    }

    @ViewBuilder
    private func icon(_ bundleID: String?) -> some View {
        if let bundleID, let icon = sources.icon(forBundleID: bundleID, size: Self.iconSize) {
            Image(nsImage: icon)
        } else {
            Image(systemName: "app.dashed")
        }
    }

    private var choice: Binding<String?> {
        Binding(
            get: { recorder.source?.bundleID },
            set: { bundleID in
                guard let source = sources.sources.first(where: { $0.bundleID == bundleID }) else { return }
                recorder.choose(source)
            })
    }

    // MARK: - Status

    @ViewBuilder
    private func statusContent(_ status: RecordingStripStatus) -> some View {
        switch status {
        case .unchosen, .ready:
            // The menu's own label asks for a Source, and an empty Library's detail says so too.
            hint("Recording begins at the first sound")
        case .notRunning(let choice):
            warning("\(choice.name) isn’t running")
            Button("Open \(choice.name)") { sources.launch(choice) }
                .buttonStyle(.link)
                .fixedSize()
        case .noAudioYet(let source):
            Image(systemName: "speaker.slash")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            hint("\(source.name) hasn’t played audio yet — start it playing, then press Record")
                .help("Start playback in \(source.name) once, then press Record.")
        case .refusedForSpace(let blocker):
            refusal(title: blocker.title, message: blocker.message, action: "Show in Finder") {
                FaultNotifier.revealLibrary()
            }
        case .permissionDenied:
            refusal(
                title: PermissionRecovery.title, message: PermissionRecovery.message,
                action: "Open System Settings"
            ) {
                if let url = PermissionRecovery.settingsURL { NSWorkspace.shared.open(url) }
            }
        case .waitingForAudio:
            // Hollow until the first sound, and no clock: a zero timer would read as a fault.
            Image(systemName: "circle.dashed")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Waiting for audio")
                .fontWeight(.semibold)
                .lineLimit(1)
                .fixedSize()
            hint("Recording begins at the first sound")
        case .recording(let lowRunway):
            Image(systemName: "circle.fill")
                .foregroundStyle(lowRunway ? Color.orange : Color.red)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                .accessibilityHidden(true)
            Text("Recording")
                .fontWeight(.semibold)
                .lineLimit(1)
                .fixedSize()
            StripElapsed(run: run)
            StripMeter(run: run)
            if lowRunway { warning("Disk space running low") }
        }
    }

    private func hint(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    /// A warning's colour belongs to its mark, not to its sentence.
    private func warning(_ text: LocalizedStringKey) -> some View {
        Label {
            Text(text)
                .lineLimit(1)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        .labelStyle(.titleAndIcon)
    }

    /// The last press's refusal, in the strip rather than the helper's panel: the reason, and the one
    /// action that fixes it. Pressing Record again is the retry.
    @ViewBuilder
    private func refusal(
        title: String, message: String, action: LocalizedStringKey, perform: @escaping () -> Void
    ) -> some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .fontWeight(.semibold)
                .lineLimit(1)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Metrics.xs)
        .help(message)
        Spacer(minLength: Metrics.sm)
        Button(action, action: perform)
            .buttonStyle(.link)
            .fixedSize()
    }

    // MARK: - Record and Stop

    /// Live capture's one control, red where playback's transport is not.
    private func recordButton(canRecord: Bool) -> some View {
        let isRecording = run.isRecording
        return Button {
            if isRecording {
                recorder.stop(from: .window)
            } else {
                // Rescanned at the press, so the tap follows the Source's processes as they are now.
                sources.refresh()
                recorder.record(among: sources.sources, from: .window)
            }
        } label: {
            Group {
                if isRecording {
                    Label("Stop", systemImage: "stop.fill")
                } else {
                    Label("Record", systemImage: "circle.fill")
                }
            }
            .fontWeight(.semibold)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, Metrics.xs)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.extraLarge)
        .tint(.red)
        .fixedSize()
        .disabled(!isRecording && !canRecord)
        .keyboardShortcut("r", modifiers: .command)
        .help(isRecording ? "Stop Recording (⌘R)" : "Record (⌘R)")
        .accessibilityLabel(isRecording ? "Stop Recording" : "Record")
    }

    /// Rescans the running apps while the strip is on screen and nothing is being captured.
    private func keepSourcesCurrent() async {
        while !Task.isCancelled {
            if !run.isRecording { sources.refresh() }
            try? await Task.sleep(for: .seconds(2))
        }
    }
}

/// The master's length so far, on the run's 4 Hz clock — its own view, so the tick redraws only it.
private struct StripElapsed: View {
    var run: CaptureRun

    var body: some View {
        Text(run.elapsedText)
            .fontWeight(.semibold)
            .monospacedDigit()
            .fixedSize()
            .accessibilityLabel("Elapsed")
            .accessibilityValue(run.elapsedText)
    }
}

/// The live level at the meter's 20 Hz — its own view for the same reason.
private struct StripMeter: View {
    var run: CaptureRun

    var body: some View {
        LevelMeterShape(fills: run.meterColumns)
            .fill(Color.red.opacity(0.85))
            .frame(width: 96, height: 18)
            .accessibilityHidden(true)
    }
}
