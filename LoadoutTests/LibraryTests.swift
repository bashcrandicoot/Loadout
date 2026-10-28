import XCTest
@testable import Loadout

final class LibraryTests: XCTestCase {
    var box: Sandbox!
    override func setUpWithError() throws { box = try Sandbox() }
    override func tearDown() { box = nil }

    private func install(_ urls: [URL], pack: String, policy: ConflictPolicy = .replace,
                         index: inout LibraryIndex) throws -> InstallReport {
        let scan = try PackScanner(stagingRoot: box.root.appendingPathComponent("Staging")).scan(urls)
        defer { scan.cleanUp() }
        let installer = Installer(paths: box.paths)
        var options = InstallOptions(packName: pack)
        options.conflictPolicy = policy
        let plan = installer.plan(scan, options: options, index: index)
        return try installer.install(plan, options: options, sourceName: urls[0].lastPathComponent, index: &index, using: box.fileOperator)
    }

    func testInstallScanDisableEnableRemove() throws {
        let src = box.root.appendingPathComponent("Src/Pack", isDirectory: true)
        try box.write("Neon.cube", in: src, Fixtures.cube)
        try box.write("Titles/Lower.setting", in: src, Fixtures.plainSetting)
        try box.write("Grain.dctl", in: src, Fixtures.dctl)
        var index = LibraryIndex()
        let report = try install([src], pack: "Pack", index: &index)
        XCTAssertEqual(report.installed.count, 3)
        XCTAssertEqual(report.refresh, .restart)
        XCTAssertEqual(report.whatInstalled, "1 LUT, 1 DCTL, and 1 title")
        let lut = box.paths.destination(for: .lut, pack: "Pack", fileName: "Neon.cube")
        let title = box.paths.destination(for: .title, pack: "Pack", fileName: "Lower.setting")
        XCTAssertTrue(box.exists(lut))
        XCTAssertTrue(box.exists(title))
        XCTAssertTrue(box.exists(src.appendingPathComponent("Neon.cube")), "the original stays where it was")

        // Index round trip (the [AssetKind: Int] dictionary included).
        try IndexStore(url: box.paths.indexURL).save(index)
        let loaded = IndexStore(url: box.paths.indexURL).load()
        XCTAssertEqual(loaded.packs.map(\.id), index.packs.map(\.id))
        XCTAssertEqual(loaded.files.map(\.id), index.files.map(\.id))
        XCTAssertEqual(loaded.files.map(\.homePath), index.files.map(\.homePath))
        XCTAssertEqual(loaded.files.map(\.kind), index.files.map(\.kind))
        XCTAssertEqual(loaded.files.map { Int($0.installedAt.timeIntervalSince1970) },
                       index.files.map { Int($0.installedAt.timeIntervalSince1970) })
        var withBundle = index
        withBundle.files[0].bundleContents = [.title: 2, .transition: 1]
        try IndexStore(url: box.paths.indexURL).save(withBundle)
        XCTAssertEqual(IndexStore(url: box.paths.indexURL).load().files[0].bundleContents, [.title: 2, .transition: 1])

        let scanner = LibraryScanner(paths: box.paths)
        var items = scanner.scan(index: index)
        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items.allSatisfy { $0.state == .enabled && $0.isManaged && $0.group == "Pack" })

        // Disable: out of Resolve's folders, into Parked with the same relative path.
        let actions = LibraryActions(paths: box.paths)
        let lutItem = try XCTUnwrap(items.first { $0.kind == .lut })
        try actions.disable([lutItem], using: box.fileOperator)
        XCTAssertFalse(box.exists(lut))
        let parked = try XCTUnwrap(box.paths.parkedURL(forHome: lut))
        XCTAssertTrue(box.exists(parked))
        items = scanner.scan(index: index)
        let off = try XCTUnwrap(items.first { $0.kind == .lut })
        XCTAssertEqual(off.state, .disabled)
        XCTAssertEqual(off.currentURL.path, parked.path)
        XCTAssertEqual(off.homeURL.path, lut.path)

        // Enable: back exactly where it was.
        try actions.enable([off], using: box.fileOperator)
        XCTAssertTrue(box.exists(lut))
        XCTAssertFalse(box.exists(parked))
        items = scanner.scan(index: index)
        XCTAssertTrue(items.allSatisfy { $0.state == .enabled })

        // Remove: to the (sandbox) Trash, and out of the index.
        let titleItem = try XCTUnwrap(items.first { $0.kind == .title })
        try actions.remove([titleItem], index: &index, using: box.fileOperator)
        XCTAssertFalse(box.exists(title))
        XCTAssertTrue(box.exists(box.paths.trashDirectory!.appendingPathComponent("Lower.setting")))
        XCTAssertFalse(box.exists(title.deletingLastPathComponent()), "the empty pack folder is cleaned up")
        XCTAssertEqual(index.files.count, 2)
        XCTAssertEqual(scanner.scan(index: index).count, 2)

