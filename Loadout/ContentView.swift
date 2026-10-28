import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var dropTargeted = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 232, max: 300)
        } detail: {
            VStack(spacing: 0) {
                LibraryView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay { if dropTargeted { DropHighlight() } }
                    .overlay(alignment: .bottom) {
                        if let run = model.libraryRun {
                            CaseToast(run: run) { model.caseRunSettled($0) }
                                .padding(.bottom, 14)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(.smooth(duration: 0.3), value: model.libraryRun?.id)
                FooterBar()
            }
            .inspector(isPresented: $model.showInspector) {
                InspectorView()
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
            }
        }
        .toolbar { LibraryToolbar() }
        .searchable(text: $model.search, placement: .toolbar, prompt: "Search LUTs, templates, packs")
        .navigationTitle("Loadout")
        .modifier(HideWindowTitle())
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            loadURLs(providers) { model.handleDrop($0) }
            return true
        }
        .sheet(item: Screenshots.showsDropSheetInPanel ? .constant(nil) : $model.pending) { _ in
            DropSheet()
                .environmentObject(model)
        }
        .alert("Loadout", isPresented: Binding(get: { model.errorMessage != nil },
                                              set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .confirmationDialog(removalTitle, isPresented: Binding(get: { !model.confirmingRemoval.isEmpty },
                                                               set: { if !$0 { model.confirmingRemoval = [] } })) {
            Button("Move to Trash", role: .destructive) { model.remove(model.confirmingRemoval) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(removalMessage)
        }
    }

    private var removalTitle: String {
        let n = model.confirmingRemoval.count
        return n == 1 ? "Move “\(model.confirmingRemoval[0].name)” to the Trash?" : "Move \(n) items to the Trash?"
    }

    private var removalMessage: String {
        let unmanaged = model.confirmingRemoval.filter { !$0.isManaged }.count
        var text = "Resolve won’t see them any more. You can put them back from the Trash."
        if unmanaged > 0 {
            text += " \(unmanaged == 1 ? "One of them wasn’t" : "\(unmanaged) of them weren’t") installed by Loadout."
        }
        return text
    }
}

/// Reads file URLs from a drop.
func loadURLs(_ providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
    let group = DispatchGroup()
    let lock = NSLock()
    var urls: [URL] = []
    for provider in providers where provider.canLoadObject(ofClass: URL.self) {
        group.enter()
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url, url.isFileURL { lock.lock(); urls.append(url); lock.unlock() }
            group.leave()
        }
    }
    group.notify(queue: .main) {
        MainActor.assumeIsolated { completion(urls) }
    }
}

struct DropHighlight: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                VStack(spacing: 10) {
                    // The case opens wide for the drop.
                    CaseDropTarget()
                    Text("Drop to install in Resolve")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(12)
            .allowsHitTesting(false)
    }
}

/// A turn-off, turn-on or removal: the case unloads (or stashes) the items over the Library.
struct CaseToast: View {
    let run: CaseRun
    var onSettled: (UUID) -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            CaseStage(run: run, layout: .toast, onSettled: onSettled)
            Text(run.caption)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .frame(width: 170, alignment: .leading)
                .padding(.leading, 20)
                .padding(.bottom, 34)   // the queued cards sit below
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator.opacity(0.5)))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .allowsHitTesting(false)
    }
}

struct LibraryToolbar: ToolbarContent {
    @EnvironmentObject private var model: AppModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Type", selection: $model.kindFilter) {
                ForEach(KindFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Show one type")
        }
        ToolbarItem {
            Picker("View", selection: $model.layout) {
                Label("Grid", systemImage: "square.grid.2x2").tag(LibraryLayout.grid)
                Label("List", systemImage: "list.bullet").tag(LibraryLayout.list)
            }
            .pickerStyle(.segmented)
            .help("Grid or list")
        }
        ToolbarItem {
            Menu {
                Picker("Sort By", selection: $model.sort) {
                    ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .help("Sort by")
        }
        ToolbarItem {
            Button { model.chooseFiles() } label: { Label("Add", systemImage: "plus") }
                .help("Add LUTs, templates, folders or zips (⌘O)")
        }
        ToolbarItem {
            Button { model.showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.trailing") }
                .help(model.showInspector ? "Hide Inspector" : "Show Inspector")
        }
    }
}

/// Keeps the title out of the toolbar (the window is still "Loadout" in the Window menu).
struct HideWindowTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbar(removing: .title)
        } else {
            content
        }
    }
}
