//  PROTOTYPE — throwaway. Variants D and E, both built on B's spine ("the list is the
//  panel"), each answering the two things B got wrong: it never commits to a Record
//  affordance, and its `All` toggle lies when nothing is playing.

import SwiftUI

// MARK: - The per-row live indicator

/// Three capsules that move while the Source is pushing audio.
///
/// Honest about what it is: this is a *motion* indicator, not a meter. Real per-process
/// amplitude requires an installed tap, which requires the TCC grant — so nothing here
/// can show true loudness until a Recording is running. The bars say "audio is coming
/// out of this app right now", which is the only claim the process list supports.
struct LevelBars: View {
    var isPlaying: Bool
    var height: CGFloat = 13
    var barCount: Int = 3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isPlaying && !reduceMotion {
            TimelineView(.animation) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                bars { index in 0.3 + 0.7 * abs(sin(time * 3.2 + Double(index) * 1.15)) }
            }
        } else {
            // Reduce Motion, and the silent state, both degrade to a static glyph.
            bars { _ in isPlaying ? 0.75 : 0.3 }
        }
    }

    private func bars(_ scale: @escaping (Int) -> Double) -> some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule().frame(width: 2.5, height: height * scale(index))
            }
        }
        .frame(width: CGFloat(barCount) * 4.5, height: height)
        .foregroundStyle(isPlaying ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
    }
}

/// The empty state B was missing. When `All` is off and nothing is playing, say so —
/// do not silently widen the list and leave the header claiming "Playing Audio".
struct NothingPlaying: View {
    var onShowAll: (() -> Void)?
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "speaker.slash")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text("No app is playing audio")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let onShowAll {
                Button("Show All Apps", action: onShowAll)
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }
}

private struct SourceRow: View {
    var source: Source
    var isSelected: Bool
    var body: some View {
        HStack(spacing: 10) {
            AppIcon(source: source, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(source.name)
                Text(source.isPlaying ? "Playing audio" : "Silent")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            LevelBars(isPlaying: source.isPlaying)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isSelected ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear),
                    in: .rect(cornerRadius: 7))
        .contentShape(.rect)
    }
}

// MARK: - Variant D — list on top, Record docked underneath

/// Selection and commitment live in **two zones**: the list picks the Source, a permanent
/// dock at the bottom records it. The blue Record button is always on screen, so it is
/// discoverable and impossible to trigger by accident while scanning the list.
struct VariantD: View {
    static let title = "List + record dock"
    @Bindable var model: SourceModel
    @State private var showsAllApps = false

    private var listed: [Source] { showsAllApps ? model.sources : model.playing }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(showsAllApps ? "All Apps" : "Playing Audio").font(.headline)
                Spacer()
                Toggle("All", isOn: $showsAllApps.animation(.snappy))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if listed.isEmpty {
                NothingPlaying { showsAllApps = true }
                    .frame(height: 210)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(listed) { source in
                            SourceRow(source: source, isSelected: source.id == model.selectedID)
                                .onTapGesture { model.selectedID = source.id }
                        }
                    }
                    .padding(6)
                }
                .frame(height: 210)
            }

            Divider()
            dock
        }
        .frame(width: 320)
    }

    private var dock: some View {
        HStack(spacing: 10) {
            if let selected = model.selected {
                AppIcon(source: selected, size: 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text(selected.name).font(.subheadline.weight(.medium)).lineLimit(1)
                    Text(selected.isPlaying ? "Ready" : "Silent — will record when it plays")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            } else {
                Text("Choose a Source").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
            } label: {
                Label("Record", systemImage: "record.circle")
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(model.selectedID == nil)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

// MARK: - Variant E — the selected row grows its own Record button

/// One zone, not two. Tapping a row selects it and the row **expands** to reveal the blue
/// Record button inside itself, so the commit happens where the choice happened. Silent
/// apps are demoted to a disclosure below rather than mixed in behind a toggle — the
/// header can never lie about what it is showing.
struct VariantE: View {
    static let title = "Row expands to record"
    @Bindable var model: SourceModel
    @State private var showsOthers = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Playing Audio").font(.headline)
                Spacer()
                LevelBars(isPlaying: !model.playing.isEmpty, height: 11)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVStack(spacing: 2) {
                    if model.playing.isEmpty {
                        NothingPlaying()
                    } else {
                        ForEach(model.playing) { source in
                            expandingRow(source)
                        }
                    }

                    DisclosureGroup(isExpanded: $showsOthers.animation(.snappy)) {
                        ForEach(model.sources.filter { !$0.isPlaying }) { source in
                            expandingRow(source)
                        }
                    } label: {
                        Text("^[\(model.sources.filter { !$0.isPlaying }.count) other running app](inflect: true)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                }
                .padding(6)
            }
            .frame(height: 280)
        }
        .frame(width: 320)
    }

    @ViewBuilder
    private func expandingRow(_ source: Source) -> some View {
        let isSelected = source.id == model.selectedID
        VStack(spacing: 0) {
            SourceRow(source: source, isSelected: false)
            if isSelected {
                Button {
                } label: {
                    Label("Record \(source.name)", systemImage: "record.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding(.horizontal, 10)
                .padding(.bottom, 9)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(isSelected ? AnyShapeStyle(.selection.opacity(0.55)) : AnyShapeStyle(.clear),
                    in: .rect(cornerRadius: 9))
        .contentShape(.rect)
        .onTapGesture {
            withAnimation(.snappy(duration: 0.22)) {
                model.selectedID = isSelected ? nil : source.id
            }
        }
    }
}
