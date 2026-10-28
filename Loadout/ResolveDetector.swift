import AppKit

/// A DaVinci Resolve install found on this Mac.
struct ResolveInstall: Equatable {
    var appURL: URL
    var version: String
    var isStudio: Bool
    /// The Mac App Store build keeps its folders in a container Loadout doesn't support yet.
    var isAppStore: Bool

    /// "DaVinci Resolve Studio 19.1.3" or "DaVinci Resolve 21.1.0"
    var displayName: String { "DaVinci Resolve\(isStudio ? " Studio" : "") \(version)" }
    var majorVersion: String { version.split(separator: ".").first.map(String.init) ?? version }
}

/// Finds Resolve and tells whether it's running.
enum ResolveDetector {
    static let bundleIDs = ["com.blackmagic-design.DaVinciResolve", "com.blackmagic-design.DaVinciResolveLite",
                            "com.blackmagic-design.DaVinciResolveStudio", "com.blackmagic-design.DaVinciResolveAppStore"]

    /// Looks in /Applications (and one folder down, where Blackmagic's installer puts it) and ~/Applications.
    static func find(in roots: [URL]? = nil) -> [ResolveInstall] {
        let fm = FileManager.default
        let searchRoots = roots ?? [URL(fileURLWithPath: "/Applications"),
                                    fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        var candidates: [URL] = []
        for root in searchRoots {
            guard let children = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for child in children {
                if child.pathExtension == "app" { candidates.append(child) }
                else if child.lastPathComponent.lowercased().contains("davinci"),
                        let inner = try? fm.contentsOfDirectory(at: child, includingPropertiesForKeys: nil) {
                    candidates += inner.filter { $0.pathExtension == "app" }
                }
            }
        }
        return candidates.compactMap(install(at:))
            .sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }

    static func install(at url: URL) -> ResolveInstall? {
        guard let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier,
              id.hasPrefix("com.blackmagic-design.DaVinciResolve") else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let version = (info["CFBundleShortVersionString"] as? String) ?? (info["CFBundleVersion"] as? String) ?? "?"
        let name = url.deletingPathExtension().lastPathComponent
        let isAppStore = FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt").path)
        return ResolveInstall(appURL: url, version: version,
                              isStudio: name.localizedCaseInsensitiveContains("studio") || id.hasSuffix("Studio"),
                              isAppStore: isAppStore)
    }

    static var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            guard let id = app.bundleIdentifier else { return false }
            return id.hasPrefix("com.blackmagic-design.DaVinciResolve")
        }
    }
}
