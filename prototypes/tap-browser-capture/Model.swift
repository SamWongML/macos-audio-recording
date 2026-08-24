//  PROTOTYPE — throwaway. The heartbeat: once a second, write down what the tap did, what
//  the HAL process table looks like, and whether the two disagree.
//
//  That disagreement is the instrument the ticket actually needs. An all-zero tap is
//  indistinguishable from genuine silence *unless* you also know that the process you are
//  tapping is reporting `kAudioProcessPropertyIsRunningOutput`. Cross-checking the two is
//  what turns "I heard nothing" into "the tap is broken".

import AppKit
import CoreAudio
import Observation
import SwiftUI

@MainActor
@Observable
final class ProbeModel {
    // Configuration
    var strategy: TapStrategy = .bundleIDsOnMixdownInit
    var bundleIDText = "com.google.Chrome"
    var processRestoreEnabled = true

    // Live state
    private(set) var run: TapRun?
    private(set) var processes: [AudioProcess] = []
    private(set) var logLines: [String] = []
    private(set) var level: Float = 0
    private(set) var lastSnapshot = CounterSnapshot()
    private(set) var outputRate: Double = 0
    private(set) var availableRates: [Double] = []
    private(set) var status = "idle"

    var bundleIDs: [String] {
        bundleIDText.split(whereSeparator: { ", \n".contains($0) }).map(String.init).filter { !$0.isEmpty }
    }

    // Tick bookkeeping
    private var previous = CounterSnapshot()
    private var lastNonZero: Date?
    private var stallReported = false
    private var previousProcesses: [AudioObjectID: AudioProcess] = [:]
    private var ticker: Timer?

    var logPath: String { ProbeLog.shared.path }

    // MARK: - Lifecycle

    /// `--strategy=<case> --ids=a,b --auto` starts a run without anyone clicking, so a
    /// scenario can be replayed from a shell after the grant exists.
    func applyLaunchArguments() {
        for argument in CommandLine.arguments {
            if let value = argument.split(separator: "=", maxSplits: 1).last,
               argument.hasPrefix("--strategy="),
               let parsed = TapStrategy(rawValue: String(value)) {
                strategy = parsed
            }
            if argument.hasPrefix("--ids=") {
                bundleIDText = String(argument.dropFirst("--ids=".count))
            }
            if argument == "--no-restore" { processRestoreEnabled = false }
        }
    }

