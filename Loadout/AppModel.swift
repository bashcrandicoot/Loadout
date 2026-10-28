import AppKit
import SwiftUI

/// Which part of the Library the sidebar shows.
enum LibraryScope: Hashable {
    case all
    case kind(AssetKind)
    case pack(String)
    case disabled
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case recent = "Recently Added"
    case name = "Name"
    case pack = "Pack"
    var id: String { rawValue }
}

enum LibraryLayout: String { case grid, list }

/// The toolbar's quick filter.
enum KindFilter: String, CaseIterable, Identifiable {
    case all = "All", luts = "LUTs", titles = "Titles", transitions = "Transitions", effects = "Effects", generators = "Generators"
    var id: String { rawValue }

    func matches(_ kind: AssetKind) -> Bool {
        switch self {
        case .all: return true
        case .luts: return kind == .lut || kind == .dctl
        case .titles: return kind == .title
        case .transitions: return kind == .transition
        case .effects: return kind == .effect || kind == .bundle
        case .generators: return kind == .generator
        }
    }
}

/// A drop waiting for "Install to Resolve".
struct PendingInstall: Identifiable {
    var id: UUID { scan.id }
    var scan: ScanResult
    var options: InstallOptions
}

/// What Resolve needs after the last change, shown in the footer.
struct RefreshNotice: Equatable {
    var refresh: ResolveRefresh
    var message: String
}

/// The app's state: the Library, the current drop and the settings.
@MainActor
final class AppModel: ObservableObject {
    /// True while Xcode's unit tests run inside the app.
    nonisolated static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    let paths: ResolvePaths
    let fileOperator: FileOperating
    private let store: IndexStore

    @Published private(set) var index = LibraryIndex()
    @Published private(set) var items: [LibraryItem] = []
    @Published private(set) var resolve: ResolveInstall?
    @Published private(set) var resolveRunning = false
    @Published private(set) var lastScan: Date?

    @Published var scope: LibraryScope = .all
    @Published var kindFilter: KindFilter = .all
    @Published var search = ""
    @Published var sort: LibrarySort = .recent
    @Published var layout: LibraryLayout = LibraryLayout(rawValue: UserDefaults.standard.string(forKey: "layout") ?? "") ?? .grid {
        didSet { UserDefaults.standard.set(layout.rawValue, forKey: "layout") }
    }
    /// Settings: list Resolve's own LUTs (ACES, Arri, Film Looks…) too.
    @Published var showBuiltIn = UserDefaults.standard.bool(forKey: "showBuiltInLUTs") {
        didSet { UserDefaults.standard.set(showBuiltIn, forKey: "showBuiltInLUTs") }
    }
    @Published var sampleFrame = SampleFrame(rawValue: UserDefaults.standard.string(forKey: "sampleFrame") ?? "") ?? .nightExterior {
        didSet { UserDefaults.standard.set(sampleFrame.rawValue, forKey: "sampleFrame") }
    }
    @Published var selection: Set<LibraryItem.ID> = []
    @Published var showInspector = true

    @Published var pending: PendingInstall?
    @Published var scanning = false
    @Published var notice: RefreshNotice?
    @Published var errorMessage: String?
    /// Items waiting for the "Move to Trash?" confirmation.
    @Published var confirmingRemoval: [LibraryItem] = []

    init(paths: ResolvePaths = .current, fileOperator: FileOperating? = nil) {
        self.paths = paths
        self.fileOperator = fileOperator ?? AutoFileOperator(paths: paths)
        self.store = IndexStore(url: paths.indexURL)
        index = store.load()
        reload()
    }

    // MARK: - Library

    func reload() {
        let scanned = LibraryScanner(paths: paths).scan(index: index)
        items = scanned
        lastScan = Date()
        selection = selection.intersection(Set(scanned.map(\.id)))
        refreshResolveStatus()
    }

    func refreshResolveStatus() {
        resolve = ResolveDetector.find().first
        resolveRunning = ResolveDetector.isRunning
    }

    /// Everything the Library lists (Resolve's own LUTs only when Settings says so).
    var visibleItems: [LibraryItem] { items.filter { showBuiltIn || !$0.isBuiltIn } }

