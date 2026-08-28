//
//  ExportCoordinator.swift
//  AppTape
//

import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

/// Runs one Export, non-blocking, and holds the state the inspector's Export control renders
/// (ADR-0012). It is the single place that owns the whole non-modal flow:
///
/// 1. **Save panel first** — the user picks the destination before any encoding starts.
/// 2. **Pre-flight** — a `statfs` byte-check on the *destination* volume refuses an over-large
///    Export before a byte is written (ADR-0009 is a Runway clock; this is deliberately not).
/// 3. **Encode to a sibling temp** in the destination directory, at `.utility` QoS so it cannot
///    preempt a live capture's IOProc, reporting real frame counts for a determinate bar.
/// 4. **Atomic swap** — `replaceItemAt:` finishes, so the chosen file is untouched until success.
///
/// It is **app-wide and one-at-a-time**: the running state *is* the Export button, so a second
/// Export has nowhere to present itself. Parameters are **snapshotted at launch** (`ExportRequest`),
/// so a later Trim or preset edit never reaches a running encode. Navigating away **cancels
/// unwarned** — the destination is untouched, so a cancel costs only redoable work.
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

    /// Which Recording the current telling belongs to. The inspector shows running/success/failure
    /// only when this matches the Recording on screen; every other selection reads idle.
    private(set) var subjectURL: URL?

    @ObservationIgnored private var encoder: ExportEncoder?
    /// Bumped on every launch and every cancel, so a completion handler from a superseded job is
    /// ignored rather than clobbering a newer state.
    @ObservationIgnored private var jobID = 0
    @ObservationIgnored private let queue = DispatchQueue(label: "com.apptape.export", qos: .utility)

    var isExporting: Bool { if case .running = phase { return true } else { return false } }

    /// The parameters an Export is launched with — snapshotted from the Recording at click, before
    /// the save panel, so a later Trim or preset edit never reaches the running encode (ADR-0012).
    /// A value carried as one thing rather than threaded as loose arguments; the chosen destination
    /// is the one piece that arrives later, from the panel.
    private struct Snapshot {
        let source: URL
        let name: String
        let startFrame: Int64
        let frameCount: Int64
        let preset: QualityPreset
        let estimatedBytes: Double
    }

    /// Starts an Export of `recording`'s Trim at `preset`. One at a time: a call while another
    /// Export runs is ignored. Presents the save panel, pre-flights, then encodes off the main
    /// thread. Snapshots every parameter now.
    func export(recording: Recording, preset: QualityPreset) {
        guard case .idle = phase else { return }

        let (startFrame, frameCount) = frameRange(for: recording)
        guard frameCount > 0 else {
            present(.failed(message: "There is nothing in the Trim to export."), for: recording.url)
            return
        }
        let snapshot = Snapshot(
            source: recording.url,
            name: recording.name,
            startFrame: startFrame,
            frameCount: frameCount,
            preset: preset,
            estimatedBytes: ExportSizeEstimate.bytes(preset: preset, format: recording.sourceFormat,
                                                     duration: recording.trimmedDuration))

        presentSavePanel(defaultName: snapshot.name) { [weak self] destination in
            guard let self, let destination else { return }
            self.begin(snapshot, destination: destination)
        }
    }

    /// Cancels a running Export and clears any telling back to idle. Used by the in-progress
    /// Cancel button, by navigating away (ADR-0012), and to dismiss a finished success/failure.
    /// The destination is left untouched: a running encode writes only to the sibling temp, which
    /// its own cancelled path discards.
    func cancel() {
        encoder?.cancel()
        encoder = nil
        jobID &+= 1
        phase = .idle
        subjectURL = nil
    }

    // MARK: - Launch

    private func begin(_ snapshot: Snapshot, destination: URL) {
        // Pre-flight the destination volume. Refuse rather than fill it (ADR-0012).
        let free = DiskSpace.freeBytes(forVolumeContaining: destination)
        guard DiskSpace.hasRoom(estimatedBytes: snapshot.estimatedBytes, freeBytes: free) else {
            let need = ExportSizeEstimate.sizeText(bytes: snapshot.estimatedBytes)
            let have = free.map { ExportSizeEstimate.sizeText(bytes: Double($0)) } ?? "less"
            fail(message: "Not enough space to export (needs about \(need), \(have) free).",
                 name: snapshot.name, for: snapshot.source)
            return
        }

        let temp = destination.deletingLastPathComponent()
            .appendingPathComponent(".apptape-export-\(UUID().uuidString).m4a")
        let request = ExportRequest(source: snapshot.source, destination: temp,
                                    startFrame: snapshot.startFrame, frameCount: snapshot.frameCount,
                                    preset: snapshot.preset)
        let name = snapshot.name

        let encoder = ExportEncoder()
        self.encoder = encoder
        jobID &+= 1
        let id = jobID
        subjectURL = snapshot.source
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
                if case .cancelled = failure { return }   // navigation/user cancel: no telling
                self?.hop { $0.finishFailed(failure.description, name: name, job: id) }
            } catch {
                try? FileManager.default.removeItem(at: temp)
                self?.hop { $0.finishFailed("\(error)", name: name, job: id) }
            }
        }
    }

    /// The atomic finish (ADR-0012): swap the temp into place with `replaceItemAt:` when a file is
    /// already there, or a plain move when the chosen name is new — both atomic renames within the
    /// destination directory, so the chosen file is never a partial write. Runs off-main.
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
        // Told louder: when not frontmost, also a notification (ADR-0012).
        if !NSApp.isActive {
            ExportNotifier.exportFailed(recordingName: name, detail: message)
        }
    }

    /// A pre-flight refusal, before any encode job exists. Tells in-window, and louder when the
    /// app is not frontmost.
    private func fail(message: String, name: String, for url: URL) {
        present(.failed(message: message), for: url)
        if !NSApp.isActive {
            ExportNotifier.exportFailed(recordingName: name, detail: message)
        }
    }

    private func present(_ phase: Phase, for url: URL) {
        jobID &+= 1
        subjectURL = url
        self.phase = phase
    }

    // MARK: - Helpers

    private func frameRange(for recording: Recording) -> (start: Int64, count: Int64) {
        let rate = recording.sampleRate
        guard rate > 0 else { return (0, 0) }
        let start = Int64((recording.trim.lowerBound * rate).rounded())
        let end = Int64((recording.trim.upperBound * rate).rounded())
        let clampedStart = max(0, min(start, recording.frameCount))
        let clampedEnd = max(clampedStart, min(end, recording.frameCount))
        return (clampedStart, clampedEnd - clampedStart)
    }

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
