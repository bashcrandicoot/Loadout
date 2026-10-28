import XCTest
@testable import Loadout

/// The case animation's maths: the bar follows real progress, cards wait for their share,
/// and the lid and latches go in the right order.
final class CaseMotionTests: XCTestCase {
    private let dt = 1.0 / 60

    /// Steps a driver with a progress curve until it settles (or `limit` seconds).
    @discardableResult
    private func play(_ driver: CaseDriver, limit: Double = 30, progress: (Double) -> Double,
                      finishedAt: Double, check: (Double, CaseDriver, CasePose, Double) -> Void = { _, _, _, _ in }) -> [(Double, CaseEvent)] {
        var events: [(Double, CaseEvent)] = []
        var t = 0.0
        while t < limit && !driver.isSettled {
            t += dt
            let real = t >= finishedAt ? 1 : progress(t)
            for event in driver.advance(by: dt, progress: real, finished: t >= finishedAt) { events.append((t, event)) }
            check(t, driver, driver.pose(badge: true), real)
        }
        XCTAssertTrue(driver.isSettled, "never settled")
        return events
    }

    func testStashBarNeverAheadOfRealProgressOrCards() {
        let driver = CaseDriver(direction: .stash, cards: 4)
        var last = 0.0
        play(driver, progress: { min(1, $0 / 3) }, finishedAt: 3) { _, driver, pose, real in
            XCTAssertLessThanOrEqual(pose.bar, real + 1e-9)
            XCTAssertLessThanOrEqual(pose.bar, driver.cardProgress + 1e-9)
            XCTAssertGreaterThanOrEqual(pose.bar, last - 1e-12, "the bar went backwards")
            last = pose.bar
        }
        XCTAssertEqual(driver.pose(badge: true).bar, 1, accuracy: 1e-9)
    }

