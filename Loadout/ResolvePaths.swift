import Foundation

/// Every folder Loadout reads or writes. Injectable, so tests (and the `LOADOUT_SANDBOX`
/// launch environment) never touch the real Resolve folders.
struct ResolvePaths: Equatable {
    /// `/Library/Application Support/Blackmagic Design/DaVinci Resolve/LUT` (LUTs and DCTLs).
    var lutRoot: URL
    /// `~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Templates`.
    var templatesRoot: URL
    /// `~/Library/Application Support/Loadout` (the index and the Parked folder).
    var supportRoot: URL
    /// Where removed files go. nil = the user's Trash (via FileManager.trashItem).
    var trashDirectory: URL?
    /// True for tests and the sandbox: never ask for an admin password.
    var isSandboxed: Bool = false

    /// The subfolder of the LUT folder Loadout installs into, so Resolve's LUT menu groups by pack.
    static let lutSubfolder = "Loadout"

    var parkedRoot: URL { supportRoot.appendingPathComponent("Parked", isDirectory: true) }
    var parkedLUTRoot: URL { parkedRoot.appendingPathComponent("LUT", isDirectory: true) }
    var parkedTemplatesRoot: URL { parkedRoot.appendingPathComponent("Templates", isDirectory: true) }
    var indexURL: URL { supportRoot.appendingPathComponent("library.json") }
    var stagingRoot: URL { FileManager.default.temporaryDirectory.appendingPathComponent("LoadoutStaging", isDirectory: true) }

    /// The real folders on this Mac (the direct-download Resolve build).
    static var system: ResolvePaths {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ResolvePaths(
            lutRoot: URL(fileURLWithPath: "/Library/Application Support/Blackmagic Design/DaVinci Resolve/LUT", isDirectory: true),
            templatesRoot: home.appendingPathComponent("Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Templates", isDirectory: true),
            supportRoot: home.appendingPathComponent("Library/Application Support/Loadout", isDirectory: true),
            trashDirectory: nil)
    }

    /// Every folder under one root, for tests and for trying Loadout safely.
    static func sandbox(at root: URL) -> ResolvePaths {
        let root = root.resolvingSymlinksInPath()
        return ResolvePaths(
            lutRoot: root.appendingPathComponent("LUT", isDirectory: true),
            templatesRoot: root.appendingPathComponent("Fusion/Templates", isDirectory: true),
            supportRoot: root.appendingPathComponent("Loadout", isDirectory: true),
            trashDirectory: root.appendingPathComponent("Trash", isDirectory: true),
            isSandboxed: true)
    }

    /// `LOADOUT_SANDBOX=/some/folder` puts every folder under it (screenshots and safe testing).
    static var current: ResolvePaths {
        if let root = ProcessInfo.processInfo.environment["LOADOUT_SANDBOX"], !root.isEmpty {
            return .sandbox(at: URL(fileURLWithPath: (root as NSString).expandingTildeInPath, isDirectory: true))
        }
        return .system
    }

    // MARK: - Install path mapping

    /// Where an item belongs in Resolve's folders.
    /// - Parameters:
    ///   - fileName: the file's name (its extension is lowercased, as Resolve expects for `.drfx`).
    ///   - subpath: folders inside the pack to keep (e.g. `Log/` and `Rec709/` in a LUT pack).
    func destination(for kind: AssetKind, pack: String, fileName: String, subpath: [String] = []) -> URL {
        let name = Self.normalizedFileName(fileName)
        let packFolder = Self.safeFolderName(pack)
        let cleanSub = subpath.map(Self.safeFolderName).filter { !$0.isEmpty }
        switch kind {
        case .lut, .dctl:
            var url = lutRoot.appendingPathComponent(Self.lutSubfolder, isDirectory: true)
                .appendingPathComponent(packFolder, isDirectory: true)
            for part in cleanSub { url.appendPathComponent(part, isDirectory: true) }
            return url.appendingPathComponent(name)
        case .title, .transition, .effect, .generator:
            var url = templatesRoot.appendingPathComponent("Edit", isDirectory: true)
                .appendingPathComponent(kind.templateFolder!, isDirectory: true)
                .appendingPathComponent(packFolder, isDirectory: true)
            for part in cleanSub { url.appendPathComponent(part, isDirectory: true) }
            return url.appendingPathComponent(name)
        case .bundle:
            // Resolve installs a double-clicked .drfx at the Templates root, kept zipped.
            return templatesRoot.appendingPathComponent(name)
        }
    }

    /// Lowercases the extension (`Pack.DRFX` → `Pack.drfx`).
    static func normalizedFileName(_ name: String) -> String {
        let ext = (name as NSString).pathExtension
        guard !ext.isEmpty, ext != ext.lowercased() else { return name }
        return (name as NSString).deletingPathExtension + "." + ext.lowercased()
    }

    /// A folder name without slashes or colons, trimmed, never empty or hidden.
    static func safeFolderName(_ name: String) -> String {
        var clean = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        while clean.hasPrefix(".") { clean.removeFirst() }
        return clean.isEmpty ? "Untitled Pack" : clean
    }

    // MARK: - Parking (disable / enable)

    /// Which managed root a path is in, and its path relative to that root.
    func location(of url: URL) -> (root: Root, relative: String)? {
        let path = url.standardizedFileURL.path
        for root in Root.allCases {
            let base = self.url(for: root).standardizedFileURL.path
            if path.hasPrefix(base + "/") {
                return (root, String(path.dropFirst(base.count + 1)))
            }
        }
        return nil
    }

    enum Root: CaseIterable { case lut, templates, parkedLUT, parkedTemplates }

    func url(for root: Root) -> URL {
        switch root {
        case .lut: return lutRoot
        case .templates: return templatesRoot
        case .parkedLUT: return parkedLUTRoot
        case .parkedTemplates: return parkedTemplatesRoot
        }
    }

    /// Where a file in Resolve's folders waits while it's disabled (same relative path).
    func parkedURL(forHome home: URL) -> URL? {
        guard let loc = location(of: home) else { return nil }
        switch loc.root {
        case .lut: return parkedLUTRoot.appendingPathComponent(loc.relative)
        case .templates: return parkedTemplatesRoot.appendingPathComponent(loc.relative)
        case .parkedLUT, .parkedTemplates: return nil
        }
    }

    /// Where a parked file goes back to when it's enabled again.
    func homeURL(forParked parked: URL) -> URL? {
        guard let loc = location(of: parked) else { return nil }
        switch loc.root {
        case .parkedLUT: return lutRoot.appendingPathComponent(loc.relative)
        case .parkedTemplates: return templatesRoot.appendingPathComponent(loc.relative)
        case .lut, .templates: return nil
        }
    }

    /// True when writing here may need an administrator password (the system LUT folder).
    func mayNeedAdmin(_ url: URL) -> Bool {
        guard !isSandboxed else { return false }
        return url.standardizedFileURL.path.hasPrefix(lutRoot.standardizedFileURL.path)
    }
}