        // Remove the rest: the pack goes too.
        try actions.remove(scanner.scan(index: index), index: &index, using: box.fileOperator)
        XCTAssertTrue(index.packs.isEmpty)
        XCTAssertTrue(scanner.scan(index: index).isEmpty)
    }

    func testRemovingAParkedItem() throws {
        let file = try box.write("Warm.cube", Fixtures.cube)
        var index = LibraryIndex()
        _ = try install([file], pack: "Looks", index: &index)
        let actions = LibraryActions(paths: box.paths)
        let scanner = LibraryScanner(paths: box.paths)
        try actions.disable(scanner.scan(index: index), using: box.fileOperator)
        let parked = scanner.scan(index: index)
        XCTAssertEqual(parked.first?.state, .disabled)
        try actions.remove(parked, index: &index, using: box.fileOperator)
        XCTAssertTrue(scanner.scan(index: index).isEmpty)
        XCTAssertTrue(index.files.isEmpty)
    }

    func testMissingFile() throws {
        let file = try box.write("Warm.cube", Fixtures.cube)
        var index = LibraryIndex()
        let report = try install([file], pack: "Looks", index: &index)
        try FileManager.default.removeItem(at: report.installed[0].homeURL)
        let items = LibraryScanner(paths: box.paths).scan(index: index)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].state, .missing)
    }

    func testUnmanagedAndBuiltIns() throws {
        // Files Resolve or the user put there.
        try box.write("ACES/ACES Proxy.cube", in: box.paths.lutRoot, Fixtures.cube)
        try box.write("Film Looks/Rec709 Kodak.cube", in: box.paths.lutRoot, Fixtures.cube)
        try box.write("VLog_to_V709.ilut", in: box.paths.lutRoot, "x")
        try box.write("LUTs by IWLTBAP (CUBE)/Aspen.cube", in: box.paths.lutRoot, Fixtures.cube)
        try box.write("Edit/Titles/HTML Titles/Big.setting", in: box.paths.templatesRoot, Fixtures.title)
        try box.write("Edit/Titles/Loose.setting", in: box.paths.templatesRoot, Fixtures.title)
        try box.write("Fusion Kit.drfx", in: box.paths.templatesRoot, "x")
        try box.write("Edit/Titles/notes.txt", in: box.paths.templatesRoot, "x")
        try box.write("Comp/Thing.setting", in: box.paths.templatesRoot, "x")

        let items = LibraryScanner(paths: box.paths).scan(index: LibraryIndex())
        func item(_ name: String) -> Loadout.LibraryItem? { items.first { $0.name == name } }
        XCTAssertEqual(items.count, 7)
        XCTAssertTrue(try XCTUnwrap(item("ACES Proxy")).isBuiltIn)
        XCTAssertTrue(try XCTUnwrap(item("Rec709 Kodak")).isBuiltIn)
        XCTAssertTrue(try XCTUnwrap(item("VLog_to_V709")).isBuiltIn)
        let aspen = try XCTUnwrap(item("Aspen"))
        XCTAssertFalse(aspen.isBuiltIn)
        XCTAssertFalse(aspen.isManaged)
        XCTAssertEqual(aspen.group, "LUTs by IWLTBAP (CUBE)")
        XCTAssertEqual(item("Big")?.kind, .title)
        XCTAssertEqual(item("Big")?.group, "HTML Titles")
        XCTAssertEqual(item("Loose")?.group, "Titles")
        XCTAssertEqual(item("Fusion Kit")?.kind, .bundle)

        // Built-ins can't be turned off or removed.
        let actions = LibraryActions(paths: box.paths)
        XCTAssertThrowsError(try actions.disableOps([item("ACES Proxy")!]))
        XCTAssertThrowsError(try actions.removeOps([item("ACES Proxy")!]))
        // Other people's files can be turned off and on again.
        try actions.disable([aspen], using: box.fileOperator)
        let off = try XCTUnwrap(LibraryScanner(paths: box.paths).scan(index: LibraryIndex()).first { $0.name == "Aspen" })
        XCTAssertEqual(off.state, .disabled)
        try actions.enable([off], using: box.fileOperator)
        XCTAssertTrue(box.exists(aspen.homeURL))
    }

    func testConflicts() throws {
        let v2 = box.root.appendingPathComponent("Src/v2/ATL Nights", isDirectory: true)
        try box.write("Neon.cube", in: v2, Fixtures.cube)
        try box.write("Sodium.cube", in: v2, Fixtures.cube)
        var index = LibraryIndex()
        _ = try install([v2], pack: "ATL Nights", index: &index)
        let packID = index.packs[0].id

        let v3 = box.root.appendingPathComponent("Src/v3/ATL Nights", isDirectory: true)
        try box.write("Neon.cube", in: v3, Fixtures.invertCube)
        try box.write("Teal.cube", in: v3, Fixtures.cube)

        // Plan: one file replaces the same pack's.
        let scan = try PackScanner(stagingRoot: box.root.appendingPathComponent("Staging")).scan([v3])
        let plan = Installer(paths: box.paths).plan(scan, options: InstallOptions(packName: "ATL Nights"), index: index)
        XCTAssertEqual(plan.filter { $0.conflict == .samePack }.count, 1)

        // Skip leaves the old file.
        var skipIndex = index
        let skipped = try install([v3], pack: "ATL Nights", policy: .skip, index: &skipIndex)
        XCTAssertEqual(skipped.skipped, 1)
        let neon = box.paths.destination(for: .lut, pack: "ATL Nights", fileName: "Neon.cube")
        XCTAssertEqual(try String(contentsOf: neon), Fixtures.cube)

        // Keep both numbers the new one.
        var bothIndex = skipIndex
        _ = try install([v3], pack: "ATL Nights", policy: .keepBoth, index: &bothIndex)
        XCTAssertTrue(box.exists(neon.deletingLastPathComponent().appendingPathComponent("Neon 2.cube")))

        // Replace trashes the old one and records the new one once, in the same pack.
        var replaceIndex = bothIndex
        let replaced = try install([v3], pack: "ATL Nights", policy: .replace, index: &replaceIndex)
        XCTAssertEqual(replaced.replaced, 2, "Neon and Teal were both there by now")
        XCTAssertEqual(try String(contentsOf: neon), Fixtures.invertCube)
        XCTAssertTrue(box.exists(box.paths.trashDirectory!.appendingPathComponent("Neon.cube")))
        XCTAssertEqual(replaceIndex.packs.count, 1)
        XCTAssertEqual(replaceIndex.packs[0].id, packID)
        XCTAssertEqual(replaceIndex.files.filter { $0.homePath == neon.path }.count, 1)

        // A file someone else put there is an "unmanaged" conflict.
        try box.write("Loadout/Other/Mine.cube", in: box.paths.lutRoot, Fixtures.cube)
        let mine = try box.write("Mine.cube", Fixtures.cube)
        let scan2 = try PackScanner(stagingRoot: box.root.appendingPathComponent("Staging")).scan([mine])
        let plan2 = Installer(paths: box.paths).plan(scan2, options: InstallOptions(packName: "Other"), index: replaceIndex)
        XCTAssertEqual(plan2.first?.conflict, .unmanaged)
    }

    func testRollbackOnFailure() throws {
        let src = box.root.appendingPathComponent("Src/Pack", isDirectory: true)
        let a = try box.write("A.cube", in: src, Fixtures.cube)
        let missing = src.appendingPathComponent("Gone.cube")
        let destA = box.paths.destination(for: .lut, pack: "Pack", fileName: "A.cube")
        let destB = box.paths.destination(for: .lut, pack: "Pack", fileName: "Gone.cube")
        let ops: [FileOp] = [.makeDirectory(destA.deletingLastPathComponent()), .copy(from: a, to: destA), .copy(from: missing, to: destB)]
        XCTAssertThrowsError(try box.fileOperator.perform(ops))
        XCTAssertFalse(box.exists(destA))
        XCTAssertFalse(box.exists(destA.deletingLastPathComponent()))
    }

    func testPrivilegedScriptQuoting() {
        let script = PrivilegedFileOperator.shellScript(
            for: [.makeDirectory(URL(fileURLWithPath: "/L/Bob's Pack")),
                  .copy(from: URL(fileURLWithPath: "/in/a.cube"), to: URL(fileURLWithPath: "/L/Bob's Pack/a.cube"))],
            userID: 501, groupID: 20, trash: URL(fileURLWithPath: "/Users/x/.Trash"))
        XCTAssertTrue(script.hasPrefix("set -e\n"))
        XCTAssertTrue(script.contains("mkdir -p '/L/Bob'\\''s Pack'"))
        XCTAssertTrue(script.contains("chown 501:20"))
        XCTAssertTrue(script.contains("mv -f"))
        XCTAssertEqual(PrivilegedFileOperator.appleScriptString("a \"b\" \\"), "\"a \\\"b\\\" \\\\\"")
    }
}
