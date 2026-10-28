import SwiftUI

/// What a drop holds, where it will go, and "Install to Resolve".
struct DropSheet: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let pending = model.pending {
            content(pending)
        }
    }

    private func content(_ pending: PendingInstall) -> some View {
        let scan = pending.scan
        let plan = model.plan(for: pending)
        let conflicts = plan.filter { $0.conflict != nil }
        let existingPack = model.index.pack(named: pending.options.packName)
        let installCount = plan.count - (pending.options.conflictPolicy == .skip ? conflicts.count : 0)
        let refresh = plan.map(\.kind.refresh).max() ?? .none

        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header: what was dropped.
                    HStack(spacing: 12) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: scan.sources.first?.path ?? "/"))
                            .resizable().frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(scan.sources.count == 1 ? scan.sources[0].lastPathComponent : "\(scan.sources.count) items")
                                .font(.headline).lineLimit(1).truncationMode(.middle)
                            Text("\(ByteCountFormatter.string(fromByteCount: scan.totalBytes, countStyle: .file)) · \(scan.fileCount) file\(scan.fileCount == 1 ? "" : "s") · scanned in \(String(format: "%.1f", scan.duration)) s")
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(scan.headline).font(.title2.weight(.semibold))
                        Text("Loadout puts each file where Resolve looks for it. Nothing in Resolve changes until you install.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !scan.countsByKind.isEmpty || !scan.unsortedTemplates.isEmpty {
                        Panel {
                            ForEach(scan.countsByKind, id: \.0) { kind, count in
                                KindRow(symbol: kind.symbol, title: kind.pluralName == "Bundles" ? ".drfx Bundles" : kind.pluralName,
                                        detail: extensions(of: kind, in: scan), count: count)
                            }
                            if !scan.unsortedTemplates.isEmpty {
                                HStack {
                                    KindRow(symbol: "questionmark.square.dashed", title: "Fusion templates",
                                            detail: ".setting", count: scan.unsortedTemplates.count)
                                }
                                HStack {
                                    Text("Loadout can’t tell what these are. Install them as:")
                                        .font(.callout).foregroundStyle(.secondary)
                                    Spacer()
                                    Picker("Install as", selection: binding(\.unsortedKind)) {
                                        ForEach(AssetKind.templateKinds, id: \.self) { Text($0.pluralName).tag(Optional($0)) }
                                        Divider()
                                        Text("Don’t Install").tag(AssetKind?.none)
                                    }
                                    .labelsHidden().fixedSize()
                                }
                            }
                        }
                    }

                    // The pack these files belong to.
                    Panel {
                        HStack(spacing: 10) {
                            Image(systemName: "shippingbox").foregroundStyle(Color.accentColor).frame(width: 20)
                            Text(existingPack == nil ? "New pack" : "Updates pack").foregroundStyle(.secondary)
                            TextField("Pack name", text: binding(\.packName))
                                .textFieldStyle(.roundedBorder)
                        }
                        HStack(spacing: 8) {
                            TextField("Creator (optional)", text: binding(\.creator)).textFieldStyle(.roundedBorder)
                            TextField("Version (optional)", text: binding(\.version)).textFieldStyle(.roundedBorder).frame(width: 140)
                        }
                        Text(destinationSummary(plan))
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                            .lineLimit(3).truncationMode(.middle)
                    }

                    if !conflicts.isEmpty {
                        Panel {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.orange).frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(conflictTitle(conflicts)).font(.callout.weight(.medium))
                                    Text(conflictDetail(pending.options.conflictPolicy))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Picker("If a file exists", selection: binding(\.conflictPolicy)) {
                                    ForEach(ConflictPolicy.allCases) { Text($0.title).tag($0) }
                                }
                                .labelsHidden().fixedSize()
                            }
                        }
                    }

                    if !scan.rejected.isEmpty || !scan.unsupported.isEmpty || scan.ignoredCount > 0 {
                        DisclosureGroup(skippedTitle(scan)) {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(scan.rejected.prefix(20), id: \.self) { Text($0) }
                                ForEach(scan.unsupported.prefix(20), id: \.self) { Text("\($0): not something Resolve loads from these folders") }
                                if scan.ignoredCount > 0 {
                                    Text("\(scan.ignoredCount) readme, preview or system file\(scan.ignoredCount == 1 ? "" : "s") skipped")
                                }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                        }
                        .font(.callout)
                    }

                    if refresh != .none {
                        Label(refresh == .updateLists
                              ? "After installing, use Update Lists in Resolve (Project Settings ▸ Color Management) or restart it."
                              : "Resolve shows new templates and DCTLs after a restart.",
                              systemImage: "info.circle")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
            }

            Divider()
            HStack {
                Text(model.resolveRunning ? "Resolve can stay open." : "Resolve doesn’t need to be open.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { model.cancelPending() }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                Button("Install to Resolve") { model.installPending() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(installCount == 0 || pending.options.packName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.bar)
        }
        .frame(width: 540)
        .frame(minHeight: 420, idealHeight: 600, maxHeight: 760)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<InstallOptions, T>) -> Binding<T> {
        Binding(get: { (model.pending?.options ?? InstallOptions(packName: ""))[keyPath: keyPath] },
                set: { model.pending?.options[keyPath: keyPath] = $0 })
    }

    private func extensions(of kind: AssetKind, in scan: ScanResult) -> String {
        Set(scan.items.filter { $0.kind == kind }.map { "." + $0.source.pathExtension.lowercased() })
            .sorted().joined(separator: " ")
    }

    private func destinationSummary(_ plan: [PlannedFile]) -> String {
        var folders: [String] = []
        for file in plan {
            let folder = file.kind == .bundle ? model.paths.templatesRoot : packFolder(of: file)
            let text = (folder.path as NSString).abbreviatingWithTildeInPath + "/"
            if !folders.contains(text) { folders.append(text) }
        }
        return folders.prefix(3).joined(separator: "\n") + (folders.count > 3 ? "\n…" : "")
    }

    /// The pack's own folder (above any subfolders).
    private func packFolder(of file: PlannedFile) -> URL {
        var url = file.destination.deletingLastPathComponent()
        for _ in file.item.subpath { url.deleteLastPathComponent() }
        return url
    }

    private func conflictTitle(_ conflicts: [PlannedFile]) -> String {
        let n = conflicts.count
        let owners = Set(conflicts.compactMap { file -> String? in
            switch file.conflict {
            case .samePack: return model.pending?.options.packName
            case .otherPack(let name): return name
            default: return nil
            }
        })
        if owners.count == 1, let owner = owners.first {
            return "\(n) file\(n == 1 ? "" : "s") replace\(n == 1 ? "s" : "") \(owner)"
        }
        return "\(n) file\(n == 1 ? " is" : "s are") already in Resolve’s folders"
    }

    private func conflictDetail(_ policy: ConflictPolicy) -> String {
        switch policy {
        case .replace: return "The old versions move to the Trash."
        case .keepBoth: return "The new ones get a number (“Neon 2.cube”)."
        case .skip: return "The old versions stay; the new ones aren’t installed."
        }
    }

    private func skippedTitle(_ scan: ScanResult) -> String {
        let n = scan.rejected.count + scan.unsupported.count + scan.ignoredCount
        return "\(n) file\(n == 1 ? "" : "s") skipped"
    }
}

private struct KindRow: View {
    let symbol: String
    let title: String
    let detail: String
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Color.accentColor).frame(width: 20)
            Text(title)
            Text(detail).font(.caption.monospaced()).foregroundStyle(.secondary)
            Spacer()
            Text("\(count)").monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

/// A rounded material panel, like Lodge's.
struct Panel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
    }
}
