import Foundation

/// The maths behind the flight-case animation (see `CaseStage`): when the cards fly into the
/// case, when the lid shuts and the latches snap, how full the colour bar on the front is.
/// Everything here is plain numbers so it can be unit-tested; the drawing lives in
/// `CaseArt.swift` and `CaseStage.swift`.
///
/// Two rules keep the bar honest: it never shows more than the real copy progress, and it
/// never runs ahead of the cards (a card is a share of the files, and it only leaves the queue
/// once the copy has reached its share). A quick local install is paced by the cards; a slow
/// one (the admin prompt, a big .drfx) waits for the files.
enum CaseMotion {
    // MARK: Timing (seconds)

    /// One card's arc from the queue into the case.
    static let cardFlight = 0.75
    /// The gap between two cards leaving the queue.
    static let cardStagger = 0.3
    /// The lid's swing shut.
    static let lidClose = 0.42
    /// The lid's little rebound once it lands.
    static let lidSettle = 0.18
    /// One latch snapping down (or flipping up).
    static let latchSnap = 0.16
    /// Between the left and the right latch.
    static let latchGap = 0.14
    /// The glint across the full bar.
    static let glint = 0.6
    /// The Restart / Update Lists badge popping on.
    static let badgePop = 0.4
    /// Unload: the lid popping open.
    static let lidPop = 0.42
    /// Unload: one card lifting out and fading.
    static let lift = 0.8
    static let liftStagger = 0.2
    /// The finished case stays on screen this long before the sheet or the toast goes.
    static let hold = 0.6
    /// Reduce Motion: the crossfade from the open case to the closed one (or back).
    static let crossfade = 0.3

    // MARK: Lid (0 = shut, 1 = wide open)

    /// Sitting in the drop sheet, waiting.
    static let idleOpen = 0.22
    /// Something is being dragged over the window.
    static let hoverOpen = 1.0
    /// Open to catch the cards (and after an unload).
    static let stashOpen = 0.8

    // MARK: Helpers

    static func clamp(_ x: Double, _ low: Double = 0, _ high: Double = 1) -> Double {
        min(high, max(low, x))
    }

    static func mix(_ a: Double, _ b: Double, _ k: Double) -> Double { a + (b - a) * k }

    /// Smoothstep: 0 below `edge0`, 1 above `edge1`, an S-curve in between.
    static func smooth(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let k = clamp((x - edge0) / (edge1 - edge0))
        return k * k * (3 - 2 * k)
    }

    /// Ease-out with a small overshoot (a latch snapping, a badge popping). 0 → 1, peaks ≈ 1.1.
    static func easeOutBack(_ x: Double, overshoot s: Double = 1.70158) -> Double {
        let k = clamp(x) - 1
        return 1 + k * k * ((s + 1) * k + s)
    }

    static func easeOut(_ x: Double) -> Double {
        let k = 1 - clamp(x)
        return 1 - k * k * k
    }

    /// Moves the shown progress towards the real progress without jumping (time constant `tau`).
    /// It never goes backwards and snaps once it is close (as in Lodge's wagon).
    static func easedProgress(current: Double, target: Double, dt: Double, tau: Double = 0.22) -> Double {
        let target = clamp(target)
        guard target > current else { return current }
        let next = current + (target - current) * (1 - exp(-max(0, dt) / tau))
        return target - next < 0.0005 ? target : next
    }

    /// The real progress a card waits for before it leaves the queue: card `i` of `n` is the
    /// `i`-th share of the files.
    static func launchThreshold(card i: Int, of n: Int) -> Double {
        n <= 0 ? 0 : Double(i) / Double(n)
    }

    /// The longest a stash can take once the files are in (used as a safety timer, so a sheet
    /// whose window is hidden still closes).
    static func stashDuration(cards n: Int) -> Double {
        0.3 + Double(max(0, n - 1)) * cardStagger + cardFlight + 0.4 + lidClose + lidSettle
            + latchGap + latchSnap + 0.1 + glint + badgePop + hold
    }

    static func unloadDuration(cards n: Int) -> Double {
        0.05 + latchGap + latchSnap + lidPop + Double(max(0, n - 1)) * liftStagger + lift + 0.4 + hold
    }

