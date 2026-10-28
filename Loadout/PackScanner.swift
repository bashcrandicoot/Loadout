import Foundation

/// One installable file found in a drop.
struct ScannedItem: Identifiable, Hashable {
    let id = UUID()
    /// The file to copy (in the drop, or in the staging folder for zips).
    let source: URL
    /// Its path inside the drop, for display ("ATL Nights/Log/Neon.cube").
    let displayPath: String
    /// nil for a loose `.setting` whose kind couldn't be told (asked once per pack).
    var kind: AssetKind?
    /// Folders inside the pack to keep at the destination ("Log", "Rec709").
    var subpath: [String]
    /// For a `.drfx`: the templates inside it.
    var bundleContents: [AssetKind: Int] = [:]

    var fileName: String { source.lastPathComponent }
    var size: Int64 { (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0 }
}

/// What a drop held.
struct ScanResult: Identifiable {
    let id = UUID()
    let sources: [URL]
    var suggestedPackName: String
    var items: [ScannedItem]
    /// Files that look like assets but aren't (e.g. `.cube.txt`), with the reason.
    var rejected: [String]
    /// Files Loadout doesn't install (names only).
    var unsupported: [String]
    /// Readmes, previews, `__MACOSX`… skipped quietly.
    var ignoredCount: Int
    /// Every file looked at, unpacked zips included.
    var fileCount: Int
    var totalBytes: Int64
    var duration: TimeInterval
    /// Temporary folder holding unpacked zips; removed after install or cancel.
    var stagingFolder: URL?

    var unsortedTemplates: [ScannedItem] { items.filter { $0.kind == nil } }

    func count(of kind: AssetKind) -> Int { items.filter { $0.kind == kind }.count }

    var countsByKind: [(AssetKind, Int)] {
        AssetKind.allCases.compactMap { kind in
            let n = count(of: kind)
            return n > 0 ? (kind, n) : nil
        }
    }

    /// "Found 24 LUTs, 6 titles and 2 transitions"
    var headline: String {
        var parts = countsByKind.map { $0.0.count($0.1) }
        let unsorted = unsortedTemplates.count
        if unsorted > 0 { parts.append("\(unsorted) Fusion template\(unsorted == 1 ? "" : "s")") }
        guard !parts.isEmpty else { return "Nothing to install" }
        return "Found " + ListFormatter.localizedString(byJoining: parts)
    }

    func cleanUp() {
        if let stagingFolder { try? FileManager.default.removeItem(at: stagingFolder) }
    }
}

/// Unpacks and classifies whatever the user dropped: files, folders, packs and zips
/// (nested zips too). `.drfx` bundles are left zipped, as Resolve expects.
struct PackScanner {
    var stagingRoot: URL
    var maxZipDepth = 4

    init(stagingRoot: URL = FileManager.default.temporaryDirectory.appendingPathComponent("LoadoutStaging", isDirectory: true)) {
        self.stagingRoot = stagingRoot
    }

    /// Folders that only say where a file goes in Resolve, not how the pack is organised.
    static let structuralFolders: Set<String> = ["edit", "templates", "fusion", "titles", "transitions", "effects",
                                                 "generators", "lut", "luts", "dctl", "dctls", "macros"]

    func scan(_ urls: [URL]) throws -> ScanResult {
        let start = Date()
        let staging = stagingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        var usedStaging = false
        var found: [(url: URL, components: [String])] = []
        var rejected: [String] = []
        var unsupported: [String] = []
        var ignored = 0
        var fileCount = 0
        var bytes: Int64 = 0

        func visitFile(_ url: URL, components: [String], depth: Int) throws {
            fileCount += 1
            bytes += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            switch TypeDetector.classify(url, components: components) {
            case .asset, .unsortedTemplate:
                found.append((url, components))
            case .archive:
                guard depth < maxZipDepth else { unsupported.append(components.joined(separator: "/")); return }
                let name = url.deletingPathExtension().lastPathComponent
                let folder = staging.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    .appendingPathComponent(name, isDirectory: true)
                try Archive.extract(url, into: folder)
                usedStaging = true
                fileCount -= 1   // the zip itself isn't counted, its contents are
                try visitFolder(folder, components: Array(components.dropLast()) + [name], depth: depth + 1)
            case .junk:
                ignored += 1
            case .rejected(let reason):
                rejected.append(reason)
            case .unsupported:
                unsupported.append(components.joined(separator: "/"))
            }
        }

        func visitFolder(_ folder: URL, components: [String], depth: Int) throws {
            if TypeDetector.isJunkPath(components) { return }
            let children = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [])
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            for child in children {
                let parts = components + [child.lastPathComponent]
                if TypeDetector.isJunkPath(parts) || child.lastPathComponent.hasPrefix(".") { ignored += 1; continue }
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey])
                if values?.isDirectory == true {
                    try visitFolder(child, components: parts, depth: depth)
                } else {
                    try visitFile(child, components: parts, depth: depth)
                }
            }
        }

        do {
            for url in urls {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
                if isDir.boolValue {
                    try visitFolder(url, components: [url.lastPathComponent], depth: 0)
                } else {
                    try visitFile(url, components: [url.lastPathComponent], depth: 0)
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }

        // Folders shared by every file (the zip's name, a wrapper folder) aren't kept.
        let folderLists = found.map { Array($0.components.dropLast()) }
        let common = Self.commonPrefixCount(folderLists)
        let items: [ScannedItem] = found.map { entry in
            let folders = Array(entry.components.dropLast())
            let verdict = TypeDetector.classify(entry.url, components: entry.components)
            var kind: AssetKind? = nil
            if case .asset(let k) = verdict { kind = k }
            let sub = Array(folders.dropFirst(common)).filter { !Self.structuralFolders.contains($0.lowercased()) }
            var item = ScannedItem(source: entry.url, displayPath: entry.components.joined(separator: "/"),
                                   kind: kind, subpath: kind == .bundle ? [] : sub)
            if kind == .bundle { item.bundleContents = TypeDetector.bundleContents(of: entry.url) }
            return item
        }

        if !usedStaging { try? FileManager.default.removeItem(at: staging) }
        return ScanResult(
            sources: urls,
            suggestedPackName: Self.suggestedName(for: urls),
            items: items,
            rejected: rejected,
            unsupported: unsupported,
            ignoredCount: ignored,
            fileCount: fileCount,
            totalBytes: bytes,
            duration: Date().timeIntervalSince(start),
            stagingFolder: usedStaging ? staging : nil)
    }

    /// How many leading folders every file shares.
    static func commonPrefixCount(_ lists: [[String]]) -> Int {
        guard var prefix = lists.first else { return 0 }
        for list in lists.dropFirst() {
            var n = 0
            while n < prefix.count, n < list.count, prefix[n] == list[n] { n += 1 }
            prefix = Array(prefix.prefix(n))
        }
        return prefix.count
    }

    /// "ATL_Nights_Complete_v3.zip" → "ATL Nights Complete v3"
    static func suggestedName(for urls: [URL]) -> String {
        guard urls.count == 1, let url = urls.first else {
            let parents = Set(urls.map { $0.deletingLastPathComponent().lastPathComponent })
            return parents.count == 1 ? parents.first! : "New Pack"
        }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        var name = isDir.boolValue ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        name = name.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "New Pack" : name
    }
}
