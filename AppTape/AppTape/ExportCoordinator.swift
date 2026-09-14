import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

/// Runs one Export, non-blocking, and holds the state the inspector's Export control renders
///. It is the single place that owns the whole non-modal flow:
@MainActor
@Observable
final class ExportCoordinator {
    static let shared = ExportCoordinator()

    enum Phase: Equatable {
        case idle
        case running(fraction: Double)
        case succeeded(url: URL)
        case failed(message: String)
    }

    private(set) var phase: Phase = .idle

    /// Which Recording the current report belongs to — the object, not the path it had when
    /// the Export was launched.
    private var subject: Recording?

    /// Where the subject is now. The inspector shows running/success/failure only when this matches
    /// the Recording on screen; every other selection reads idle.
    var subjectURL: URL? { subject?.url }

    @ObservationIgnored private var encoder: ExportEncoder?
    /// Bumped on every launch and every cancel, so a completion handler from a superseded job is
    /// ignored rather than clobbering a newer state.
    @ObservationIgnored private var jobID = 0
    @ObservationIgnored private let queue = DispatchQueue(label: "com.apptape.export", qos: .utility)

    var isExporting: Bool { if case .running = phase { return true } else { return false } }

    #if DEBUG
        /// Park the coordinator in one phase, for a preview or a test.
        func enter(phase: Phase, subject: Recording?) {
            self.phase = phase
            self.subject = subject
        }
    #endif

    /// The parameters an Export is launched with — snapshotted from the Recording at click,
    /// before the save panel, so a later Trim or preset edit never reaches the running encode.
    private struct Snapshot {
        let source: URL
        let name: String
        let startFrame: Int64
        let frameCount: Int64
        let preset: QualityPreset
        let estimatedBytes: Double
        /// The Loudness and Gain settings, snapshotted at click like every other parameter
        /// (/-0013): the app-wide normalize toggle and this Recording's manual Gain.
        let normalize: Bool
        let gainDB: Double
    }

    /// Starts an Export of `recording`'s Trim at `preset`. Presents the save panel, pre-flights, then
    /// encodes off the main thread. Snapshots every parameter now.
    func export(recording: Recording, preset: QualityPreset, capture: any CaptureState) {
        // Not the one-at-a-time rule — that is `ExportReadiness`'s `.alreadyRunning`, below.
        guard case .idle = phase else { return }

        let (startFrame, frameCount) = recording.trimmedFrameRange
        // The belt-and-suspenders gate this comment has always claimed to be.
        if let reason = ExportReadiness.evaluate(
            isOpenable: recording.isOpenable,
            isCapturing: capture.isCapturing(recording),
            trimmedFrameCount: frameCount,
            preset: preset, format: recording.sourceFormat,
            isExporting: isExporting
        ).blocker {
            present(.failed(message: reason.sentence), for: recording)
            return
        }
        let snapshot = Snapshot(
            source: recording.url,
            name: recording.name,
            startFrame: startFrame,
            frameCount: frameCount,
            preset: preset,
            estimatedBytes: ExportSizeEstimate.bytes(
                preset: preset, format: recording.sourceFormat,
                duration: recording.trimmedDuration),
            normalize: ExportPreference.shared.normalizeLoudness,
            gainDB: recording.gain)

        presentSavePanel(defaultName: snapshot.name) { [weak self] destination in
            guard let self, let destination else { return }
            // The Recording rides alongside the snapshot rather than inside it: the snapshot is the
            // *encode's* parameters, frozen at click, and this is the report's subject, which is
            // the one thing that must stay live.
            self.begin(snapshot, subject: recording, destination: destination)
        }
    }

    /// Cancels a running Export and clears any report back to idle.
    func cancel() {
        encoder?.cancel()
        encoder = nil
        jobID &+= 1
        phase = .idle
        subject = nil
    }

    // MARK: - Launch

