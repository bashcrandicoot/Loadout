import XCTest
@testable import Loadout

/// Maddy's case-sort animation: her numbers, the real-progress driver, and the header.
final class CaseSortTests: XCTestCase {
    private let dt = 1.0 / 60

    /// Steps a driver with a progress curve until it settles (or `limit` seconds).
    @discardableResult
    private func play(_ driver: CaseSortDriver, limit: Double = 40, progress: (Double) -> Double, finishedAt: Double,
                      check: (Double, CaseSortDriver, Double) -> Void = { _, _, _ in }) -> [(Double, CaseSortEvent)] {
        var events: [(Double, CaseSortEvent)] = []
        var t = 0.0
        while t < limit && !driver.isSettled {
            t += dt
            let real = t >= finishedAt ? 1 : progress(t)
            for event in driver.advance(by: dt, progress: real, finished: t >= finishedAt) { events.append((t, event)) }
            check(t, driver, real)
        }
        XCTAssertTrue(driver.isSettled, "never settled")
        return events
    }

    // MARK: Her numbers

    func testEasingMatchesHerHelpers() {
        XCTAssertEqual(CaseSort.easeOutCubic(0.5), 0.875, accuracy: 1e-12)
        XCTAssertEqual(CaseSort.easeInOutCubic(0.25), 0.0625, accuracy: 1e-12)
        XCTAssertEqual(CaseSort.easeInOutCubic(0.75), 0.9375, accuracy: 1e-12)
        XCTAssertEqual(CaseSort.easeOutBack(1, 1.6), 1, accuracy: 1e-12)
        XCTAssertGreaterThan(CaseSort.easeOutBack(0.7, 1.6), 1, "overshoots before settling")
        XCTAssertEqual(CaseSort.bump(0.42, 0.5, 0.46), 1, accuracy: 1e-12)
        XCTAssertEqual(CaseSort.bump(0.42, 0.5, 0.5), 0)
        XCTAssertEqual(CaseSort.smooth(0.8, 0.95, 0.875), 0.5, accuracy: 1e-12)
    }

    func testDemoLayoutIsHers() {
        let layout = CaseSortLayout.demo
        XCTAssertEqual(layout.cards.map(\.art), CaseSortArt.allCases)
        XCTAssertEqual(layout.cards.map(\.start.x), [26, 48, 70, 92, 134, 170, 214, 252, 292])
        XCTAssertEqual(layout.cards.map(\.start.rotation), [-8, -3, 2, 7, -4, 5, -5, 3, 6])
        XCTAssertEqual(layout.window, 0.22, accuracy: 1e-9)
        XCTAssertEqual(layout.minimumDuration, 5.4, accuracy: 1e-9)
        for (i, card) in layout.cards.enumerated() {
            XCTAssertEqual(card.windowStart, Double(i) * (1 - 0.22) / 8, accuracy: 1e-9)
        }
        for (edge, hers) in zip(layout.edges, [338, 407.6, 477.2, 546.8, 616.4, 686]) { XCTAssertEqual(edge, hers, accuracy: 1e-9) }
        // lut0: centre of segment 0 minus 5, 64 showing; scale 70·sc/150.
        let lut0 = layout.cards[0]
        let hu = 196.0 * 70 / 150
        let sc = 0.205
        XCTAssertEqual(lut0.slot.x, 404 - 512 * sc + (372.8 - 5) * sc, accuracy: 1e-9)
        XCTAssertEqual(lut0.slot.y, 103 - 712 * sc + (498 - 64 + hu / 2) * sc, accuracy: 1e-9)
        XCTAssertEqual(lut0.slot.scale, 70 * sc / 150, accuracy: 1e-12)
        XCTAssertEqual(lut0.start.y, 100 - 196 * (31.0 / 150) / 2 - 1, accuracy: 1e-9)
    }

    func testDemoClockIsHers() {
        XCTAssertEqual(CaseSort.demoPhases(at: 1.25).open, 0.5, accuracy: 1e-9)
        XCTAssertEqual(CaseSort.demoPhases(at: 1.25).progress, 0)
        XCTAssertEqual(CaseSort.demoPhases(at: 7.9).arrival, 0.5, accuracy: 1e-9)
        XCTAssertEqual(CaseSort.demoPhases(at: 0.5, uninstall: true), .installed)
        XCTAssertEqual(CaseSort.demoPhases(at: 9.8, uninstall: true), .ready)
    }

