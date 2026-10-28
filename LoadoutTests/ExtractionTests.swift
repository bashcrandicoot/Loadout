import XCTest
@testable import Loadout

final class ExtractionTests: XCTestCase {
    var box: Sandbox!
    override func setUpWithError() throws { box = try Sandbox() }
    override func tearDown() { box = nil }

    private var scanner: PackScanner { PackScanner(stagingRoot: box.root.appendingPathComponent("Staging")) }

    /// A creator-style pack: LUTs in subfolders, templates, a drfx, readmes and Mac junk.
    private func makePack() throws -> URL {
        let src = box.root.appendingPathComponent("Src/ATL_Nights_v3", isDirectory: true)
        try box.write("LUTs/Log/Neon.cube", in: src, Fixtures.cube)
        try box.write("LUTs/Rec709/Neon.cube", in: src, Fixtures.cube)
        try box.write("LUTs/Rec709/Sodium.cube", in: src, Fixtures.cube)
        try box.write("Titles/Lower Third.setting", in: src, Fixtures.plainSetting)
        try box.write("Transitions/Swipe.setting", in: src, Fixtures.plainSetting)
        try box.write("Readme.pdf", in: src, "x")
        try box.write("previews/Neon.jpg", in: src, "x")
        try box.write("__MACOSX/LUTs/._Neon.cube", in: src, "x")
        try box.write("Bad.cube.txt", in: src, Fixtures.cube)
        try box.write("Plugin.fuse", in: src, "x")
        // A drfx is a zip, but it stays zipped.
        let drfxSrc = box.root.appendingPathComponent("Src/DrfxSrc", isDirectory: true)
        try box.write("Edit/Titles/Kit/A.setting", in: drfxSrc, Fixtures.title)
        try box.write("Edit/Titles/Kit/B.setting", in: drfxSrc, Fixtures.title)
        try box.write("Edit/Transitions/Kit/C.setting", in: drfxSrc, Fixtures.plainSetting)
        try Archive.create(from: drfxSrc, to: src.appendingPathComponent("Kit.drfx"), keepParent: false)
        return src
    }

    func testFolderScan() throws {
        let scan = try scanner.scan([try makePack()])
        XCTAssertEqual(scan.count(of: .lut), 3)
        XCTAssertEqual(scan.count(of: .title), 1)
        XCTAssertEqual(scan.count(of: .transition), 1)
        XCTAssertEqual(scan.count(of: .bundle), 1)
        XCTAssertEqual(scan.rejected.count, 1)
        XCTAssertEqual(scan.unsupported.count, 1)
        XCTAssertGreaterThanOrEqual(scan.ignoredCount, 3)
        XCTAssertEqual(scan.suggestedPackName, "ATL Nights v3")
        XCTAssertNil(scan.stagingFolder)
        // "LUTs" is structural and dropped; Log/Rec709 are kept so same-named LUTs don't collide.
        let subpaths = Set(scan.items.filter { $0.kind == .lut }.map { $0.subpath.joined(separator: "/") })
        XCTAssertEqual(subpaths, ["Log", "Rec709"])
        let drfx = try XCTUnwrap(scan.items.first { $0.kind == .bundle })
        XCTAssertEqual(drfx.bundleContents[.title], 2)
        XCTAssertEqual(drfx.bundleContents[.transition], 1)
        XCTAssertEqual(scan.headline, "Found 3 LUTs, 1 title, 1 transition, and 1 .drfx bundle")
    }

    func testZipAndNestedZip() throws {
        let src = try makePack()
        // The pack zipped, then put in another zip with an extra LUT (like a store download).
        let inner = try box.zip(src, to: "ATL_Nights_v3.zip")
        let outerSrc = box.root.appendingPathComponent("Src/Bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: outerSrc, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: inner, to: outerSrc.appendingPathComponent("ATL_Nights_v3.zip"))
        try box.write("Bonus/Bonus.cube", in: outerSrc, Fixtures.cube)
        let outer = try box.zip(outerSrc, to: "Everything.zip")

        let scan = try scanner.scan([outer])
        defer { scan.cleanUp() }
        XCTAssertEqual(scan.count(of: .lut), 4)
        XCTAssertEqual(scan.count(of: .bundle), 1, "the .drfx is kept whole")
        XCTAssertEqual(scan.count(of: .title), 1)
        XCTAssertFalse(scan.items.contains { $0.displayPath.contains("__MACOSX") })
        XCTAssertEqual(scan.suggestedPackName, "Everything")
        let staging = try XCTUnwrap(scan.stagingFolder)
        XCTAssertTrue(box.exists(staging))
        scan.cleanUp()
        XCTAssertFalse(box.exists(staging))
    }

    func testFinderZipWithMacJunk() throws {
        let src = box.root.appendingPathComponent("Src/Looks", isDirectory: true)
        try box.write("Warm.cube", in: src, Fixtures.cube)
        try box.write("__MACOSX/._Warm.cube", in: src, "junk")
        try box.write(".DS_Store", in: src, "junk")
        let zip = try box.zip(src, to: "Looks.zip")
        let scan = try scanner.scan([zip])
        defer { scan.cleanUp() }
        XCTAssertEqual(scan.items.count, 1)
        XCTAssertEqual(scan.items.first?.fileName, "Warm.cube")
        XCTAssertEqual(scan.items.first?.subpath, [])
    }

    func testLooseUnsortedSetting() throws {
        let file = try box.write("Mystery.setting", Fixtures.plainSetting)
        let scan = try scanner.scan([file])
        XCTAssertEqual(scan.unsortedTemplates.count, 1)
        XCTAssertEqual(scan.headline, "Found 1 Fusion template")
    }

    func testNothingUseful() throws {
        let file = try box.write("notes.txt", "x")
        let scan = try scanner.scan([file])
        XCTAssertTrue(scan.items.isEmpty)
        XCTAssertEqual(scan.headline, "Nothing to install")
    }
}
