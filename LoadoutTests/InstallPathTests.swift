import XCTest
@testable import Loadout

final class InstallPathTests: XCTestCase {
    func testSystemPaths() {
        let p = ResolvePaths.system
        XCTAssertEqual(p.lutRoot.path, "/Library/Application Support/Blackmagic Design/DaVinci Resolve/LUT")
        XCTAssertTrue(p.templatesRoot.path.hasSuffix("Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Templates"))
        XCTAssertTrue(p.supportRoot.path.hasSuffix("Library/Application Support/Loadout"))
        XCTAssertTrue(p.parkedRoot.path.hasSuffix("Application Support/Loadout/Parked"))
        XCTAssertFalse(p.isSandboxed)
        XCTAssertTrue(p.mayNeedAdmin(p.lutRoot.appendingPathComponent("x.cube")))
        XCTAssertFalse(p.mayNeedAdmin(p.templatesRoot.appendingPathComponent("x.drfx")))
    }

    func testMapping() {
        let p = ResolvePaths.sandbox(at: URL(fileURLWithPath: "/tmp/LoadoutPathTest"))
        let root = p.lutRoot.deletingLastPathComponent().path
        XCTAssertEqual(p.destination(for: .lut, pack: "ATL Nights", fileName: "Neon.cube").path,
                       root + "/LUT/Loadout/ATL Nights/Neon.cube")
        XCTAssertEqual(p.destination(for: .lut, pack: "ATL Nights", fileName: "Neon.CUBE", subpath: ["Log"]).path,
                       root + "/LUT/Loadout/ATL Nights/Log/Neon.cube")
        XCTAssertEqual(p.destination(for: .dctl, pack: "Tools", fileName: "Grain.dctl").path,
                       root + "/LUT/Loadout/Tools/Grain.dctl")
        XCTAssertEqual(p.destination(for: .title, pack: "Kit", fileName: "Lower.setting").path,
                       root + "/Fusion/Templates/Edit/Titles/Kit/Lower.setting")
        XCTAssertEqual(p.destination(for: .transition, pack: "Kit", fileName: "Swipe.setting").path,
                       root + "/Fusion/Templates/Edit/Transitions/Kit/Swipe.setting")
        XCTAssertEqual(p.destination(for: .effect, pack: "Kit", fileName: "Glow.setting").path,
                       root + "/Fusion/Templates/Edit/Effects/Kit/Glow.setting")
        XCTAssertEqual(p.destination(for: .generator, pack: "Kit", fileName: "Bg.setting").path,
                       root + "/Fusion/Templates/Edit/Generators/Kit/Bg.setting")
        XCTAssertEqual(p.destination(for: .bundle, pack: "Kit", fileName: "Kit.DRFX").path,
                       root + "/Fusion/Templates/Kit.drfx")
    }

    func testUnsafePackNames() {
        XCTAssertEqual(ResolvePaths.safeFolderName("a/b:c"), "a-b-c")
        XCTAssertEqual(ResolvePaths.safeFolderName("  ..hidden "), "hidden")
        XCTAssertEqual(ResolvePaths.safeFolderName("   "), "Untitled Pack")
    }

    func testParkingRoundTrip() {
        let p = ResolvePaths.sandbox(at: URL(fileURLWithPath: "/tmp/LoadoutPathTest"))
        let home = p.destination(for: .lut, pack: "Pack", fileName: "a.cube", subpath: ["Log"])
        let parked = p.parkedURL(forHome: home)!
        XCTAssertEqual(parked.path, p.parkedLUTRoot.path + "/Loadout/Pack/Log/a.cube")
        XCTAssertEqual(p.homeURL(forParked: parked), home)
        let t = p.destination(for: .title, pack: "Kit", fileName: "x.setting")
        XCTAssertEqual(p.parkedURL(forHome: t)!.path, p.parkedTemplatesRoot.path + "/Edit/Titles/Kit/x.setting")
        XCTAssertNil(p.parkedURL(forHome: URL(fileURLWithPath: "/Users/x/Desktop/a.cube")))
        XCTAssertFalse(p.mayNeedAdmin(home), "the sandbox never asks for a password")
    }
}
