import XCTest
@testable import Loadout

final class CubeLUTTests: XCTestCase {
    func testIdentity3D() throws {
        let lut = try CubeLUT(text: Fixtures.cube)
        XCTAssertEqual(lut.size, 2)
        XCTAssertTrue(lut.is3D)
        XCTAssertEqual(lut.title, "Test")
        let out = lut.apply(SIMD3(0.25, 0.5, 0.75))
        XCTAssertEqual(out.x, 0.25, accuracy: 1e-5)
        XCTAssertEqual(out.y, 0.5, accuracy: 1e-5)
        XCTAssertEqual(out.z, 0.75, accuracy: 1e-5)
    }

    func testInvert() throws {
        let lut = try CubeLUT(text: Fixtures.invertCube)
        let out = lut.apply(SIMD3(0.2, 0.3, 0.9))
        XCTAssertEqual(out.x, 0.8, accuracy: 1e-5)
        XCTAssertEqual(out.y, 0.7, accuracy: 1e-5)
        XCTAssertEqual(out.z, 0.1, accuracy: 1e-5)
    }

    func test1D() throws {
        let lut = try CubeLUT(text: Fixtures.oneD)
        XCTAssertFalse(lut.is3D)
        XCTAssertEqual(lut.apply(SIMD3(repeating: 0.5)).x, 0.25, accuracy: 1e-5)
        XCTAssertEqual(lut.apply(SIMD3(repeating: 0.75)).x, 0.625, accuracy: 1e-5)
        let cube = lut.colorCubeData()
        XCTAssertEqual(cube.data.count, cube.dimension * cube.dimension * cube.dimension * 4 * MemoryLayout<Float>.size)
    }

    func testBadData() {
        XCTAssertThrowsError(try CubeLUT(text: "hello"))
        XCTAssertThrowsError(try CubeLUT(text: "LUT_3D_SIZE 2\n0 0 0\n"))
        XCTAssertThrowsError(try CubeLUT(text: "LUT_3D_SIZE 2\n0 0 zero\n"))
    }

    func testPreviewRenders() throws {
        let box = try Sandbox()
        let url = try box.write("Invert.cube", Fixtures.invertCube)
        for frame in SampleFrame.allCases {
            let images = try XCTUnwrap(LUTPreview.image(for: url, frame: frame))
            XCTAssertEqual(images.after.width, 640)
        }
    }

    func testResolveDetectorIgnoresOtherApps() throws {
        let box = try Sandbox()
        let fake = box.root.appendingPathComponent("Apps/DaVinci Resolve/DaVinci Resolve.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: fake, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "com.blackmagic-design.DaVinciResolve",
                                   "CFBundleShortVersionString": "19.1.3", "CFBundlePackageType": "APPL"]
        try (info as NSDictionary).write(to: fake.appendingPathComponent("Info.plist"))
        let other = box.root.appendingPathComponent("Apps/Other.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try (["CFBundleIdentifier": "com.example.other"] as NSDictionary).write(to: other.appendingPathComponent("Info.plist"))
        let found = ResolveDetector.find(in: [box.root.appendingPathComponent("Apps")])
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.version, "19.1.3")
        XCTAssertEqual(found.first?.isStudio, false)
        XCTAssertEqual(found.first?.displayName, "DaVinci Resolve 19.1.3")
    }
}
