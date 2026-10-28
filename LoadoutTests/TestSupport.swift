import XCTest
@testable import Loadout

/// A throwaway folder with a sandboxed set of Resolve folders. Never the real ones.
final class Sandbox {
    let root: URL
    let paths: ResolvePaths
    let inbox: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoadoutTests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        paths = .sandbox(at: root)
        inbox = root.appendingPathComponent("Inbox", isDirectory: true)
        for dir in [paths.lutRoot, paths.templatesRoot, inbox] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        XCTAssertFalse(paths.lutRoot.path.hasPrefix("/Library/"))
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    var fileOperator: LocalFileOperator { LocalFileOperator(trashDirectory: paths.trashDirectory) }

    @discardableResult
    func write(_ relative: String, in base: URL? = nil, _ contents: String) throws -> URL {
        let url = (base ?? inbox).appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Zips `folder` (with the folder itself inside the zip, like Finder's Compress).
    func zip(_ folder: URL, to name: String) throws -> URL {
        let zip = inbox.appendingPathComponent(name)
        try Archive.create(from: folder, to: zip, keepParent: true)
        return zip
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
}

enum Fixtures {
    /// A tiny valid 2×2×2 identity cube.
    static let cube = """
    TITLE "Test"
    # comment
    LUT_3D_SIZE 2
    0 0 0
    1 0 0
    0 1 0
    1 1 0
    0 0 1
    1 0 1
    0 1 1
    1 1 1
    """
    /// Inverts colours.
    static let invertCube = """
    LUT_3D_SIZE 2
    1 1 1
    0 1 1
    1 0 1
    0 0 1
    1 1 0
    0 1 0
    1 0 0
    0 0 0
    """
    static let oneD = """
    LUT_1D_SIZE 3
    0 0 0
    0.25 0.25 0.25
    1 1 1
    """
    static let title = """
    {
        Tools = ordered() {
            Template = TextPlus { Inputs = { StyledText = Input { Value = "Hello" } } }
        }
    }
    """
    static let plainSetting = """
    {
        Tools = ordered() { Blur1 = Blur { } }
    }
    """
    static let dctl = "__DEVICE__ float3 transform(int p_Width, int p_Height, int p_X, int p_Y, float p_R, float p_G, float p_B) { return make_float3(p_R, p_G, p_B); }"
}
