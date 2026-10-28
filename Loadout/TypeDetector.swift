import Foundation

/// Decides what a file is: a LUT, a DCTL, a Fusion template (and which kind), a .drfx
/// bundle, an archive to unpack, junk to skip, or something Loadout doesn't install.
enum TypeDetector {
    enum Verdict: Equatable {
        /// An asset Loadout installs.
        case asset(AssetKind)
        /// A loose `.setting` whose kind can't be told from its folders or contents
        /// (the drop sheet asks once per pack).
        case unsortedTemplate
        /// A `.zip` to unpack (nested zips too).
        case archive
        /// Readmes, previews, `__MACOSX`, `.DS_Store`…: skipped without mention.
        case junk
        /// Looks like an asset but isn't one (e.g. `.cube.txt`, a `.cube` with no LUT data).
        case rejected(String)
        /// Something else (a .fuse, a .mov…), listed as not installed.
        case unsupported
    }

    static let lutExtensions: Set<String> = ["cube", "3dl", "ilut", "olut", "mga"]
    static let dctlExtensions: Set<String> = ["dctl", "dctle"]
    static let templateExtensions: Set<String> = ["setting"]
    static let bundleExtensions: Set<String> = ["drfx"]
    static let archiveExtensions: Set<String> = ["zip"]
    static let junkExtensions: Set<String> = ["txt", "md", "rtf", "pdf", "png", "jpg", "jpeg", "gif", "webp", "heic",
                                              "html", "htm", "url", "webloc", "ds_store", "ini", "db"]
    /// What `.cube.txt`-style names really are: an asset with a second, wrong extension.
    static var assetExtensions: Set<String> {
        lutExtensions.union(dctlExtensions).union(templateExtensions).union(bundleExtensions)
    }

    /// Path components that mean "skip everything in here".
    static func isJunkPath(_ components: [String]) -> Bool {
        components.contains { $0 == "__MACOSX" || $0.hasPrefix("._") || $0 == ".DS_Store" }
    }

    /// - Parameters:
    ///   - url: the file on disk (read for content checks).
    ///   - components: its path inside the drop, folders first (used for template kind hints).
    static func classify(_ url: URL, components: [String]? = nil) -> Verdict {
        let name = url.lastPathComponent
        let parts = components ?? [name]
        if isJunkPath(parts) || name.hasPrefix(".") { return .junk }
        let ext = url.pathExtension.lowercased()
        let stem = (name as NSString).deletingPathExtension
        let innerExt = (stem as NSString).pathExtension.lowercased()

        // "Look.cube.txt": an asset someone (or a browser) gave a second extension.
        if !ext.isEmpty, !assetExtensions.contains(ext), assetExtensions.contains(innerExt) {
            return .rejected("“\(name)” ends in .\(ext), not .\(innerExt). Rename it to “\(stem)” if it’s a real \(innerExt) file.")
        }
        if lutExtensions.contains(ext) {
            if ext == "cube", !looksLikeCube(url) {
                return .rejected("“\(name)” isn’t a valid .cube LUT (no LUT_3D_SIZE or LUT_1D_SIZE).")
            }
            return .asset(.lut)
        }
        if dctlExtensions.contains(ext) { return .asset(.dctl) }
        if bundleExtensions.contains(ext) { return .asset(.bundle) }
        if archiveExtensions.contains(ext) { return .archive }
        if templateExtensions.contains(ext) {
            if let kind = templateKind(fromFolders: Array(parts.dropLast())) { return .asset(kind) }
            if let kind = templateKind(fromContents: url) { return .asset(kind) }
            return .unsortedTemplate
        }
        if junkExtensions.contains(ext) || name.lowercased().hasPrefix("readme") || name.lowercased().hasPrefix("license") {
            return .junk
        }
        return .unsupported
    }

    /// The nearest folder named like a Resolve template category wins
    /// (`Pack/Edit/Titles/Lower Thirds/x.setting` → title).
    static func templateKind(fromFolders folders: [String]) -> AssetKind? {
        for folder in folders.reversed() {
            let f = folder.lowercased()
            if f.contains("transition") { return .transition }
            if f.contains("title") || f.contains("lower third") { return .title }
            if f.contains("generator") { return .generator }
            if f.contains("effect") || f == "fx" { return .effect }
        }
        return nil
    }

    /// A light read of the macro: text tools make a title.
    static func templateKind(fromContents url: URL) -> AssetKind? {
        guard let text = readPrefix(url, bytes: 256 * 1024) else { return nil }
        if text.contains("TextPlus") || text.contains("StyledText") || text.contains("Text3D") { return .title }
        return nil
    }

    /// A real .cube names its size before the data.
    static func looksLikeCube(_ url: URL) -> Bool {
        guard let text = readPrefix(url, bytes: 64 * 1024) else { return false }
        for line in text.split(whereSeparator: \.isNewline).prefix(400) {
            let trimmed = line.trimmingCharacters(in: .whitespaces).uppercased()
            if trimmed.hasPrefix("LUT_3D_SIZE") || trimmed.hasPrefix("LUT_1D_SIZE") { return true }
        }
        return false
    }

    static func readPrefix(_ url: URL, bytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: bytes) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// What a `.drfx` holds, from its zip listing (`Edit/Titles/…`).
    static func bundleContents(of url: URL) -> [AssetKind: Int] {
        guard let entries = try? Archive.list(url) else { return [:] }
        var counts: [AssetKind: Int] = [:]
        for entry in entries where entry.lowercased().hasSuffix(".setting") {
            let parts = entry.split(separator: "/").map(String.init)
            if isJunkPath(parts) { continue }   // __MACOSX/…/._Title.setting
            if let kind = templateKind(fromFolders: Array(parts.dropLast())) {
                counts[kind, default: 0] += 1
            }
        }
        return counts
    }
}
