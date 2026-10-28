import Foundation

/// Whether an item is in Resolve's folders right now.
enum ItemState: String, Codable {
    /// In Resolve's folders: Resolve loads it.
    case enabled
    /// Parked in Loadout's holding folder: Resolve doesn't see it.
    case disabled
    /// Loadout installed it, but the file is gone.
    case missing
}

/// One asset in the Library: managed (installed by Loadout) or found in Resolve's folders.
struct LibraryItem: Identifiable, Hashable {
    /// The path where it lives when it's on.
    var id: String { homeURL.path }
    var homeURL: URL
    /// Where the file is now (home, parked, or home for a missing file).
    var currentURL: URL
    var kind: AssetKind
    var state: ItemState
    /// The pack that installed it (nil for files Loadout didn't install).
    var packID: UUID?
    /// The pack's name, or for other files the folder they're in ("LUTs by IWLTBAP").
    var group: String
    var creator: String?
    var size: Int64
    var addedAt: Date
    /// One of Resolve's own LUTs (ACES, Arri, Film Looks…).
    var isBuiltIn = false
    var bundleContents: [AssetKind: Int]? = nil

    var isManaged: Bool { packID != nil }
    var fileName: String { homeURL.lastPathComponent }
    var name: String { homeURL.deletingPathExtension().lastPathComponent }
    var fileExtension: String { homeURL.pathExtension.lowercased() }
}

/// Reads Resolve's folders and Loadout's Parked folder, and matches what it finds to the index.
struct LibraryScanner {
    var paths: ResolvePaths

    /// LUT folders and files Resolve installs itself.
    static let builtInLUTFolders: Set<String> = [
        "aces", "arri", "astrodesign", "blackmagic design", "canon", "dci", "dji", "film looks",
        "hdr hybrid log-gamma", "hdr st 2084", "leica", "olympus", "panasonic", "red", "sony", "nikon",
        "fujifilm", "gopro", "vfx io", "apple", "z cam", "zcam", "kinefinity", "insta360"]
    static let builtInRootExtensions: Set<String> = ["ilut", "olut", "xml"]

    func scan(index: LibraryIndex) -> [LibraryItem] {
        var items: [String: LibraryItem] = [:]

        func add(_ file: URL, home: URL, state: ItemState) {
            guard let kind = kind(ofHome: home) else { return }
            let key = home.standardizedFileURL.path
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])
            var item = LibraryItem(
                homeURL: home.standardizedFileURL, currentURL: file.standardizedFileURL, kind: kind, state: state,
                packID: nil, group: groupName(forHome: home), creator: nil,
                size: Int64(values?.fileSize ?? 0),
                addedAt: values?.creationDate ?? values?.contentModificationDate ?? .distantPast)
            if let record = index.record(forHome: key) {
                let pack = index.pack(record.packID)
                item.packID = record.packID
                item.group = pack?.name ?? item.group
                item.creator = pack?.creator
                item.addedAt = record.installedAt
                item.bundleContents = record.bundleContents
            } else {
                item.isBuiltIn = isBuiltIn(home)
                if kind == .bundle { item.bundleContents = TypeDetector.bundleContents(of: file) }
            }
            // A file both home and parked: the home copy is the live one.
            if let existing = items[key], existing.state == .enabled { return }
            items[key] = item
        }

        for file in walk(paths.lutRoot) { add(file, home: file, state: .enabled) }
        for file in walk(paths.templatesRoot) { add(file, home: file, state: .enabled) }
        for root in [paths.parkedLUTRoot, paths.parkedTemplatesRoot] {
            for file in walk(root) {
                if let home = paths.homeURL(forParked: file) { add(file, home: home, state: .disabled) }
            }
        }
        // Installed by Loadout, but gone from both places.
        for record in index.files where items[record.homeURL.standardizedFileURL.path] == nil {
            let pack = index.pack(record.packID)
            items[record.homeURL.standardizedFileURL.path] = LibraryItem(
                homeURL: record.homeURL.standardizedFileURL, currentURL: record.homeURL.standardizedFileURL,
                kind: record.kind, state: .missing, packID: record.packID, group: pack?.name ?? "Unknown pack",
                creator: pack?.creator, size: record.size, addedAt: record.installedAt,
                bundleContents: record.bundleContents)
        }
        return Array(items.values)
    }

    /// Every file under `root` (no hidden files, no package contents).
    func walk(_ root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true { files.append(url) }
        }
        return files
    }

    /// What a file in Resolve's folders is, from where it sits. nil = not something Loadout lists.
    func kind(ofHome home: URL) -> AssetKind? {
        guard let loc = paths.location(of: home) else { return nil }
        let ext = home.pathExtension.lowercased()
        switch loc.root {
        case .lut, .parkedLUT:
            if TypeDetector.lutExtensions.contains(ext) { return .lut }
            if TypeDetector.dctlExtensions.contains(ext) { return .dctl }
            return nil
        case .templates, .parkedTemplates:
            if ext == "drfx" { return .bundle }
            guard ext == "setting" else { return nil }
            let parts = loc.relative.split(separator: "/").map(String.init)
            // Only Edit page templates: Edit/<Titles|Transitions|Effects|Generators>/…
            guard parts.count >= 3, parts[0].lowercased() == "edit" else { return nil }
            return AssetKind.templateKinds.first { $0.templateFolder!.lowercased() == parts[1].lowercased() }
        }
    }

    /// For files Loadout didn't install: the folder that groups them in the sidebar.
    func groupName(forHome home: URL) -> String {
        guard let loc = paths.location(of: home) else { return "Other" }
        let parts = loc.relative.split(separator: "/").map(String.init)
        switch loc.root {
        case .lut, .parkedLUT:
            if parts.count >= 3, parts[0] == ResolvePaths.lutSubfolder { return parts[1] }
            return parts.count >= 2 ? parts[0] : "LUT Folder"
        case .templates, .parkedTemplates:
            if parts.count >= 4, parts[0].lowercased() == "edit" { return parts[2] }
            if parts.count == 3, parts[0].lowercased() == "edit" { return parts[1] }
            return parts.count >= 2 ? parts[0] : "Templates Folder"
        }
    }

    func isBuiltIn(_ home: URL) -> Bool {
        guard let loc = paths.location(of: home), loc.root == .lut || loc.root == .parkedLUT else { return false }
        let parts = loc.relative.split(separator: "/").map(String.init)
        if parts.count == 1 { return Self.builtInRootExtensions.contains(home.pathExtension.lowercased()) }
        return Self.builtInLUTFolders.contains(parts[0].lowercased())
    }
}