    // MARK: Drag-over

    /// The case in the window's drop highlight, `elapsed` seconds after the drag came in: the
    /// lid swings wide with a little overshoot and the case gives one gentle bounce, then bobs.
    static func hoverPose(elapsed e: Double) -> CasePose {
        var pose = CasePose(lidOpen: mix(idleOpen, hoverOpen, easeOutBack(e / 0.45, overshoot: 1.2)),
                            latches: [0, 0], bar: 0)
        let hop = clamp(e / 0.55)
        pose.bounce = -9 * sin(.pi * hop) * (1 - hop * 0.35)
        if e > 0.55 { pose.bounce += -1.5 * sin((e - 0.55) * 3.2) * smooth(0.55, 1.2, e) }
        return pose
    }
}

/// Which way a run goes: files into Resolve, or out of it.
enum CaseDirection: Equatable {
    /// Install, or turning items back on: cards drop in, the lid shuts, the bar fills.
    case stash
    /// Remove or turn off: the latches flip, the lid pops, cards lift out, the bar drains.
    case unload
}

/// A moment worth a haptic tap.
enum CaseEvent: Equatable {
    case lidShut, latchLeft, latchRight, lidOpen
}

/// Where one card is: `travel` < 0 waiting in the queue (stash) or still in the case
/// (unload), then 0 → 1 along its path.
struct CardPose: Equatable {
    var index: Int
    var travel: Double
}

/// Everything the drawing needs for one frame of the case.
struct CasePose: Equatable {
    /// 0 = shut, 1 = wide open.
    var lidOpen: Double = 0
    /// Left and right latch: 1 = snapped down (locked), 0 = flipped up.
    var latches: [Double] = [1, 1]
    /// The colour bar's fill, 0…1.
    var bar: Double = 0
    /// The glint's position across the bar (0 → 1), nil when there's none.
    var glint: Double?
    /// The badge's pop (0 = hidden, ~1.1 overshoot, 1 = shown).
    var badge: Double = 0
    /// The case's vertical offset in points (negative = up).
    var bounce: Double = 0
    var cards: [CardPose] = []

    /// In the drop sheet before Install: lid ajar, latches up, bar empty.
    static func idle(cards n: Int) -> CasePose {
        CasePose(lidOpen: CaseMotion.idleOpen, latches: [0, 0], bar: 0,
                 cards: (0..<n).map { CardPose(index: $0, travel: -1) })
    }

    /// Shut and latched with the bar full (before an unload, after a stash).
    static func shut(cards n: Int = 0, badge: Bool = false) -> CasePose {
        CasePose(lidOpen: 0, latches: [1, 1], bar: 1, badge: badge ? 1 : 0,
                 cards: (0..<n).map { CardPose(index: $0, travel: 1) })
    }

    /// Open and empty (after an unload).
    static func emptied(cards n: Int = 0) -> CasePose {
        CasePose(lidOpen: CaseMotion.stashOpen, latches: [0, 0], bar: 0,
                 cards: (0..<n).map { CardPose(index: $0, travel: 1) })
    }
}

/// One frame to draw: usually a single pose; with Reduce Motion, two poses crossfading.
struct CaseFrame: Equatable {
    var poses: [(pose: CasePose, opacity: Double)]

    init(_ pose: CasePose) { poses = [(pose, 1)] }
    init(from: CasePose, to: CasePose, mix: Double) {
        let k = CaseMotion.clamp(mix)
        poses = k <= 0 ? [(from, 1)] : k >= 1 ? [(to, 1)] : [(from, 1 - k), (to, k)]
    }

    static func == (a: CaseFrame, b: CaseFrame) -> Bool {
        a.poses.count == b.poses.count && zip(a.poses, b.poses).allSatisfy { $0.pose == $1.pose && $0.opacity == $1.opacity }
    }
}

/// Drives one stash or unload from the real progress, frame by frame. A plain class (not
/// observed), like Lodge's `WagonDriver`: the stage's `TimelineView` asks it for each frame.
final class CaseDriver {
    let direction: CaseDirection
    let cardCount: Int
    /// Reduce Motion: no flights or swings, just a crossfade and the bar.
    let reduced: Bool

