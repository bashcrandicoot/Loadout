import Foundation

/// A pack: one install, and every file it put in Resolve's folders.
struct PackRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var creator: String?
    var version: String?
    /// The file or folder it came from ("ATL_Nights_Complete_v3.zip").
    var sourceName: String
    var installedAt = Date()
}

/// One file Loadout installed. Whether it's on, off (parked) or missing is read from disk.
struct FileRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var packID: UUID
    var kind: AssetKind
    /// Where it lives in Resolve's folders when it's on.
    var homePath: String
    var size: Int64
    var installedAt = Date()
    var bundleContents: [AssetKind: Int]? = nil

    var homeURL: URL { URL(fileURLWithPath: homePath) }
}

/// Loadout's record of what it installed, kept as JSON in Application Support.
struct LibraryIndex: Codable, Equatable {
    var version = 1
    var packs: [PackRecord] = []
    var files: [FileRecord] = []

    func pack(_ id: UUID) -> PackRecord? { packs.first { $0.id == id } }
    func pack(named name: String) -> PackRecord? {
        packs.first { $0.name.compare(name, options: [.caseInsensitive]) == .orderedSame }
    }
    func record(forHome path: String) -> FileRecord? {
        let key = URL(fileURLWithPath: path).standardizedFileURL.path
        return files.first { URL(fileURLWithPath: $0.homePath).standardizedFileURL.path == key }
    }
    func files(in packID: UUID) -> [FileRecord] { files.filter { $0.packID == packID } }

    mutating func removeFiles(atHomes paths: Set<String>) {
        let keys = Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        files.removeAll { keys.contains(URL(fileURLWithPath: $0.homePath).standardizedFileURL.path) }
        // A pack with no files left is gone too.
        let live = Set(files.map(\.packID))
        packs.removeAll { !live.contains($0.id) }
    }
}

/// Loads and saves the index file.
struct IndexStore {
    let url: URL

    func load() -> LibraryIndex {
        guard let data = try? Data(contentsOf: url) else { return LibraryIndex() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(LibraryIndex.self, from: data)) ?? LibraryIndex()
    }

    func save(_ index: LibraryIndex) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(index).write(to: url, options: .atomic)
    }
}
