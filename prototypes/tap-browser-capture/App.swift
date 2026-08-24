//  PROTOTYPE — throwaway. Answers issue #12. Not production code: no tests, no error
//  handling, no abstractions worth keeping.
//
//  This is not a design prototype — there is no UI question here and no state model to
//  feel out. It is an instrument. The window exists so a human can drive real browsers
//  while the tap is watched, and every control either aims the tap, perturbs the system,
//  or writes down what the human just did.

import AppKit
import SwiftUI

@main
struct TapProbeApp: App {
    @State private var model = ProbeModel()

    var body: some Scene {
        Window("AppTape tap probe — issue #12", id: "probe") {
            ProbeView(model: model)
                .frame(minWidth: 1080, minHeight: 720)
                .task { model.begin() }
        }
        .defaultSize(width: 1180, height: 820)
    }
}

// MARK: - Root

struct ProbeView: View {
    @Bindable var model: ProbeModel

    var body: some View {
        VStack(spacing: 0) {
            ControlBar(model: model)
            Divider()
            ReadoutBar(model: model)
            Divider()
            HSplitView {
                ScenarioList(model: model).frame(minWidth: 320, idealWidth: 380)
                ProcessTable(model: model).frame(minWidth: 380)
            }
            .frame(minHeight: 240)
            Divider()
            LogView(model: model).frame(minHeight: 220)
        }
    }
}

// MARK: - Aiming the tap

struct ControlBar: View {
    @Bindable var model: ProbeModel

    /// The bundle IDs worth trying, and why each one is a distinct question.
    private static let presets: [(String, String)] = [
        ("Chrome (the app)", "com.google.Chrome"),
        ("Chrome (the helper)", "com.google.Chrome.helper"),
        ("Safari (the app)", "com.apple.Safari"),
        ("WebKit GPU (shared!)", "com.apple.WebKit.GPU"),
        ("Music", "com.apple.Music"),
        ("QuickTime Player", "com.apple.QuickTimePlayerX"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Strategy", selection: $model.strategy) {
                    ForEach(TapStrategy.allCases) { Text($0.label).tag($0) }
                }
                .frame(maxWidth: 420)
                .disabled(model.run != nil)

                Toggle("processRestoreEnabled", isOn: $model.processRestoreEnabled)
                    .disabled(model.run != nil)

                Spacer()

                Button("Start", action: model.start).disabled(model.run != nil).keyboardShortcut(.return)
                Button("Stop", action: model.stop).disabled(model.run == nil)
                Button("Recreate tap", action: model.recreate).disabled(model.run == nil)
            }

            HStack {
                TextField("Bundle IDs, comma separated", text: $model.bundleIDText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.run != nil)
                    .frame(maxWidth: 420)
                Menu("Presets") {
                    ForEach(Self.presets, id: \.1) { preset in
                        Button(preset.0) { model.bundleIDText = preset.1 }
                    }
                }
                .frame(width: 110)
                .disabled(model.run != nil)

                Text(model.strategy.usesBundleIDs
                     ? "Aiming by bundle ID — the thing under test."
                     : model.strategy == .globalControl
                       ? "Control: taps everything, ignores the bundle IDs."
                       : "Baseline: enumerates matching helper processes by hand and taps their object IDs.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(12)
    }
}

// MARK: - What the tap is doing

struct ReadoutBar: View {
    @Bindable var model: ProbeModel

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.status)
                    .font(.headline)
                    .foregroundStyle(model.run?.failure != nil ? .red : .primary)
                Text(model.run?.lastKnownFormat.map(describe) ?? "no tap")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 340, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(min(model.level, 1)))
                    .frame(width: 180)
                Text(String(format: "peak %.4f", model.level))
                    .font(.system(.caption, design: .monospaced))
            }

            Text("""
                 callbacks \(model.lastSnapshot.callbacks)   frames \(model.lastSnapshot.frames)
                 non-zero \(model.lastSnapshot.nonZeroBuffers)   zero \(model.lastSnapshot.zeroBuffers)
                 """)
                .font(.system(.caption, design: .monospaced))

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("Output device \(Int(model.outputRate)) Hz").font(.callout)
                HStack(spacing: 6) {
                    ForEach(model.availableRates, id: \.self) { rate in
                        Button("\(Int(rate))") { model.setRate(rate) }
                            .disabled(rate == model.outputRate)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - The run sheet

/// The scenario from the ticket, as buttons. Each one stamps the log, so the log reads
/// back as a narrative instead of an undated wall of numbers.
struct ScenarioList: View {
    @Bindable var model: ProbeModel
    @State private var note = ""
    @State private var done: Set<String> = []

    private static let steps = [
        "Chrome: play a YouTube video",
        "Chrome: switch to a different tab and back",
        "Chrome: open a NEW tab and play audio in it",
        "Chrome: let the video end, start a different one",
        "Chrome: quit Chrome entirely",
        "Chrome: relaunch Chrome and play audio (processRestoreEnabled)",
        "Safari: play a Bilibili video",
        "Safari: open a new tab and play audio in it",
        "Change the system output device (headphones in/out)",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Scenario — click when you have just done it")
                .font(.headline).padding(12)
            List {
                ForEach(Self.steps, id: \.self) { step in
                    HStack {
                        Image(systemName: done.contains(step) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(done.contains(step) ? .green : .secondary)
                        Text(step).font(.callout)
                        Spacer()
                    }
                    .contentShape(.rect)
                    .onTapGesture {
                        done.insert(step)
                        model.mark(step)
                    }
                }
            }
            HStack {
                TextField("…or type what you just did", text: $note)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { stamp() }
                Button("Mark", action: stamp).disabled(note.isEmpty)
            }
            .padding(12)
        }
    }

    private func stamp() {
        guard !note.isEmpty else { return }
        model.mark(note)
        note = ""
    }
}

// MARK: - The evidence

struct ProcessTable: View {
    @Bindable var model: ProbeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("HAL process table — highlighted rows match the bundle IDs above")
                .font(.headline).padding(12)
            Table(model.processes) {
                TableColumn("out") { Text($0.isRunningOutput ? "●" : "").foregroundStyle(.green) }
                    .width(24)
                TableColumn("pid") { Text("\($0.pid)").monospaced() }.width(56)
                TableColumn("bundle ID") { process in
                    Text(process.bundleID.isEmpty ? "—" : process.bundleID)
                        .monospaced()
                        .fontWeight(model.isTargeted(process) ? .bold : .regular)
                        .foregroundStyle(model.isTargeted(process) ? Color.accentColor : .primary)
                }
                TableColumn("NSRunningApplication") { Text($0.appName ?? "—").foregroundStyle(.secondary) }
            }
        }
    }
}

struct LogView: View {
    @Bindable var model: ProbeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Log").font(.headline)
                Spacer()
                Text(model.logPath).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: model.logPath)])
                }
            }
            .padding(12)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(model.logLines.suffix(400).enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(colour(for: line))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 12)
                }
                .onChange(of: model.logLines.count) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private func colour(for line: String) -> Color {
        if line.contains("MARK") { return .orange }
        if line.contains("<<<") || line.contains("FAILED") || line.contains("STALL") { return .red }
        if line.contains("EVENT") { return .primary }
        return .secondary
    }
}
