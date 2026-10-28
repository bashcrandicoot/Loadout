import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let items = model.filteredItems
        Group {
            if items.isEmpty {
                EmptyLibrary()
            } else if model.layout == .grid {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 176, maximum: 260), spacing: 14)], spacing: 14) {
                        ForEach(items) { item in
                            ItemTile(item: item, selected: model.selection.contains(item.id))
                                .onTapGesture { select(item) }
                                .contextMenu { ItemMenu(items: targets(for: item)) }
                        }
                    }
                    .padding(16)
                }
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.0001))
                .onTapGesture { model.selection = [] }
            } else {
                Table(items, selection: $model.selection) {
                    TableColumn("Name") { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.kind.symbol).foregroundStyle(.secondary).frame(width: 16)
                            Text(item.name).lineLimit(1)
                                .foregroundStyle(item.state == .enabled ? .primary : .secondary)
                        }
                    }
                    .width(min: 180, ideal: 280)
                    TableColumn("Type") { Text($0.kind.singularName) }.width(80)
                    TableColumn("Pack") { Text($0.group).lineLimit(1) }.width(min: 100, ideal: 160)
                    TableColumn("Status") { StateBadge(item: $0, compact: false) }.width(90)
                    TableColumn("Added") { item in
                        Text(item.addedAt == .distantPast ? "—" : item.addedAt.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(.secondary)
                    }
                    .width(100)
                }
                .contextMenu(forSelectionType: LibraryItem.ID.self) { ids in
                    ItemMenu(items: model.items.filter { ids.contains($0.id) })
                }
            }
        }
    }

    private func select(_ item: LibraryItem) {
        if NSEvent.modifierFlags.contains(.command) {
            if model.selection.contains(item.id) { model.selection.remove(item.id) } else { model.selection.insert(item.id) }
        } else {
            model.selection = [item.id]
        }
    }

    private func targets(for item: LibraryItem) -> [LibraryItem] {
        model.selection.contains(item.id) ? model.selectedItems : [item]
    }
}

/// Reveal, turn on/off and remove, for a context menu.
struct ItemMenu: View {
    @EnvironmentObject private var model: AppModel
    let items: [LibraryItem]

    var body: some View {
        Button("Reveal in Finder") { model.reveal(items) }
            .disabled(items.allSatisfy { $0.state == .missing })
        Divider()
        if items.contains(where: { $0.state == .enabled && !$0.isBuiltIn }) {
            Button("Turn Off") { model.setEnabled(false, items) }
        }
        if items.contains(where: { $0.state == .disabled }) {
            Button("Turn On") { model.setEnabled(true, items) }
        }
        Divider()
        Button("Move to Trash…", role: .destructive) { model.requestRemove(items) }
            .disabled(items.contains(where: \.isBuiltIn))
    }
}

struct EmptyLibrary: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(model.items.isEmpty ? "Drop LUTs, templates or packs here" : "Nothing matches")
                .font(.title3.weight(.semibold))
            Text(model.items.isEmpty
                 ? "Loadout puts each file where DaVinci Resolve looks for it: .cube LUTs, DCTLs, Fusion .setting templates, .drfx bundles, folders and zips."
                 : "Try another type or search.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ItemTile: View {
    @EnvironmentObject private var model: AppModel
    let item: LibraryItem
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ItemPreview(item: item, frame: model.sampleFrame, split: 0.5, showsSplit: true)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .opacity(item.state == .enabled ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.callout.weight(.medium)).lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(item.kind.singularName) · \(item.group)").lineLimit(1)
                    Spacer(minLength: 4)
                    StateBadge(item: item, compact: true)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: selected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .help(item.homeURL.path)
    }
}

struct StateBadge: View {
    let item: LibraryItem
    let compact: Bool

    var body: some View {
        switch item.state {
        case .enabled:
            if !compact {
                Label(item.isBuiltIn ? "Built in" : (item.isManaged ? "On" : "Found"), systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon).foregroundStyle(item.isBuiltIn ? Color.secondary : Color.green)
            } else if !item.isManaged {
                Text(item.isBuiltIn ? "Built in" : "Found").foregroundStyle(.tertiary)
            }
        case .disabled:
            Label("Off", systemImage: "pause.circle.fill").labelStyle(.titleAndIcon).foregroundStyle(.orange)
        case .missing:
            Label("Missing", systemImage: "exclamationmark.triangle.fill").labelStyle(.titleAndIcon).foregroundStyle(.red)
        }
    }
}

/// The thumbnail: a before/after LUT preview, or an icon for templates and DCTLs.
struct ItemPreview: View {
    let item: LibraryItem
    let frame: SampleFrame
    var split: CGFloat
    var showsSplit: Bool
    @State private var images: (before: CGImage, after: CGImage)?
    @State private var loaded = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let images {
                    Image(decorative: images.before, scale: 1).resizable().scaledToFill()
                    Image(decorative: images.after, scale: 1).resizable().scaledToFill()
                        .mask(alignment: .trailing) {
                            Rectangle().frame(width: geo.size.width * (showsSplit ? 1 - split : 1))
                        }
                    if showsSplit {
                        Rectangle().fill(.white.opacity(0.85)).frame(width: 1.5)
                            .position(x: geo.size.width * split, y: geo.size.height / 2)
                    }
                } else {
                    LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: item.kind.symbol)
                        .font(.system(size: min(geo.size.height * 0.32, 44), weight: .light))
                        .foregroundStyle(.white.opacity(0.9))
                    if item.kind == .lut, loaded {
                        Text(".\(item.fileExtension)")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                            .padding(6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .task(id: "\(item.currentURL.path)|\(frame.rawValue)|\(item.state.rawValue)") {
            guard item.kind == .lut, item.state != .missing else { loaded = true; return }
            let url = item.currentURL
            let result = await Task.detached(priority: .utility) { LUTPreview.image(for: url, frame: frame) }.value
            images = result
            loaded = true
        }
    }

    private var gradient: [Color] {
        switch item.kind {
        case .lut: return [Color(red: 0.18, green: 0.22, blue: 0.32), Color(red: 0.35, green: 0.3, blue: 0.4)]
        case .dctl: return [Color(red: 0.2, green: 0.28, blue: 0.3), Color(red: 0.15, green: 0.4, blue: 0.45)]
        case .title: return [Color(red: 0.16, green: 0.3, blue: 0.55), Color(red: 0.32, green: 0.5, blue: 0.85)]
        case .transition: return [Color(red: 0.36, green: 0.22, blue: 0.5), Color(red: 0.55, green: 0.35, blue: 0.75)]
        case .effect: return [Color(red: 0.5, green: 0.25, blue: 0.3), Color(red: 0.8, green: 0.42, blue: 0.4)]
        case .generator: return [Color(red: 0.2, green: 0.4, blue: 0.3), Color(red: 0.32, green: 0.62, blue: 0.45)]
        case .bundle: return [Color(red: 0.35, green: 0.32, blue: 0.28), Color(red: 0.55, green: 0.5, blue: 0.42)]
        }
    }
}
