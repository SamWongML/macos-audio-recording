//  PROTOTYPE — throwaway. Menu bar host for the three source-picker variants.
//  Three variants of the Source picker on the real MenuBarExtra surface, switchable
//  from the bar at the bottom of the panel (or the ← / → keys).

import Combine

extension String {
    func appendToFile(_ path: String) throws {
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile(); handle.write(data(using: .utf8)!); handle.closeFile()
        } else {
            try write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
import SwiftUI

enum Variant: String, CaseIterable, Identifiable {
    case a, b, c, d, e, f, g
    var id: String { rawValue }
    var key: String { rawValue.uppercased() }
    var title: String {
        switch self {
        case .a: VariantA.title
        case .b: VariantB.title
        case .c: VariantC.title
        case .d: VariantD.title
        case .e: VariantE.title
        case .f: VariantF.title
        case .g: VariantG.title
        }
    }
    var next: Variant { Self.allCases[(Self.allCases.firstIndex(of: self)! + 1) % Self.allCases.count] }
    var previous: Variant { Self.allCases[(Self.allCases.firstIndex(of: self)! + Self.allCases.count - 1) % Self.allCases.count] }
}

@main
struct SourcePickerPrototypeApp: App {
    @State private var model = SourceModel()
    @State private var variant = Variant(rawValue: ProcessInfo.processInfo.environment["VARIANT"] ?? "a") ?? .a
    @State private var showsEvidence = false

    /// Fast enough that a video starting in Chrome shows up while the panel is open.
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    /// PROBE=1 exercises the tap path headlessly, from app launch — the scene's own timer
    /// cannot do this, because MenuBarExtra content is not built until the panel opens.
    init() {
        let argv = CommandLine.arguments
        if ProcessInfo.processInfo.environment["PROBE"] == "2" || argv.contains("probe-global") {
            // Global tap: if this reads zero too, the problem is the permission, not the
            // process list we are targeting.
            Task.detached(priority: .userInitiated) {
                let tap = SourceTap(processes: [], name: "global", global: true)
                for _ in 0..<12 {
                    try? await Task.sleep(for: .seconds(1))
                    let peak = tap.ring.snapshot().max() ?? 0
                    let line = "GLOBAL peak=\(String(format: "%.4f", peak)) failure=\(tap.failure ?? "none")\n"
                    FileHandle.standardError.write(line.data(using: .utf8)!)
                    try? line.appendToFile("/tmp/global.log")
                }
            }
            return
        }
        guard ProcessInfo.processInfo.environment["PROBE"] == "1" || argv.contains("probe") else { return }
        let probeModel = SourceModel()
        let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
            MainActor.assumeIsolated {
                probeModel.refresh()
                LevelMonitor.shared.sync(with: probeModel.sources)
                var line = "PROBE \(probeModel.playing.count) playing / \(probeModel.sources.count) apps"
                for source in probeModel.playing {
                    let peak = LevelMonitor.shared.ring(for: source.bundleID)?.snapshot().max()
                    line += " | \(source.name): peak=\(peak.map { String(format: "%.3f", $0) } ?? "-") level=\(String(format: "%.3f", LevelMonitor.shared.levels[source.bundleID] ?? -1)) \(LevelMonitor.shared.failures[source.bundleID] ?? "")"
                }
                FileHandle.standardError.write((line + "\n").data(using: .utf8)!)
                try? (line + "\n").appendToFile("/tmp/probe.log")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    var body: some Scene {
        MenuBarExtra("Source Picker Prototype", systemImage: "waveform.badge.magnifyingglass") {
            VStack(spacing: 0) {
                switch variant {
                case .a: VariantA(model: model)
                case .b: VariantB(model: model)
                case .c: VariantC(model: model)
                case .d: VariantD(model: model)
                case .e: VariantE(model: model)
                case .f: VariantF(model: model)
                case .g: VariantG(model: model)
                }

                if showsEvidence { evidence }
                switcher
            }
            .onAppear { model.refresh() }
            .onReceive(tick) { _ in
                model.refresh()
            }
        }
        .menuBarExtraStyle(.window)
    }

    /// The raw HAL table the design is reacting to. Not part of any variant —
    /// it is here so the claims in the ticket can be checked against live data.
    private var evidence: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            Text("\(model.processes.count) HAL clients · \(model.processes.filter(\.isRunningOutput).count) playing")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.processes.sorted { $0.isRunningOutput && !$1.isRunningOutput }) { process in
                        HStack(spacing: 5) {
                            Text(process.isRunningOutput ? "▶" : "·")
                                .foregroundStyle(process.isRunningOutput ? Color.accentColor : Color.secondary.opacity(0.5))
                            Text(process.bundleID.isEmpty ? "(no bundle ID)" : process.bundleID)
                            Spacer(minLength: 4)
                            Text(process.appName ?? "no NSRunningApplication")
                                .foregroundStyle(process.appName == nil ? Color.red.opacity(0.8) : .secondary)
                        }
                        .font(.system(size: 9, design: .monospaced))
                        .lineLimit(1)
                    }
                }
                .padding(.horizontal, 10)
            }
            .frame(height: 150)
        }
    }

    /// Deliberately ugly: this bar is scaffolding, not part of any design being judged.
    private var switcher: some View {
        HStack(spacing: 8) {
            Button { variant = variant.previous } label: { Image(systemName: "chevron.left") }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Text("\(variant.key) — \(variant.title)")
                .font(.caption.monospaced())
                .frame(maxWidth: .infinity)
            Button { variant = variant.next } label: { Image(systemName: "chevron.right") }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button { showsEvidence.toggle() } label: { Image(systemName: "tablecells") }
                .help("Show the raw Core Audio process table")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "xmark") }
                .keyboardShortcut("q")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(8)
        .background(.black.opacity(0.85))
        .foregroundStyle(.white)
    }
}