    private func begin(_ snapshot: Snapshot, subject: Recording, destination: URL) {
        // Pre-flight the destination volume. Refuse rather than fill it.
        let free = DiskSpace.freeBytes(forVolumeContaining: destination)
        guard DiskSpace.hasRoom(estimatedBytes: snapshot.estimatedBytes, freeBytes: free) else {
            let need = ExportSizeEstimate.sizeText(bytes: snapshot.estimatedBytes)
            let have = free.map { "\(ExportSizeEstimate.sizeText(bytes: Double($0))) free" } ?? "less free"
            // Two lines, and the two numbers are the payload. The failed phase renders inside
            // the Export dock's one declared height beside `Try Again…`, which leaves
            fail(
                message: "Not enough space: needs \(need), \(have).",
                name: snapshot.name, for: subject)
            return
        }

        let temp = destination.deletingLastPathComponent()
            .appendingPathComponent(".apptape-export-\(UUID().uuidString).m4a")
        let request = ExportRequest(
            source: snapshot.source, destination: temp,
            startFrame: snapshot.startFrame, frameCount: snapshot.frameCount,
            preset: snapshot.preset,
            normalize: snapshot.normalize, gainDB: snapshot.gainDB)
        let name = snapshot.name

        let encoder = ExportEncoder()
        self.encoder = encoder
        jobID &+= 1
        let id = jobID
        self.subject = subject
        phase = .running(fraction: 0)

        queue.async { [weak self] in
            do {
                try encoder.run(request) { fraction in
                    self?.hop { $0.updateProgress(fraction, job: id) }
                }
                try Self.commit(temp: temp, to: destination)
                self?.hop { $0.finishSucceeded(destination, job: id) }
            } catch let failure as ExportEncoder.Failure {
                try? FileManager.default.removeItem(at: temp)
                if case .cancelled = failure { return }  // navigation/user cancel: no reporter
                self?.hop { $0.finishFailed(failure.description, name: name, job: id) }
            } catch {
                try? FileManager.default.removeItem(at: temp)
                self?.hop { $0.finishFailed("\(error)", name: name, job: id) }
            }
        }
    }

    /// The atomic finish: swap the temp into place with `replaceItemAt:` when a file is already
    /// there, or a plain move when the chosen name is new — both atomic renames within the
    /// destination directory, so the chosen file is never a partial write.
    nonisolated static func commit(temp: URL, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: destination)
        }
    }

    // MARK: - Completions (main actor, guarded by job id)

    private func updateProgress(_ fraction: Double, job: Int) {
        guard job == jobID, case .running = phase else { return }
        phase = .running(fraction: min(max(fraction, 0), 1))
    }

    private func finishSucceeded(_ url: URL, job: Int) {
        guard job == jobID else { return }
        encoder = nil
        phase = .succeeded(url: url)
    }

    private func finishFailed(_ message: String, name: String, job: Int) {
        guard job == jobID else { return }
        encoder = nil
        phase = .failed(message: message)
        // Told louder: when not frontmost, also a notification.
        if !NSApp.isActive {
            FaultNotifier.exportFailed(recordingName: name, detail: message)
        }
    }

    /// A pre-flight blocker, before any encode job exists. Tells in-window, and louder when the
    /// app is not frontmost.
    private func fail(message: String, name: String, for recording: Recording) {
        present(.failed(message: message), for: recording)
        if !NSApp.isActive {
            FaultNotifier.exportFailed(recordingName: name, detail: message)
        }
    }

    private func present(_ phase: Phase, for recording: Recording) {
        jobID &+= 1
        subject = recording
        self.phase = phase
    }

    // MARK: - Helpers

    private func presentSavePanel(defaultName: String, completion: @escaping (URL?) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Audio]
        panel.nameFieldStringValue = "\(defaultName).m4a"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Export Recording"
        panel.prompt = "Export"
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            completion(response == .OK ? panel.url : nil)
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }

    /// Hop a completion onto the main actor. The closure receives `self` so its job-id guard runs
    /// on the actor that owns `jobID`.
    nonisolated private func hop(_ body: @escaping @Sendable @MainActor (ExportCoordinator) -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated { body(self) } }
    }
}
