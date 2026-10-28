import XCTest
@testable import Loadout

final class TypeDetectionTests: XCTestCase {
    var box: Sandbox!
    override func setUpWithError() throws { box = try Sandbox() }
    override func tearDown() { box = nil }

    func testLUTsAndDCTLs() throws {
        XCTAssertEqual(TypeDetector.classify(try box.write("a.cube", Fixtures.cube)), .asset(.lut))
        XCTAssertEqual(TypeDetector.classify(try box.write("A.CUBE", Fixtures.cube)), .asset(.lut))
        XCTAssertEqual(TypeDetector.classify(try box.write("b.3dl", "0 512 1023\n")), .asset(.lut))
        XCTAssertEqual(TypeDetector.classify(try box.write("c.dctl", Fixtures.dctl)), .asset(.dctl))
        XCTAssertEqual(TypeDetector.classify(try box.write("d.dctle", "x")), .asset(.dctl))
    }

    func testFakeAndDoubleExtensionsAreRejected() throws {
        if case .rejected = TypeDetector.classify(try box.write("look.cube.txt", Fixtures.cube)) {} else {
            XCTFail(".cube.txt should be rejected")
        }
        if case .rejected = TypeDetector.classify(try box.write("fake.cube", "<html>not a lut</html>")) {} else {
            XCTFail("a .cube without LUT_3D_SIZE should be rejected")
        }
    }

    func testJunk() throws {
        XCTAssertEqual(TypeDetector.classify(try box.write("readme.txt", "hi")), .junk)
        XCTAssertEqual(TypeDetector.classify(try box.write("preview.jpg", "x")), .junk)
        XCTAssertEqual(TypeDetector.classify(try box.write("LICENSE", "x")), .junk)
        XCTAssertEqual(TypeDetector.classify(try box.write(".DS_Store", "x")), .junk)
        XCTAssertEqual(TypeDetector.classify(try box.write("._a.cube", "x")), .junk)
        XCTAssertTrue(TypeDetector.isJunkPath(["Pack", "__MACOSX", "a.cube"]))
        XCTAssertEqual(TypeDetector.classify(try box.write("thing.exe", "x")), .unsupported)
    }

    func testTemplatesByFolder() throws {
        let t = try box.write("Pack/Titles/Lower Thirds/a.setting", Fixtures.plainSetting)
        XCTAssertEqual(TypeDetector.classify(t, components: ["Pack", "Titles", "Lower Thirds", "a.setting"]), .asset(.title))
        let tr = try box.write("Pack/Transitions/b.setting", Fixtures.plainSetting)
        XCTAssertEqual(TypeDetector.classify(tr, components: ["Pack", "Transitions", "b.setting"]), .asset(.transition))
        let g = try box.write("Pack/Generators/c.setting", Fixtures.plainSetting)
        XCTAssertEqual(TypeDetector.classify(g, components: ["Pack", "Generators", "c.setting"]), .asset(.generator))
        let e = try box.write("Pack/Effects/d.setting", Fixtures.plainSetting)
        XCTAssertEqual(TypeDetector.classify(e, components: ["Pack", "Effects", "d.setting"]), .asset(.effect))
        // "Textures" isn't "text".
        let x = try box.write("Pack/Textures/e.setting", Fixtures.plainSetting)
        XCTAssertEqual(TypeDetector.classify(x, components: ["Pack", "Textures", "e.setting"]), .unsortedTemplate)
    }

    func testTitleByContents() throws {
        let t = try box.write("Loose/x.setting", Fixtures.title)
        XCTAssertEqual(TypeDetector.classify(t, components: ["Loose", "x.setting"]), .asset(.title))
    }

    func testDrfxAndZip() throws {
        XCTAssertEqual(TypeDetector.classify(try box.write("p.drfx", "x")), .asset(.bundle))
        XCTAssertEqual(TypeDetector.classify(try box.write("p.zip", "x")), .archive)
    }

    func testRefreshNeeds() {
        XCTAssertEqual(AssetKind.lut.refresh, .updateLists)
        XCTAssertEqual(AssetKind.dctl.refresh, .restart)
        XCTAssertEqual(AssetKind.title.refresh, .restart)
        XCTAssertEqual(AssetKind.bundle.refresh, .restart)
        XCTAssertEqual([ResolveRefresh.updateLists, .restart, .none].max(), .restart)
    }
}