/// Disable, enable and remove.
struct LibraryActions {
    var paths: ResolvePaths

    enum Refusal: LocalizedError {
        case builtIn(String)
        var errorDescription: String? {
            switch self {
            case .builtIn(let name): return "“\(name)” is one of Resolve’s own LUTs, so Loadout leaves it alone."
            }
        }
    }

    /// Moves items out of Resolve's folders into Loadout's Parked folder (same relative path).
    func disableOps(_ items: [LibraryItem]) throws -> [FileOp] {
        var ops: [FileOp] = []
        for item in items where item.state == .enabled {
            if item.isBuiltIn { throw Refusal.builtIn(item.name) }
            guard let parked = paths.parkedURL(forHome: item.homeURL) else { continue }
            ops.append(.makeDirectory(parked.deletingLastPathComponent()))
            if FileManager.default.fileExists(atPath: parked.path) { ops.append(.trash(parked)) }
            ops.append(.move(from: item.currentURL, to: parked))
        }
        return ops
    }

    /// Moves parked items back to exactly where they were.
    func enableOps(_ items: [LibraryItem]) -> [FileOp] {
        var ops: [FileOp] = []
        for item in items where item.state == .disabled {
            ops.append(.makeDirectory(item.homeURL.deletingLastPathComponent()))
            ops.append(.move(from: item.currentURL, to: item.homeURL))
        }
        return ops
    }

    /// Moves items to the Trash (never deletes).
    func removeOps(_ items: [LibraryItem]) throws -> [FileOp] {
        var ops: [FileOp] = []
        for item in items where item.state != .missing {
            if item.isBuiltIn { throw Refusal.builtIn(item.name) }
            ops.append(.trash(item.currentURL))
        }
        return ops
    }

    func disable(_ items: [LibraryItem], using op: FileOperating, progress: FileOpProgress.Handler? = nil) throws {
        try op.perform(try disableOps(items), progress: progress)
        cleanEmptyFolders(after: items)
    }

    func enable(_ items: [LibraryItem], using op: FileOperating, progress: FileOpProgress.Handler? = nil) throws {
        try op.perform(enableOps(items), progress: progress)
        cleanEmptyFolders(after: items)
    }

    /// Trashes the files and forgets them in the index.
    func remove(_ items: [LibraryItem], index: inout LibraryIndex, using op: FileOperating,
                progress: FileOpProgress.Handler? = nil) throws {
        try op.perform(try removeOps(items), progress: progress)
        index.removeFiles(atHomes: Set(items.map(\.homeURL.path)))
        cleanEmptyFolders(after: items)
    }

    /// Removes the pack folders Loadout made once they're empty.
    func cleanEmptyFolders(after items: [LibraryItem]) {
        let fm = FileManager.default
        // Never remove Resolve's own folders (LUT/Loadout, Templates/Edit/Titles…), only pack folders.
        var stopURLs = [paths.lutRoot, paths.templatesRoot, paths.parkedLUTRoot, paths.parkedTemplatesRoot,
                        paths.lutRoot.appendingPathComponent(ResolvePaths.lutSubfolder),
                        paths.parkedLUTRoot.appendingPathComponent(ResolvePaths.lutSubfolder)]
        for root in [paths.templatesRoot, paths.parkedTemplatesRoot] {
            let edit = root.appendingPathComponent("Edit")
            stopURLs.append(edit)
            stopURLs += AssetKind.templateKinds.compactMap(\.templateFolder).map { edit.appendingPathComponent($0) }
        }
        let stops = Set(stopURLs.map { $0.standardizedFileURL.path })
        for item in items where item.isManaged {
            var folder = item.currentURL.deletingLastPathComponent().standardizedFileURL
            while !stops.contains(folder.path), paths.location(of: folder) != nil,
                  let contents = try? fm.contentsOfDirectory(atPath: folder.path),
                  contents.allSatisfy({ $0 == ".DS_Store" }) {
                try? fm.removeItem(at: folder)
                folder = folder.deletingLastPathComponent()
            }
        }
    }

    /// What Resolve needs after changing these items.
    static func refresh(for items: [LibraryItem]) -> ResolveRefresh {
        items.map(\.kind.refresh).max() ?? .none
    }
}