    func testPoseFliesFromDeskToSlotAndSinksOnArrival() {
        let layout = CaseSortLayout.demo
        let window = layout.window
        XCTAssertEqual(layout.pose(0, progress: 0, arrival: 0), layout.cards[0].start)
        XCTAssertEqual(layout.pose(0, progress: 0.05 * window, arrival: 0).layer, .desk)
        XCTAssertEqual(layout.pose(0, progress: 0.5 * window, arrival: 0).layer, .flying)
        let landed = layout.pose(0, progress: window, arrival: 0)
        XCTAssertEqual(landed.layer, .inCase)
        XCTAssertEqual(landed.x, layout.cards[0].slot.x, accuracy: 1e-9)
        XCTAssertEqual(landed.y, layout.cards[0].slot.y, accuracy: 1e-9)
        XCTAssertEqual(landed.glow, 0, accuracy: 1e-9)
        let sunk = layout.pose(0, progress: 1, arrival: 0.3)
        XCTAssertEqual(sunk.y - landed.y, 95 * 0.205, accuracy: 1e-9, "sinks under the lid as it shuts")
    }

    func testBarSegmentsFillAsTheirCardsLand() {
        let layout = CaseSortLayout.demo
        XCTAssertEqual(layout.segmentFills(0), [0, 0, 0, 0, 0])
        XCTAssertEqual(layout.segmentFills(1), [1, 1, 1, 1, 1])
        // The first LUT lands at 0.95 of its window: a quarter of the LUT segment.
        XCTAssertEqual(layout.segmentFills(0.95 * layout.window)[0], 0.25, accuracy: 1e-9)
        XCTAssertEqual(layout.segmentFills(0.79 * layout.window)[0], 0, "nothing fills before a card lands")
        var last = 0.0
        for k in 0...200 {
            let fill = layout.barFill(Double(k) / 200)
            XCTAssertGreaterThanOrEqual(fill, last - 1e-12)
            last = fill
        }
        XCTAssertGreaterThan(layout.segmentPulses(0.9 * layout.window)[0], 0)
        XCTAssertLessThan(layout.segmentPulses(1).max()!, 1e-9)
    }

    func testLidAndLatchesAtTheBeats() {
        XCTAssertEqual(CaseSort.lidAngle(.ready), 0)
        XCTAssertEqual(CaseSort.lidAngle(CaseSortPhases(open: 1, progress: 0.5, arrival: 0)), 100, accuracy: 1e-9)
        XCTAssertEqual(CaseSort.lidAngle(CaseSortPhases(open: 1, progress: 1, arrival: 0.42)), 0, accuracy: 1e-9)
        XCTAssertGreaterThan(CaseSort.lidAngle(CaseSortPhases(open: 1, progress: 1, arrival: 0.45)), 0, "bounces")
        XCTAssertEqual(CaseSort.lidAngle(.installed), 0)
        XCTAssertEqual(CaseSort.latchAngles(CaseSortPhases(open: 0.5, progress: 0, arrival: 0)).left, 180)
        XCTAssertEqual(CaseSort.latchAngles(CaseSortPhases(open: 0.5, progress: 0, arrival: 0)).right, 180)
        let a = CaseSortPhases(open: 1, progress: 1, arrival: 0.52)
        XCTAssertLessThan(CaseSort.latchAngles(a).left, 180)
        XCTAssertEqual(CaseSort.latchAngles(a).right, 180, "left snaps first")
        XCTAssertEqual(CaseSort.latchAngles(.installed).left, 0)
        XCTAssertEqual(CaseSort.latchAngles(.installed).right, 0)
        XCTAssertGreaterThan(CaseSort.glow(CaseSortPhases(open: 1, progress: 1, arrival: 0.7)), 0.9)
        XCTAssertEqual(CaseSort.glow(.installed), 0.38, accuracy: 1e-9)
    }

    // MARK: Cards for real installs

    func testKindsMapOntoHerFiveGroups() {
        XCTAssertEqual(CaseSortGroup(.lut), .luts)
        XCTAssertEqual(CaseSortGroup(.dctl), .looks)
        XCTAssertEqual(CaseSortGroup(.effect), .looks)
        XCTAssertEqual(CaseSortGroup(.generator), .looks)
        XCTAssertEqual(CaseSortGroup(.title), .titles)
        XCTAssertEqual(CaseSortGroup(.bundle), .bundles)
        XCTAssertEqual(CaseSortGroup(.transition), .transitions)
    }

    func testCardsAreSharedOutByCount() {
        let demo = CaseSortLayout.allocate([.luts: 24, .looks: 2, .titles: 6, .bundles: 1, .transitions: 2])
        XCTAssertEqual(demo.values.reduce(0, +), 9)
        XCTAssertEqual(demo[.luts], 4)
        XCTAssertTrue(demo.values.allSatisfy { $0 >= 1 && $0 <= 4 })
        XCTAssertEqual(CaseSortLayout.allocate([.titles: 2]), [.titles: 2], "never more cards than files")
        XCTAssertEqual(CaseSortLayout.allocate([.luts: 100]), [.luts: 4])
        let one = CaseSortLayout(kinds: [.lut])
        XCTAssertEqual(one.cards.count, 1)
        XCTAssertEqual(one.window, 1)
        XCTAssertEqual(one.edges, [338, 686])
        XCTAssertEqual(one.cards[0].start.x, 159, "a lone card stands in the middle of her row")
    }

