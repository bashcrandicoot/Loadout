import Foundation

/// The kinds of DaVinci Resolve assets Loadout installs.
enum AssetKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case lut
    case dctl
    case title
    case transition
    case effect
    case generator
    case bundle

    var id: String { rawValue }

    /// "LUTs", "Titles", … (sidebar, filter and counts).
    var pluralName: String {
        switch self {
        case .lut: return "LUTs"
        case .dctl: return "DCTLs"
        case .title: return "Titles"
        case .transition: return "Transitions"
        case .effect: return "Effects"
        case .generator: return "Generators"
        case .bundle: return "Bundles"
        }
    }

    var singularName: String {
        switch self {
        case .lut: return "LUT"
        case .dctl: return "DCTL"
        case .title: return "Title"
        case .transition: return "Transition"
        case .effect: return "Effect"
        case .generator: return "Generator"
        case .bundle: return "Bundle"
        }
    }

    /// "1 LUT", "6 titles"
    func count(_ n: Int) -> String {
        let word: String
        switch self {
        case .lut: word = n == 1 ? "LUT" : "LUTs"
        case .dctl: word = n == 1 ? "DCTL" : "DCTLs"
        case .bundle: word = n == 1 ? ".drfx bundle" : ".drfx bundles"
        default: word = n == 1 ? singularName.lowercased() : pluralName.lowercased()
        }
        return "\(n) \(word)"
    }

    var symbol: String {
        switch self {
        case .lut: return "camera.filters"
        case .dctl: return "function"
        case .title: return "textformat"
        case .transition: return "rectangle.lefthalf.inset.filled.arrow.left"
        case .effect: return "sparkles"
        case .generator: return "square.stack.3d.down.right"
        case .bundle: return "shippingbox"
        }
    }

    /// Fusion templates that live in `Templates/Edit/<folder>`.
    var isEditTemplate: Bool { templateFolder != nil }

    /// The `Templates/Edit/` subfolder Resolve's Effects library reads.
    var templateFolder: String? {
        switch self {
        case .title: return "Titles"
        case .transition: return "Transitions"
        case .effect: return "Effects"
        case .generator: return "Generators"
        default: return nil
        }
    }

    /// The kinds a loose `.setting` can be.
    static let templateKinds: [AssetKind] = [.title, .transition, .effect, .generator]

    /// What Resolve needs before it shows a newly installed or changed item.
    var refresh: ResolveRefresh {
        self == .lut ? .updateLists : .restart
    }

    /// LUTs and DCTLs live in the system-wide LUT folder.
    var usesLUTFolder: Bool { self == .lut || self == .dctl }
}

/// What Resolve needs to pick up a change.
enum ResolveRefresh: Int, Comparable, Codable {
    case none = 0
    /// LUTs: Project Settings ▸ Color Management ▸ Lookup Tables ▸ Update Lists.
    case updateLists = 1
    /// Templates, bundles and DCTLs: quit and reopen Resolve.
    case restart = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