    func begin() {
        applyLaunchArguments()
        refreshDevice()
        refreshProcesses(logDiff: false)
        ProbeLog.shared.event("probe.ready logFile=\(ProbeLog.shared.path)")
        if CommandLine.arguments.contains("--auto") { start() }
        runScriptIfRequested()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    /// `--script=perturb` walks the two perturbations from the ticket on a timer — flip the
    /// output device's sample rate away and back, then destroy and rebuild everything —
    /// so the run needs nobody at the keyboard and lands the same way every time.
    private func runScriptIfRequested() {
        guard CommandLine.arguments.contains("--script=perturb") else { return }
        let original = outputRate
        schedule(15) {
            guard let other = self.availableRates.first(where: { $0 != original }) else {
                self.mark("SCRIPT: no second sample rate available on this device"); return
            }
            self.setRate(other)
        }
        schedule(28) { self.setRate(original) }
        schedule(41) { self.recreate() }
        schedule(54) { self.mark("SCRIPT complete") }
    }

    private func schedule(_ seconds: Double, _ action: @escaping @MainActor () -> Void) {
        let timer = Timer(timeInterval: seconds, repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: - Tap control

    func start() {
        guard run == nil else { return }
        let strategy = self.strategy
        let ids = bundleIDs
        let restore = processRestoreEnabled
        // Every process object whose bundle ID is, or hangs off, one of the target IDs.
        // Only the baseline strategy uses this — and gathering it by hand is precisely the
        // work `bundleIDs` is supposed to abolish.
        let objects = processes.filter { matchesTarget($0, ids: ids) }.map(\.id)
        status = "starting…"
        ProbeLog.shared.mark("START  \(strategy.label)  ids=\(ids)  restore=\(restore)")

        // Off the main thread: this blocks, and it is where the TCC prompt appears.
        Task.detached(priority: .userInitiated) {
            let run = TapRun(strategy: strategy, bundleIDs: ids, processObjects: objects,
                             processRestoreEnabled: restore)
            await MainActor.run {
                self.run = run
                self.previous = run.snapshot()
                self.lastNonZero = nil
                self.stallReported = false
                self.status = run.failure ?? "running"
            }
        }
    }

    func stop() {
        guard let run else { return }
        ProbeLog.shared.mark("STOP")
        run.stop()
        self.run = nil
        status = "idle"
        level = 0
    }

    /// Destroy and rebuild everything — the recovery the ticket asks about after a
    /// sample-rate change.
    func recreate() {
        guard run != nil else { return }
        ProbeLog.shared.mark("RECREATE tap + aggregate device")
        run?.stop()
        run = nil
        start()
    }

    // MARK: - Sample rate

    func refreshDevice() {
        let device = defaultOutputDevice()
        outputRate = nominalSampleRate(of: device) ?? 0
        availableRates = availableSampleRates(of: device).filter { $0 >= 44100 && $0 <= 96000 }
    }

    func setRate(_ rate: Double) {
        let device = defaultOutputDevice()
        ProbeLog.shared.mark("SET OUTPUT RATE \(Int(outputRate)) -> \(Int(rate)) Hz")
        let status = setNominalSampleRate(of: device, to: rate)
        ProbeLog.shared.event("output.setRate status=\(status)")
        refreshDevice()
    }

    func mark(_ text: String) { ProbeLog.shared.mark(text) }

    // MARK: - Matching

    /// The prefix rule from the source-picker prototype: `com.google.Chrome.helper` hangs
    /// off `com.google.Chrome`. Used only to decide what the *table* highlights and what
    /// the baseline strategy enumerates — never to aim a bundle-ID tap, which is the
    /// thing under test.
    private func matchesTarget(_ process: AudioProcess, ids: [String]) -> Bool {
        ids.contains { process.bundleID == $0 || process.bundleID.hasPrefix($0 + ".") }
    }

    func isTargeted(_ process: AudioProcess) -> Bool {
        strategy == .globalControl || matchesTarget(process, ids: bundleIDs)
    }

    // MARK: - The heartbeat

    private func tick() {
        refreshProcesses(logDiff: true)

        let device = defaultOutputDevice()
        if let rate = nominalSampleRate(of: device), rate != outputRate {
            ProbeLog.shared.event("output.rate changed \(Int(outputRate)) -> \(Int(rate))   <<< CHANGED")
            outputRate = rate
            availableRates = availableSampleRates(of: device).filter { $0 >= 44100 && $0 <= 96000 }
        }

        guard let run else { logLines = ProbeLog.shared.snapshot(); return }

        let now = run.snapshot()
        let callbacks = now.callbacks - previous.callbacks
        let frames = now.frames - previous.frames
        let zero = now.zeroBuffers - previous.zeroBuffers
        let nonZero = now.nonZeroBuffers - previous.nonZeroBuffers
        previous = now
        lastSnapshot = now

        let peak = run.counters.takePeak()
        level = peak

        // Does the OS think the thing we are tapping is producing audio right now?
        let targetsOut = processes.filter { isTargeted($0) && $0.isRunningOutput }
        let targetSummary = targetsOut.isEmpty
            ? "targetOut=no"
            : "targetOut=yes(\(targetsOut.map { "pid \($0.pid)" }.joined(separator: ",")))"

        ProbeLog.shared.tick(String(format: "peak=%.4f callbacks=%d frames=%d nonZeroBuf=%d zeroBuf=%d lastList=%dx%dB %@",
                                    peak, callbacks, frames, nonZero, zero,
                                    now.lastBufferCount, now.lastBytesPerBuffer, targetSummary))

        if nonZero > 0 {
            if lastNonZero == nil { ProbeLog.shared.event("signal.first  <<< THE TAP IS CAPTURING AUDIO") }
            if stallReported { ProbeLog.shared.event("signal.recovered  <<< audio came back on its own") }
            lastNonZero = Date()
            stallReported = false
        }

        // The IOProc not being called at all is a different failure from it being called
        // with zeros, and the ticket needs them told apart.
        if callbacks == 0 && run.isRunning {
            ProbeLog.shared.event("ioproc.starved  no callbacks in the last second  <<< DEVICE STOPPED")
        }

        // The silent all-zero failure: we are being handed buffers, the OS says the target
        // is producing output, and every sample is zero.
        if !stallReported, callbacks > 0, nonZero == 0, !targetsOut.isEmpty {
            let quietFor = lastNonZero.map { Date().timeIntervalSince($0) } ?? Double(zero) / max(1, Double(callbacks))
            if lastNonZero == nil || quietFor > 4 {
                ProbeLog.shared.event("STALL  all-zero buffers while \(targetsOut.count) targeted process(es) report isRunningOutput=Y  <<< THE SILENT FAILURE")
                stallReported = true
            }
        }

        logLines = ProbeLog.shared.snapshot()
    }

    private func refreshProcesses(logDiff: Bool) {
        let scanned = scanAudioProcesses()
        if logDiff {
            let current = Dictionary(uniqueKeysWithValues: scanned.map { ($0.id, $0) })
            for (id, process) in current where previousProcesses[id] == nil {
                ProbeLog.shared.event("proc.added   \(process.line)")
            }
            for (id, process) in previousProcesses where current[id] == nil {
                ProbeLog.shared.event("proc.removed \(process.line)")
            }
            for (id, process) in current {
                if let was = previousProcesses[id], was.isRunningOutput != process.isRunningOutput {
                    ProbeLog.shared.event("proc.output  \(process.isRunningOutput ? "started" : "stopped") \(process.line)")
                }
            }
            previousProcesses = current
        } else {
            previousProcesses = Dictionary(uniqueKeysWithValues: scanned.map { ($0.id, $0) })
            for process in scanned { ProbeLog.shared.event("proc.initial \(process.line)") }
        }
        processes = scanned
    }
}