    /// Seconds since the run started.
    private(set) var time: Double = 0
    /// The real progress, eased.
    private(set) var shown: Double = 0
    /// The highest real progress seen so far.
    private(set) var target: Double = 0
    /// When each card left the queue (stash) or the case (unload).
    private(set) var launches: [Double] = []
    /// Stash: when the lid starts to shut. Unload: when the last card is out.
    private(set) var doneTime: Double?
    private var lastBar: Double

    init(direction: CaseDirection, cards: Int, reduced: Bool = false) {
        self.direction = direction
        cardCount = max(1, cards)
        self.reduced = reduced
        lastBar = direction == .stash ? 0 : 1
    }

    // MARK: Advancing

    /// Moves `dt` seconds on. `progress` is the real copy progress (0…1); `finished` is true
    /// once every file is in place. Returns the moments passed in this step (for haptics).
    @discardableResult
    func advance(by dt: Double, progress: Double, finished: Bool) -> [CaseEvent] {
        let dt = max(0, min(dt, 1.0 / 10))   // a hidden window doesn't make the case leap ahead
        let before = time
        time += dt
        target = max(target, CaseMotion.clamp(finished ? 1 : progress))
        shown = CaseMotion.easedProgress(current: shown, target: target, dt: dt)

        if !reduced {
            launchCards(finished: finished)
        }
        if doneTime == nil, finished, isComplete {
            doneTime = time
        }
        lastBar = barValue
        return events.filter { $0.time > before && $0.time <= time }.map(\.event)
    }

    private var launchReady: Double {
        switch direction {
        case .stash: return 0.2
        case .unload: return unloadLidStart + CaseMotion.lidPop * 0.5
        }
    }

    private func launchCards(finished: Bool) {
        let stagger = direction == .stash ? CaseMotion.cardStagger : CaseMotion.liftStagger
        while launches.count < cardCount {
            let i = launches.count
            let earliest = max(launchReady, (launches.last ?? -.infinity) + stagger)
            guard time >= earliest,
                  finished || target >= CaseMotion.launchThreshold(card: i, of: cardCount) else { return }
            launches.append(time)
        }
    }

    /// How far card `i` is along its path (−1 before it leaves).
    func travel(of i: Int) -> Double {
        guard i < launches.count else { return -1 }
        let duration = direction == .stash ? CaseMotion.cardFlight : CaseMotion.lift
        return CaseMotion.clamp((time - launches[i]) / duration)
    }

    /// The share of the work the cards show as done (each card is 1/n).
    var cardProgress: Double {
        if reduced { return 1 }
        return (0..<cardCount).reduce(0) { $0 + max(0, travel(of: $1)) } / Double(cardCount)
    }

    /// The bar's work fraction: never more than the real progress, never ahead of the cards.
    var workDone: Double { min(shown, cardProgress) }

    private var barValue: Double {
        switch direction {
        case .stash: return max(lastBar, workDone)
        case .unload: return min(lastBar, 1 - workDone)
        }
    }

    /// All cards have landed (or lifted out) and the bar shows everything.
    private var isComplete: Bool {
        (reduced || launches.count == cardCount && travel(of: cardCount - 1) >= 1) && shown >= 1
    }

    // MARK: The schedule after the files are in

    private var lidCloseStart: Double? { direction == .stash ? doneTime : nil }
    private var latchStarts: [Double]? {
        switch direction {
        case .stash:
            guard let close = lidCloseStart else { return nil }
            let first = close + CaseMotion.lidClose + 0.04
            return [first, first + CaseMotion.latchGap]
        case .unload:
            return [0.05, 0.05 + CaseMotion.latchGap]
        }
    }
    private var unloadLidStart: Double { 0.05 + CaseMotion.latchGap + CaseMotion.latchSnap }
    private var glintStart: Double? {
        guard direction == .stash, let latches = latchStarts else { return nil }
        return latches[1] + CaseMotion.latchSnap + 0.06
    }
    private var badgeStart: Double? { glintStart.map { $0 + 0.25 } }

