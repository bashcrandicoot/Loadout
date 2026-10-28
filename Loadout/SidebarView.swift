import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(selection: Binding<LibraryScope?>(get: { model.scope }, set: { model.scope = $0 ?? .all })) {
            Section {
                row("All Items", "square.grid.2x2", model.visibleItems.count, .all)
                ForEach(AssetKind.allCases, id: \.self) { kind in
                    if kind == .lut || kind == .title || model.count(kind) > 0 {
                        row(kind.pluralName == "Bundles" ? ".drfx Bundles" : kind.pluralName, kind.symbol, model.count(kind), .kind(kind))
                    }
                }
                if model.disabledCount > 0 {
                    row("Turned Off", "pause.circle", model.disabledCount, .disabled)
                }
            } header: {
                Text("Library")
            }
            Section("Packs") {
                if model.packs.isEmpty {
                    Text("Drop a pack to start")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.packs, id: \.name) { pack in
                    row(pack.name, pack.managed ? "shippingbox" : "folder", pack.count, .pack(pack.name))
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) { Brand() }
        .safeAreaInset(edge: .bottom, spacing: 0) { ResolveStatusBox() }
    }

    private func row(_ title: String, _ symbol: String, _ count: Int, _ scope: LibraryScope) -> some View {
        Label {
            HStack {
                Text(title).lineLimit(1)
                Spacer()
                Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
            }
        } icon: {
            Image(systemName: symbol)
        }
        .tag(scope)
    }
}

private struct Brand: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Loadout").font(.title3.weight(.semibold))
            Text("for DaVinci Resolve").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}

/// Which Resolve is installed and whether it's running.
struct ResolveStatusBox: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(model.resolve == nil ? Color.orange : (model.resolveRunning ? Color.green : Color.secondary))
                    .frame(width: 7, height: 7)
                Text(model.resolve.map { "DaVinci Resolve \($0.majorVersion)" } ?? "DaVinci Resolve not found")
                    .font(.callout.weight(.medium))
            }
            if let resolve = model.resolve {
                Text("\(resolve.isStudio ? "Studio" : "Free") \(resolve.version) · \(model.resolveRunning ? "running" : "not running")")
                    .font(.caption).foregroundStyle(.secondary)
                if resolve.isAppStore {
                    Text("The App Store version isn’t supported yet.")
                        .font(.caption).foregroundStyle(.orange)
                }
            } else {
                Text("Loadout can still install; Resolve will find the files once it’s installed.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let lastScan = model.lastScan {
                Text("Last scan \(lastScan.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            if model.paths.isSandboxed {
                Text("Sandbox folders (LOADOUT_SANDBOX)")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
        .padding(10)
    }
}
