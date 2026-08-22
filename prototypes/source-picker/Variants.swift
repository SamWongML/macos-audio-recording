//  PROTOTYPE — throwaway. Three structurally different answers to "how does the user
//  choose a Source?", switchable from the bar at the bottom of the panel.

import SwiftUI

// MARK: - Shared scraps (deliberately small — each variant owns its own layout)

/// A live dot: filled and tinted while the Source is pushing audio.
struct PlayingDot: View {
    var isPlaying: Bool
    var body: some View {
        Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.slash")
            .foregroundStyle(isPlaying ? Color.accentColor : Color.secondary.opacity(0.5))
            .font(.caption)
            .symbolEffect(.variableColor, isActive: isPlaying)
    }
}

struct AppIcon: View {
    var source: Source
    var size: CGFloat
    var body: some View {
        Group {
            if let icon = source.icon {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Variant A — Source as a setting row

/// The official-components-first reading: a `Picker` is the stock control for
/// "one of a list", so the Source is one labelled row above the Record button.
/// Information hierarchy: Record is the hero, the Source is a subordinate setting.
struct VariantA: View {
    static let title = "Picker row"
    @Bindable var model: SourceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker(selection: $model.selectedID) {
                ForEach(model.sources) { source in
                    HStack {
                        AppIcon(source: source, size: 16)
                        Text(source.name)
                        if source.isPlaying { Image(systemName: "speaker.wave.2.fill") }
                    }
                    .tag(Optional(source.id))
                }
            } label: {
                Text("Source")
            }
            .pickerStyle(.menu)

            Button {
            } label: {
                Label("Start Recording", systemImage: "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.glassProminent)
            .disabled(model.selectedID == nil)

            if let selected = model.selected, !selected.isPlaying {
                Label("\(selected.name) isn't playing audio right now.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
            Text("No recordings yet")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 320)
    }
}

// MARK: - Variant B — the list is the panel

/// There is no picker. The panel *is* the list of apps, and one click on a row both
/// chooses the Source and starts the Recording. Primary affordance: the row.
/// Defaults to apps producing audio right now, because that is nearly always the one.
struct VariantB: View {
    static let title = "List is the panel"
    @Bindable var model: SourceModel
    @State private var showsAllApps = false
    @State private var hovered: String?

    private var listed: [Source] {
        showsAllApps ? model.sources : (model.playing.isEmpty ? model.sources : model.playing)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(showsAllApps ? "All Apps" : "Playing Audio")
                    .font(.headline)
                Spacer()
                Toggle("All", isOn: $showsAllApps)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(listed) { source in
                        HStack(spacing: 10) {
                            AppIcon(source: source, size: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(source.name)
                                Text(source.processes.isEmpty
                                     ? "no audio process"
                                     : "^[\(source.processes.count) process](inflect: true)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            if hovered == source.id {
                                Image(systemName: "record.circle.fill")
                                    .foregroundStyle(.red)
                                    .font(.title3)
                            } else {
                                PlayingDot(isPlaying: source.isPlaying)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(hovered == source.id ? Color.accentColor.opacity(0.12) : .clear,
                                    in: .rect(cornerRadius: 7))
                        .contentShape(.rect)
                        .onHover { hovered = $0 ? source.id : nil }
                        .onTapGesture { model.selectedID = source.id }
                    }
                }
                .padding(6)
            }
            .frame(height: 240)
        }
        .frame(width: 320)
    }
}

// MARK: - Variant C — remembered Source as the hero, changing is a drill-down

/// The Source is chosen rarely and recorded from constantly, so it is shown big and
/// changing it is a deliberate second mode: a searchable, sectioned list that replaces
/// the panel. Information hierarchy: the remembered Source is the subject of the panel.
struct VariantC: View {
    static let title = "Hero + drill-down"
    @Bindable var model: SourceModel
    @State private var isChoosing = false
    @State private var query = ""

    var body: some View {
        Group {
            if isChoosing { chooser } else { hero }
        }
        .frame(width: 320)
    }

    private var hero: some View {
        VStack(spacing: 12) {
            if let selected = model.selected {
                AppIcon(source: selected, size: 56)
                VStack(spacing: 3) {
                    Text(selected.name).font(.title3.weight(.semibold))
                    HStack(spacing: 5) {
                        PlayingDot(isPlaying: selected.isPlaying)
                        Text(selected.isPlaying ? "Playing audio" : "Silent")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ContentUnavailableView("No Source", systemImage: "app.dashed")
            }

            Button {
            } label: {
                Label("Start Recording", systemImage: "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.glassProminent)
            .disabled(model.selectedID == nil)

            Button("Change Source…") { isChoosing = true }
                .buttonStyle(.link)
                .font(.caption)
        }
        .padding(18)
    }

    private var chooser: some View {
        VStack(spacing: 0) {
            HStack {
                Button { isChoosing = false } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                Text("Choose Source").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            TextField("Search", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            Divider()

            List {
                section("Playing Now", model.playing)
                section("Running", model.sources.filter { !$0.isPlaying })
            }
            .listStyle(.sidebar)
            .frame(height: 220)
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ sources: [Source]) -> some View {
        let matching = sources.filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
        }
        if !matching.isEmpty {
            Section(title) {
                ForEach(matching) { source in
                    Button {
                        model.selectedID = source.id
                        isChoosing = false
                    } label: {
                        HStack(spacing: 8) {
                            AppIcon(source: source, size: 18)
                            Text(source.name)
                            Spacer()
                            if source.id == model.selectedID { Image(systemName: "checkmark") }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
