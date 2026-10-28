import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let selected = model.selectedItems
        Group {
            if selected.count == 1, let item = selected.first {
                ItemInspector(item: item)
                    .id(item.id)
            } else if selected.count > 1 {
                MultiInspector(items: selected)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "sidebar.trailing").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("Select an item to see where it lives in Resolve.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct ItemInspector: View {
    @EnvironmentObject private var model: AppModel
    let item: LibraryItem
    @State private var split: CGFloat = 0.5

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    ItemPreview(item: item, frame: model.sampleFrame, split: split, showsSplit: item.kind == .lut)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            // The inspector preview is ~288 wide; map the drag to the split.
                            split = min(max(value.location.x / 288, 0.02), 0.98)
                        })
                        .help(item.kind == .lut ? "Drag to compare before and after" : "")
                    if item.kind == .lut {
                        HStack {
                            Text("Before").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Picker("Sample", selection: $model.sampleFrame) {
                                ForEach(SampleFrame.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .labelsHidden().controlSize(.small).fixedSize()
                            Spacer()
                            Text("After").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.title3.weight(.semibold)).textSelection(.enabled)
                    Text(item.isManaged ? "\(item.kind.singularName) from \(item.group)" : "\(item.kind.singularName) · \(item.isBuiltIn ? "Built into Resolve" : "Not installed by Loadout")")
                        .foregroundStyle(.secondary)
                }

                GroupBox("Details") {
                    VStack(spacing: 6) {
                        row("Type", item.kind.singularName + (item.fileExtension.isEmpty ? "" : " (.\(item.fileExtension))"))
                        row("Pack", item.group)
                        if let creator = item.creator { row("Creator", creator) }
                        row("Size", ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                        if item.addedAt != .distantPast { row("Added", item.addedAt.formatted(date: .abbreviated, time: .shortened)) }
                        if let contents = item.bundleContents, !contents.isEmpty {
                            row("Contains", AssetKind.allCases.compactMap { k in contents[k].map { k.count($0) } }.joined(separator: ", "))
                        }
                    }
                    .padding(4)
                }

                GroupBox("Installed in Resolve") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            StateBadge(item: item, compact: false)
                            Spacer()
                        }
                        Text(statusText).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(item.currentURL.path)
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                            .textSelection(.enabled).lineLimit(4)
                    }
                    .padding(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    Button("Reveal in Finder") { model.reveal([item]) }
                        .disabled(item.state == .missing)
                    if item.state == .enabled {
                        Button("Turn Off") { model.setEnabled(false, [item]) }
                            .disabled(item.isBuiltIn)
                            .help("Moves it out of Resolve’s folders until you turn it on again")
                    } else if item.state == .disabled {
                        Button("Turn On") { model.setEnabled(true, [item]) }
                    }
                }
                if !item.isBuiltIn {
                    Button("Move to Trash…", role: .destructive) { model.requestRemove([item]) }
                        .buttonStyle(.link)
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
        }
    }

    private var statusText: String {
        switch item.state {
        case .enabled:
            return item.kind.refresh == .updateLists ? "Resolve lists it after Update Lists or a restart."
                                                     : "Resolve lists it after a restart."
        case .disabled: return "Turned off: waiting in Loadout’s Parked folder. Resolve doesn’t see it."
        case .missing: return "Loadout installed this, but the file is gone."
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
            Text(value).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
        }
        .font(.callout)
    }
}

private struct MultiInspector: View {
    @EnvironmentObject private var model: AppModel
    let items: [LibraryItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(items.count) items selected").font(.title3.weight(.semibold))
            Text(ByteCountFormatter.string(fromByteCount: items.reduce(0) { $0 + $1.size }, countStyle: .file))
                .foregroundStyle(.secondary)
            HStack {
                Button("Reveal in Finder") { model.reveal(items) }
                if items.contains(where: { $0.state == .enabled && !$0.isBuiltIn }) {
                    Button("Turn Off") { model.setEnabled(false, items) }
                }
                if items.contains(where: { $0.state == .disabled }) {
                    Button("Turn On") { model.setEnabled(true, items) }
                }
            }
            if !items.contains(where: \.isBuiltIn) {
                Button("Move to Trash…", role: .destructive) { model.requestRemove(items) }
                    .buttonStyle(.link).foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The bar under the Library: counts, what Resolve needs, and the one prominent button.
struct FooterBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.summary).font(.callout.weight(.medium)).monospacedDigit()
                if let notice = model.notice {
                    HStack(spacing: 5) {
                        Image(systemName: icon(for: notice.refresh))
                            .foregroundStyle(notice.refresh == .none ? Color.green : Color.orange)
                        Text(notice.message).lineLimit(2)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(model.scanning ? "Reading the drop…" : "Drop files, folders or zips anywhere in this window.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.notice != nil {
                Button("Dismiss") { model.notice = nil }
                    .buttonStyle(.borderless)
            }
            Button {
                model.chooseFiles()
            } label: {
                Text("Add Assets…").frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.scanning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func icon(for refresh: ResolveRefresh) -> String {
        switch refresh {
        case .none: return "checkmark.circle.fill"
        case .updateLists: return "arrow.clockwise.circle.fill"
        case .restart: return "arrow.triangle.2.circlepath.circle.fill"
        }
    }
}