    var filteredItems: [LibraryItem] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let list = visibleItems.filter { item in
            switch scope {
            case .all: break
            case .kind(let kind): guard item.kind == kind else { return false }
            case .pack(let name): guard item.group == name else { return false }
            case .disabled: guard item.state == .disabled else { return false }
            }
            guard kindFilter.matches(item.kind) else { return false }
            guard query.isEmpty else {
                return item.name.localizedCaseInsensitiveContains(query)
                    || item.group.localizedCaseInsensitiveContains(query)
                    || (item.creator?.localizedCaseInsensitiveContains(query) ?? false)
            }
            return true
        }
        switch sort {
        case .recent: return list.sorted { ($0.addedAt, $1.name) > ($1.addedAt, $0.name) }
        case .name: return list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .pack: return list.sorted {
            $0.group == $1.group ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                                 : $0.group.localizedStandardCompare($1.group) == .orderedAscending }
        }
    }

    func count(_ kind: AssetKind) -> Int { visibleItems.filter { $0.kind == kind }.count }
    var disabledCount: Int { visibleItems.filter { $0.state == .disabled }.count }

    /// Sidebar packs: Loadout's packs first, then folders it found.
    var packs: [(name: String, count: Int, managed: Bool)] {
        var counts: [String: (Int, Bool)] = [:]
        for item in visibleItems {
            let old = counts[item.group] ?? (0, false)
            counts[item.group] = (old.0 + 1, old.1 || item.isManaged)
        }
        return counts.map { ($0.key, $0.value.0, $0.value.1) }
            .sorted { $0.managed != $1.managed ? $0.managed : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var selectedItems: [LibraryItem] { items.filter { selection.contains($0.id) } }

    /// "214 items · 132 LUTs · 1.8 GB"
    var summary: String {
        let list = visibleItems
        let bytes = list.reduce(Int64(0)) { $0 + $1.size }
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        return "\(list.count) item\(list.count == 1 ? "" : "s") · \(AssetKind.lut.count(count(.lut))) · \(size)"
    }

    // MARK: - Dropping

    func handleDrop(_ urls: [URL]) {
        guard !urls.isEmpty, !scanning else { return }
        scanning = true
        let scanner = PackScanner(stagingRoot: paths.stagingRoot)
        Task.detached(priority: .userInitiated) {
            let result = Result { try scanner.scan(urls) }
            await MainActor.run {
                self.scanning = false
                switch result {
                case .success(let scan):
                    self.pending?.scan.cleanUp()
                    self.pending = PendingInstall(scan: scan, options: InstallOptions(packName: scan.suggestedPackName))
                case .failure(let error):
                    self.errorMessage = "Loadout couldn’t read that: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Opens an Open panel for files, folders and zips.
    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose LUTs, DCTLs, Fusion templates, .drfx bundles, folders or zips."
        if panel.runModal() == .OK { handleDrop(panel.urls) }
    }

    func plan(for pending: PendingInstall) -> [PlannedFile] {
        Installer(paths: paths).plan(pending.scan, options: pending.options, index: index)
    }

    func cancelPending() {
        pending?.scan.cleanUp()
        pending = nil
    }

    func installPending() {
        guard let pending else { return }
        let installer = Installer(paths: paths)
        let planned = installer.plan(pending.scan, options: pending.options, index: index)
        do {
            var newIndex = index
            let report = try installer.install(planned, options: pending.options,
                                               sourceName: pending.scan.sources.first?.lastPathComponent ?? pending.options.packName,
                                               index: &newIndex, using: fileOperator)
            try store.save(newIndex)
            index = newIndex
            pending.scan.cleanUp()
            self.pending = nil
            reload()
            scope = .pack(report.pack.name)
            notice = Self.notice(for: report.refresh,
                                 what: "Installed \(report.whatInstalled) in “\(report.pack.name)”.")
        } catch FileOpError.cancelled {
            errorMessage = FileOpError.cancelled.errorDescription
        } catch {
            errorMessage = "Nothing was installed. \(error.localizedDescription)"
        }
    }

    // MARK: - Disable, enable, remove

    func setEnabled(_ enabled: Bool, _ targets: [LibraryItem]) {
        let actions = LibraryActions(paths: paths)
        do {
            if enabled { try actions.enable(targets, using: fileOperator) }
            else { try actions.disable(targets, using: fileOperator) }
            reload()
            let n = targets.count
            notice = Self.notice(for: LibraryActions.refresh(for: targets),
                                 what: "\(enabled ? "Turned on" : "Turned off") \(n) item\(n == 1 ? "" : "s").")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestRemove(_ targets: [LibraryItem]) {
        if let builtIn = targets.first(where: \.isBuiltIn) {
            errorMessage = LibraryActions.Refusal.builtIn(builtIn.name).errorDescription
            return
        }
        confirmingRemoval = targets
    }

    func remove(_ targets: [LibraryItem]) {
        confirmingRemoval = []
        var newIndex = index
        do {
            try LibraryActions(paths: paths).remove(targets, index: &newIndex, using: fileOperator)
            try store.save(newIndex)
            index = newIndex
            reload()
            let n = targets.count
            notice = Self.notice(for: LibraryActions.refresh(for: targets),
                                 what: "Moved \(n) item\(n == 1 ? "" : "s") to the Trash.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reveal(_ targets: [LibraryItem]) {
        let urls = targets.filter { $0.state != .missing }.map(\.currentURL)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    static func notice(for refresh: ResolveRefresh, what: String) -> RefreshNotice? {
        switch refresh {
        case .none: return RefreshNotice(refresh: .none, message: what)
        case .updateLists:
            return RefreshNotice(refresh: .updateLists,
                                 message: "\(what) In Resolve, choose Project Settings ▸ Color Management ▸ Update Lists, or restart Resolve.")
        case .restart:
            return RefreshNotice(refresh: .restart, message: "\(what) Restart Resolve to see them.")
        }
    }
}
