import Foundation

/// What to do when a file is already where an item would go.
enum ConflictPolicy: String, CaseIterable, Identifiable {
    /// The old file goes to the Trash.
    case replace
    /// Install the new one as "name 2".
    case keepBoth
    /// Leave the old one; don't install the new one.
    case skip

    var id: String { rawValue }
    var title: String {
        switch self {
        case .replace: return "Replace"
        case .keepBoth: return "Keep Both"
        case .skip: return "Skip"
        }
    }
}

/// Who owns a file that's already at a destination.
enum Conflict: Equatable {
    case samePack
    case otherPack(String)
    case unmanaged
}

struct InstallOptions {
    var packName: String
    var creator: String = ""
    var version: String = ""
    /// The kind for loose `.setting` files Loadout couldn't sort (nil skips them).
    var unsortedKind: AssetKind? = .effect
    var conflictPolicy: ConflictPolicy = .replace
}

struct PlannedFile: Identifiable {
    var id: UUID { item.id }
    let item: ScannedItem
    let kind: AssetKind
    var destination: URL
    var conflict: Conflict?
}

struct InstallReport {
    var pack: PackRecord
    var installed: [FileRecord]
    var skipped: Int
    var replaced: Int
    /// What Resolve needs to show the new items.
    var refresh: ResolveRefresh

    func count(of kind: AssetKind) -> Int { installed.filter { $0.kind == kind }.count }

    /// "24 LUTs and 6 titles"
    var whatInstalled: String {
        let parts = AssetKind.allCases.compactMap { kind -> String? in
            let n = count(of: kind)
            return n > 0 ? kind.count(n) : nil
        }
        return parts.isEmpty ? "nothing" : ListFormatter.localizedString(byJoining: parts)
    }
}

/// Maps scanned items to Resolve's folders and copies them in as one transaction.
struct Installer {
    var paths: ResolvePaths

    func plan(_ scan: ScanResult, options: InstallOptions, index: LibraryIndex) -> [PlannedFile] {
        let existingPack = index.pack(named: options.packName)
        var claimed = Set<String>()
        var planned: [PlannedFile] = []
        for item in scan.items {
            guard let kind = item.kind ?? options.unsortedKind else { continue }
            var dest = paths.destination(for: kind, pack: options.packName, fileName: item.fileName, subpath: item.subpath)
            // Two files in one drop with the same destination: number the second.
            if claimed.contains(dest.path) {
                let original = dest
                var n = 2
                let stem = original.deletingPathExtension().lastPathComponent, ext = original.pathExtension
                repeat {
                    dest = original.deletingLastPathComponent().appendingPathComponent("\(stem) \(n).\(ext)")
                    n += 1
                } while claimed.contains(dest.path)
            }
            claimed.insert(dest.path)
            var conflict: Conflict? = nil
            if FileManager.default.fileExists(atPath: dest.path) {
                if let record = index.record(forHome: dest.path), let owner = index.pack(record.packID) {
                    conflict = owner.id == existingPack?.id ? .samePack : .otherPack(owner.name)
                } else {
                    conflict = .unmanaged
                }
            }
            planned.append(PlannedFile(item: item, kind: kind, destination: dest, conflict: conflict))
        }
        return planned
    }

    /// Copies the plan in and records it in `index`. All or nothing: a failure undoes every step.
    func install(_ planned: [PlannedFile], options: InstallOptions, sourceName: String,
                 index: inout LibraryIndex, using fileOperator: FileOperating) throws -> InstallReport {
        var pack = index.pack(named: options.packName) ?? PackRecord(name: options.packName, sourceName: sourceName)
        pack.sourceName = sourceName
        pack.installedAt = Date()
        if !options.creator.isEmpty { pack.creator = options.creator }
        if !options.version.isEmpty { pack.version = options.version }

        var folders: [FileOp] = []
        var steps: [FileOp] = []
        var dirs = Set<String>()
        var records: [FileRecord] = []
        var replacedHomes = Set<String>()
        var skipped = 0
        var replaced = 0
        var reserved = Set<String>()

        for file in planned {
            var dest = file.destination
            if file.conflict != nil {
                switch options.conflictPolicy {
                case .skip:
                    skipped += 1
                    continue
                case .keepBoth:
                    dest = Self.uniqueURL(dest, avoiding: reserved)
                case .replace:
                    steps.append(.trash(dest))
                    replacedHomes.insert(dest.path)
                    replaced += 1
                }
            }
            reserved.insert(dest.path)
            let folder = dest.deletingLastPathComponent()
            if !dirs.contains(folder.path) {
                dirs.insert(folder.path)
                folders.append(.makeDirectory(folder))
            }
            steps.append(.copy(from: file.item.source, to: dest))
            records.append(FileRecord(packID: pack.id, kind: file.kind, homePath: dest.path, size: file.item.size,
                                      bundleContents: file.item.bundleContents.isEmpty ? nil : file.item.bundleContents))
        }

        try fileOperator.perform(folders + steps)

        index.removeFiles(atHomes: replacedHomes)
        if let i = index.packs.firstIndex(where: { $0.id == pack.id }) {
            index.packs[i] = pack
        } else if !records.isEmpty {
            index.packs.append(pack)
        }
        index.files.append(contentsOf: records)

        let refresh = records.map(\.kind.refresh).max() ?? .none
        return InstallReport(pack: pack, installed: records, skipped: skipped, replaced: replaced, refresh: refresh)
    }

    static func uniqueURL(_ url: URL, avoiding reserved: Set<String>) -> URL {
        var candidate = LocalFileOperator.uniqueURL(url)
        var n = 2
        let stem = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        while reserved.contains(candidate.path) || FileManager.default.fileExists(atPath: candidate.path) {
            n += 1
            candidate = url.deletingLastPathComponent().appendingPathComponent("\(stem) \(n).\(ext)")
        }
        return candidate
    }
}