    func testOnlyPresentKindsGetSegments() {
        let layout = CaseSortLayout(kinds: [.title, .lut, .lut, .transition])
        XCTAssertEqual(layout.segments, [.luts, .titles, .transitions])
        XCTAssertEqual(layout.edges.count, 4)
        XCTAssertEqual(layout.cards.map(\.group), [.luts, .luts, .titles, .transitions])
        XCTAssertTrue(layout.cards.allSatisfy { $0.start.x > 0 && $0.start.x < 300 }, "cards stay on the desk, left of the case")
    }

    // MARK: Driver

    func testInstallNeverRunsAheadOfRealProgressAndKeepsHerPace() {
        let layout = CaseSortLayout.demo
        let driver = CaseSortDriver(direction: .install, layout: layout)
        var last = 0.0
        play(driver, progress: { min(1, $0 / 4) }, finishedAt: 4) { _, d, real in
            XCTAssertLessThanOrEqual(d.phases.progress, real + 1e-12)
            XCTAssertGreaterThanOrEqual(d.phases.progress, last)
            XCTAssertLessThanOrEqual(d.phases.progress - last, self.dt / layout.minimumDuration + 1e-9)
            if d.phases.open < CaseSort.progressStartsAt { XCTAssertEqual(d.phases.progress, 0) }
            if d.phases.progress < 1 { XCTAssertEqual(d.phases.arrival, 0) }
            last = d.phases.progress
        }
        XCTAssertEqual(driver.phases, .installed)
        XCTAssertEqual(driver.label, .installed)
    }

    func testInstantCopyStillPlaysTheWholeStoryInOrder() {
        let driver = CaseSortDriver(direction: .install, layout: .demo)
        let events = play(driver, progress: { _ in 1 }, finishedAt: 0)
        XCTAssertEqual(events.map(\.1), [.lidShut, .latchLeft, .latchRight])
        XCTAssertGreaterThan(events[0].0, 0.675 + 5.4, "cards keep her 5.4 s pace")
    }

    func testArrivalWaitsForTheInstallToFinish() {
        let driver = CaseSortDriver(direction: .install, layout: CaseSortLayout(kinds: [.lut]))
        for _ in 0..<600 { driver.advance(by: dt, progress: 1, finished: false) }
        XCTAssertEqual(driver.phases.progress, 1)
        XCTAssertEqual(driver.phases.arrival, 0, "the lid stays open until the index is saved")
    }

    func testUninstallIsTheStoryBackwards() {
        let layout = CaseSortLayout(kinds: [.lut, .lut, .title])
        let driver = CaseSortDriver(direction: .uninstall, layout: layout)
        XCTAssertEqual(driver.label, .installed)
        let events = play(driver, progress: { min(1, $0 / 2) }, finishedAt: 2) { _, d, real in
            XCTAssertGreaterThanOrEqual(d.phases.progress, 1 - real - 1e-12, "cards never leave before their files")
        }
        XCTAssertEqual(events.map(\.1), [.latchRight, .latchLeft, .lidOpen, .lidShut])
        XCTAssertEqual(driver.phases, .ready)
        XCTAssertEqual(driver.label, .removed)
    }

    func testReduceMotionCrossfadesWithoutFlightsOrHaptics() {
        let layout = CaseSortLayout.demo
        let driver = CaseSortDriver(direction: .install, layout: layout, reduced: true)
        driver.advance(by: dt, progress: 0.4, finished: false)
        XCTAssertEqual(driver.frame.layers.count, 1)
        XCTAssertEqual(driver.frame.layers[0].phases, .ready, "cards stay put")
        XCTAssertEqual(driver.frame.layers[0].bar, 0.4)
        XCTAssertEqual(driver.label, .working(0.4))
        driver.advance(by: 0.1, progress: 1, finished: true)
        XCTAssertEqual(driver.frame.layers.count, 2)
        XCTAssertEqual(driver.frame.layers[1].phases, .installed)
        let events = play(driver, progress: { _ in 1 }, finishedAt: 0)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(driver.frame.layers.map(\.phases), [.installed])
    }