    func testCardsWaitForTheirShareOfTheFiles() {
        let driver = CaseDriver(direction: .stash, cards: 4)
        // Stuck at 30 % (an admin prompt): only cards 0 and 1 (thresholds 0 and 0.25) may leave.
        for _ in 0..<300 { driver.advance(by: dt, progress: 0.3, finished: false) }
        XCTAssertEqual(driver.launches.count, 2)
        XCTAssertEqual(driver.pose(badge: false).lidOpen, CaseMotion.stashOpen, accuracy: 1e-9, "the lid stays open while waiting")
        XCTAssertNil(driver.doneTime)
        XCTAssertLessThanOrEqual(driver.pose(badge: false).bar, 0.3)
        // The copy finishes: the rest follow, one stagger apart.
        play(driver, progress: { _ in 1 }, finishedAt: 0)
        XCTAssertEqual(driver.launches.count, 4)
        for (a, b) in zip(driver.launches, driver.launches.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b - a, CaseMotion.cardStagger - 1e-9)
        }
    }

    func testStashOrderLidThenLeftThenRightLatchAndEndsShut() {
        let driver = CaseDriver(direction: .stash, cards: 2)
        let events = play(driver, progress: { _ in 1 }, finishedAt: 0.01)
        XCTAssertEqual(events.map(\.1), [.lidShut, .latchLeft, .latchRight])
        XCTAssertLessThan(events[0].0, events[1].0)
        XCTAssertLessThan(events[1].0, events[2].0)
        // The lid only starts down once every card has landed.
        let lastLanding = driver.launches.last! + CaseMotion.cardFlight
        XCTAssertGreaterThanOrEqual(driver.doneTime!, lastLanding - 1e-9)
        let pose = driver.pose(badge: true)
        XCTAssertEqual(pose.lidOpen, 0, accuracy: 1e-6)
        XCTAssertEqual(pose.latches[0], 1, accuracy: 1e-6)
        XCTAssertEqual(pose.latches[1], 1, accuracy: 1e-6)
        XCTAssertEqual(pose.badge, 1, accuracy: 1e-6)
        XCTAssertNil(pose.glint)
        XCTAssertTrue(pose.cards.allSatisfy { $0.travel == 1 })
    }

    func testLatchesStayUpUntilTheLidIsShut() {
        let driver = CaseDriver(direction: .stash, cards: 3)
        play(driver, progress: { min(1, $0) }, finishedAt: 1) { _, _, pose, _ in
            if pose.lidOpen > 0.06 { XCTAssertEqual(pose.latches, [0, 0]) }
        }
    }

    func testNoBadgeWhenResolveNeedsNothing() {
        let driver = CaseDriver(direction: .stash, cards: 1)
        play(driver, progress: { _ in 1 }, finishedAt: 0.01)
        XCTAssertEqual(driver.pose(badge: false).badge, 0)
    }

    func testUnloadFlipsLatchesOpensLidAndDrains() {
        let driver = CaseDriver(direction: .unload, cards: 3)
        var last = 1.0
        let events = play(driver, progress: { min(1, $0 / 0.5) }, finishedAt: 0.5) { _, driver, pose, real in
            XCTAssertGreaterThanOrEqual(pose.bar, 1 - real - 1e-9, "drained ahead of the files")
            XCTAssertLessThanOrEqual(pose.bar, last + 1e-12, "the bar refilled")
            last = pose.bar
            // No card lifts out before the lid has started to open.
            if driver.launches.count > 0 { XCTAssertGreaterThan(pose.lidOpen, 0) }
        }
        XCTAssertEqual(events.map(\.1), [.latchLeft, .latchRight, .lidOpen])
        let pose = driver.pose(badge: false)
        XCTAssertEqual(pose.bar, 0, accuracy: 1e-9)
        XCTAssertEqual(pose.latches, [0, 0])
        XCTAssertEqual(pose.lidOpen, CaseMotion.stashOpen, accuracy: 1e-6)
        XCTAssertTrue(pose.cards.allSatisfy { $0.travel == 1 })
    }

    func testReduceMotionCrossfadesWithoutFlights() {
        let driver = CaseDriver(direction: .stash, cards: 5, reduced: true)
        var sawCrossfade = false
        let events = play(driver, progress: { min(1, $0 / 0.6) }, finishedAt: 0.6) { _, driver, _, real in
            let frame = driver.frame(badge: true)
            XCTAssertTrue(frame.poses.allSatisfy { $0.pose.bar <= real + 1e-9 })
            if frame.poses.count == 2 { sawCrossfade = true }
            XCTAssertEqual(frame.poses.map(\.opacity).reduce(0, +), 1, accuracy: 1e-9)
        }
        XCTAssertTrue(events.isEmpty, "no snaps, no haptics")
        XCTAssertTrue(driver.launches.isEmpty)
        XCTAssertTrue(sawCrossfade)
        let end = driver.frame(badge: true)
        XCTAssertEqual(end.poses.count, 1)
        XCTAssertEqual(end.poses[0].pose, CasePose.shut(badge: true))
    }

    func testSafetyTimersOutlastTheAnimation() {
        for n in [1, 3, 6] {
            let stash = CaseDriver(direction: .stash, cards: n)
            var t = 0.0
            while !stash.isSettled { stash.advance(by: dt, progress: 1, finished: true); t += dt }
            XCTAssertLessThanOrEqual(t, CaseMotion.stashDuration(cards: n) + 0.05, "stash \(n)")
            let unload = CaseDriver(direction: .unload, cards: n)
            t = 0
            while !unload.isSettled { unload.advance(by: dt, progress: 1, finished: true); t += dt }
            XCTAssertLessThanOrEqual(t, CaseMotion.unloadDuration(cards: n) + 0.05, "unload \(n)")
        }
    }

    func testEasedProgressNeverGoesBackAndSnaps() {
        XCTAssertEqual(CaseMotion.easedProgress(current: 0.5, target: 0.2, dt: 0.1), 0.5)
        var x = 0.0
        for _ in 0..<200 { x = CaseMotion.easedProgress(current: x, target: 1, dt: dt) }
        XCTAssertEqual(x, 1)
        XCTAssertEqual(CaseMotion.easedProgress(current: 0, target: 3, dt: 10), 1)
    }

    func testHoverOpensWideAndSettles() {
        XCTAssertEqual(CaseMotion.hoverPose(elapsed: 0).lidOpen, CaseMotion.idleOpen, accuracy: 1e-9)
        XCTAssertEqual(CaseMotion.hoverPose(elapsed: 2).lidOpen, CaseMotion.hoverOpen, accuracy: 1e-9)
        XCTAssertLessThan(CaseMotion.hoverPose(elapsed: 0.27).bounce, -4, "a gentle hop")
        XCTAssertEqual(CaseMotion.hoverPose(elapsed: 0.55).bounce, 0, accuracy: 0.5)
    }

    // MARK: Cards

    func testCardsGroupKindsInLibraryOrder() {
        let cards = CaseCard.cards(kinds: [.title, .lut, .lut, .bundle, .lut, .title])
        XCTAssertEqual(cards.map(\.symbol), [AssetKind.lut.symbol, AssetKind.title.symbol, AssetKind.bundle.symbol])
        XCTAssertEqual(cards.map(\.label), ["3", "2", nil])
        XCTAssertEqual(cards.map(\.id), [0, 1, 2])
        XCTAssertTrue(CaseCard.cards(kinds: []).isEmpty)
    }

    func testManyItemsGetAnOverflowCard() throws {
        let box = try Sandbox()
        let items = (0..<9).map { i in
            LibraryItem(homeURL: box.paths.lutRoot.appendingPathComponent("L\(i).cube"),
                        currentURL: box.paths.lutRoot.appendingPathComponent("L\(i).cube"),
                        kind: .lut, state: .enabled, packID: UUID(), group: "Pack", creator: nil, size: 10, addedAt: Date())
        }
        let cards = CaseCard.cards(items: items)
        XCTAssertEqual(cards.count, CaseCard.maxCards)
        XCTAssertEqual(cards.last?.label, "+4")
        XCTAssertEqual(CaseCard.cards(items: Array(items.prefix(3))).count, 3)
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