    private var events: [(time: Double, event: CaseEvent)] {
        switch direction {
        case .stash:
            guard let close = lidCloseStart, let latches = latchStarts else { return [] }
            if reduced { return [] }
            return [(close + CaseMotion.lidClose, .lidShut),
                    (latches[0] + CaseMotion.latchSnap * 0.6, .latchLeft),
                    (latches[1] + CaseMotion.latchSnap * 0.6, .latchRight)]
        case .unload:
            if reduced { return [] }
            let latches = latchStarts ?? []
            return [(latches[0] + CaseMotion.latchSnap * 0.5, .latchLeft),
                    (latches[1] + CaseMotion.latchSnap * 0.5, .latchRight),
                    (unloadLidStart, .lidOpen)]
        }
    }

    /// The run is over and its last frame has been held long enough to read.
    var isSettled: Bool {
        guard let done = doneTime else { return false }
        if reduced { return time >= done + CaseMotion.crossfade + CaseMotion.hold }
        switch direction {
        case .stash:
            guard let glint = glintStart, let badge = badgeStart else { return false }
            return time >= max(glint + CaseMotion.glint, badge + CaseMotion.badgePop) + CaseMotion.hold
        case .unload:
            return time >= done + CaseMotion.hold
        }
    }

    // MARK: Poses

    /// The frame to draw now. `badge` shows the Restart / Update Lists badge at the end.
    func frame(badge: Bool) -> CaseFrame {
        reduced ? reducedFrame(badge: badge) : CaseFrame(pose(badge: badge))
    }

    func pose(badge: Bool) -> CasePose {
        var pose = CasePose()
        pose.bar = lastBar
        pose.cards = (0..<cardCount).map { CardPose(index: $0, travel: travel(of: $0)) }
        let t = time
        switch direction {
        case .stash:
            pose.latches = [0, 0]
            if let close = lidCloseStart {
                let c = (t - close) / CaseMotion.lidClose
                if c < 1 {
                    // Gravity: slow at first, fast as it lands.
                    pose.lidOpen = CaseMotion.stashOpen * (1 - CaseMotion.clamp(c) * CaseMotion.clamp(c))
                } else {
                    let k = CaseMotion.clamp((t - close - CaseMotion.lidClose) / CaseMotion.lidSettle)
                    pose.lidOpen = 0.05 * sin(.pi * k) * (1 - k)
                }
            } else {
                pose.lidOpen = CaseMotion.mix(CaseMotion.idleOpen, CaseMotion.stashOpen, CaseMotion.smooth(0, 0.3, t))
            }
            if let latches = latchStarts {
                pose.latches = latches.map { start in
                    t < start ? 0 : CaseMotion.easeOutBack((t - start) / CaseMotion.latchSnap, overshoot: 2.2)
                }
            }
            if let glint = glintStart {
                let k = (t - glint) / CaseMotion.glint
                pose.glint = k > 0 && k < 1 ? k : nil
            }
            if badge, let start = badgeStart, t > start {
                pose.badge = CaseMotion.easeOutBack((t - start) / CaseMotion.badgePop, overshoot: 2.4)
            }
        case .unload:
            let latches = latchStarts ?? [0, 0]
            pose.latches = latches.map { start in
                t < start ? 1 : 1 - CaseMotion.easeOut((t - start) / CaseMotion.latchSnap)
            }
            let lid = (t - unloadLidStart) / CaseMotion.lidPop
            pose.lidOpen = lid <= 0 ? 0 : CaseMotion.stashOpen * CaseMotion.easeOutBack(lid, overshoot: 1.6)
        }
        return pose
    }

    /// Reduce Motion: the open case and the shut one crossfade once the files are in; the bar
    /// still follows the real progress.
    private func reducedFrame(badge: Bool) -> CaseFrame {
        var from: CasePose, to: CasePose
        switch direction {
        case .stash:
            from = .idle(cards: cardCount)
            from.lidOpen = CaseMotion.stashOpen
            to = .shut(badge: badge)
        case .unload:
            from = .shut()
            to = .emptied()
        }
        from.bar = lastBar
        to.bar = lastBar
        let mix = doneTime.map { (time - $0) / CaseMotion.crossfade } ?? 0
        return CaseFrame(from: from, to: to, mix: mix)
    }
}