    func testSafetyTimersOutlastTheAnimation() {
        for kinds in [[AssetKind.lut], Array(repeating: .lut, count: 40) + [.title, .dctl, .bundle, .transition]] {
            let layout = CaseSortLayout(kinds: kinds)
            for direction in [CaseSortDirection.install, .uninstall] {
                let driver = CaseSortDriver(direction: direction, layout: layout)
                var t = 0.0
                while !driver.isSettled && t < 60 { t += dt; driver.advance(by: dt, progress: 1, finished: true) }
                XCTAssertLessThanOrEqual(t, CaseSortDriver.longestDuration(direction, layout: layout) + 0.05)
            }
        }
    }

    // MARK: Header

    func testHeaderCountsAndSummary() {
        XCTAssertEqual(CaseSort.filesDone(0.5, of: 32), 16)
        XCTAssertEqual(CaseSort.filesDone(1, of: 32), 32)
        XCTAssertEqual(CaseSort.label(CaseSortPhases(open: 1, progress: 0.25, arrival: 0), direction: .install), .working(0.25))
        XCTAssertEqual(CaseSort.label(CaseSortPhases(open: 1, progress: 0.25, arrival: 0), direction: .uninstall), .working(0.75))
        XCTAssertEqual(CaseSort.label(.ready, direction: .install), .ready)
        XCTAssertEqual(CaseSort.label(.ready, direction: .uninstall), .removed)
        XCTAssertEqual(CaseSortStills.demoSubject.summary, "24 LUTs · 6 titles · 2 transitions")
        XCTAssertEqual(CaseBadge.text(for: .restart), "Restart Resolve")
        XCTAssertEqual(CaseBadge.text(for: .updateLists), "Update Lists")
        XCTAssertNil(CaseBadge.text(for: .none))
    }

    // MARK: Real progress from the file operator

    func testProgressIsWeightedByBytes() throws {
        let a = URL(fileURLWithPath: "/a"), b = URL(fileURLWithPath: "/b")
        let sizes: [String: Int64] = ["/a": 3_000_000, "/b": 1_000_000]
        let meter = FileOpProgress([.makeDirectory(a), .copy(from: a, to: b), .copy(from: b, to: a), .trash(a)],
                                   size: { sizes[$0.path] ?? 0 })
        let total = 3_000_000 + 1_000_000 + FileOpProgress.minimumWeight
        XCTAssertEqual(meter.fraction(afterSteps: 0), 0)
        XCTAssertEqual(meter.fraction(afterSteps: 1), 0, "making a folder is free")
        XCTAssertEqual(meter.fraction(afterSteps: 2), 3_000_000 / total, accuracy: 1e-12)
        XCTAssertEqual(meter.fraction(afterSteps: 4), 1)
        XCTAssertEqual(FileOpProgress([]).fraction(afterSteps: 0), 1)
    }

    func testInstallReportsRisingProgressEndingAtOne() throws {
        let box = try Sandbox()
        try box.write("Pack/A.cube", Fixtures.cube)
        try box.write("Pack/B.cube", String(repeating: Fixtures.cube + "\n", count: 200))
        try box.write("Pack/Title.setting", Fixtures.title)
        let scan = try PackScanner(stagingRoot: box.root.appendingPathComponent("Staging"))
            .scan([box.inbox.appendingPathComponent("Pack")])
        defer { scan.cleanUp() }
        let installer = Installer(paths: box.paths)
        let options = InstallOptions(packName: "Pack")
        var index = LibraryIndex()
        var seen: [Double] = []
        _ = try installer.install(installer.plan(scan, options: options, index: index), options: options,
                                  sourceName: "Pack", index: &index, using: box.fileOperator) { seen.append($0) }
        XCTAssertEqual(seen.first, 0)
        XCTAssertEqual(seen.last, 1)
        XCTAssertEqual(seen, seen.sorted(), "progress went backwards")
        XCTAssertGreaterThan(Set(seen).count, 3, "progress came in steps, not one jump")
    }

    func testFailedStepRollsBackAndNeverReportsDone() throws {
        let box = try Sandbox()
        let source = try box.write("A.cube", Fixtures.cube)
        let missing = box.inbox.appendingPathComponent("missing.cube")
        let dest = box.paths.lutRoot.appendingPathComponent("A.cube")
        var seen: [Double] = []
        XCTAssertThrowsError(try box.fileOperator.perform(
            [.copy(from: source, to: dest), .copy(from: missing, to: box.paths.lutRoot.appendingPathComponent("B.cube"))],
            progress: { seen.append($0) }))
        XCTAssertFalse(box.exists(dest))
        XCTAssertNotEqual(seen.last, 1)
    }

    func testOperatorsWithoutStepsReportOnceAtTheEnd() throws {
        struct Plain: FileOperating { func perform(_ ops: [FileOp]) throws {} }
        var seen: [Double] = []
        try Plain().perform([], progress: { seen.append($0) })
        XCTAssertEqual(seen, [1])
    }
}
