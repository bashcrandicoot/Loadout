import Foundation
import CoreGraphics

// Maddy's "case sort" install animation (brand/final/animation/loadout-case-sort.html and its
// motion notes), ported one for one. Every frame is a pure function of three numbers:
//   open      O, a 0.9 s clock: the latches flip and the lid opens
//   progress  p, the real install progress: the cards fly into their slots and fill the bar
//   arrival   A, a 2.0 s clock once p reaches 1: the lid shuts, the latches snap, the glow plays
// An uninstall is the same story backwards. `CaseSortDriver` turns real progress into those
// three numbers; `CaseSortPainter` draws them.

/// The three numbers a frame is drawn from (her `phases()`).
struct CaseSortPhases: Equatable {
    var open: Double
    var progress: Double
    var arrival: Double

    /// Case shut, cards on the desk.
    static let ready = CaseSortPhases(open: 0, progress: 0, arrival: 0)
    /// Case shut and latched with every card inside, the glow settled.
    static let installed = CaseSortPhases(open: 1, progress: 1, arrival: 1)
}

enum CaseSortDirection: Equatable {
    case install
    case uninstall
}

/// The beats worth a haptic.
enum CaseSortEvent: Equatable {
    case lidShut
    case latchLeft
    case latchRight
    case lidOpen
}

/// What the strip's header row says.
enum CaseSortLabel: Equatable {
    /// Nothing has started ("Ready to install").
    case ready
    /// Files are moving; the fraction of them done.
    case working(Double)
    /// Everything is in Resolve (an install's end, or an uninstall before it starts).
    case installed
    /// An uninstall is done.
    case removed
}

enum CaseSort {
    // MARK: Easing (her helpers, one for one)

    static func clamp(_ x: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { min(hi, max(lo, x)) }
    static func mix(_ a: Double, _ b: Double, _ k: Double) -> Double { a + (b - a) * k }
    static func smooth(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let k = clamp((x - e0) / (e1 - e0))
        return k * k * (3 - 2 * k)
    }
    static func easeOutCubic(_ k: Double) -> Double { 1 - pow(1 - k, 3) }
    static func easeInCubic(_ k: Double) -> Double { k * k * k }
    static func easeInOutCubic(_ k: Double) -> Double { k < 0.5 ? 4 * k * k * k : 1 - pow(-2 * k + 2, 3) / 2 }
    static func easeOutBack(_ k: Double, _ c: Double = 1.6) -> Double { 1 + (c + 1) * pow(k - 1, 3) + c * pow(k - 1, 2) }
    static func bump(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let k = (x - a) / (b - a)
        return k <= 0 || k >= 1 ? 0 : sin(.pi * k)
    }

    // MARK: Clocks (seconds)

    static let openDuration = 0.9
    static let arrivalDuration = 2.0
    /// The cards may start once the open phase is this far along (her notes: "p can start at O ≥ .75").
    static let progressStartsAt = 0.75
    /// p eases towards the real progress like a 0.25 s spring, so cards don't jump.
    static let smoothing = 0.25
    /// "Installed" stays up this long before the sheet closes.
    static let installedHold = 0.6
    /// An uninstall shows the installed case this long before it opens (her demo holds 0.8 s).
    static let uninstallLeadIn = 0.3
    static let removedHold = 0.4
    /// Reduce Motion: the crossfade from the start to the end state.
    static let reducedCrossfade = 0.3

    // MARK: Her demo clock (stills that match her renders)

    static let demoOpenStart = 0.8
    static let demoProgressStart = 1.5
    static let demoProgressDuration = 5.4
    static var demoArrivalStart: Double { demoProgressStart + demoProgressDuration }
    static var demoStoryLength: Double { demoArrivalStart + arrivalDuration }

    /// `phases(t)` with `demo=1` (and `dir=out` for an uninstall).
    static func demoPhases(at t: Double, uninstall: Bool = false) -> CaseSortPhases {
        let s = uninstall ? clamp(demoStoryLength + 0.8 - t, 0, demoStoryLength) : t
        return CaseSortPhases(open: clamp((s - demoOpenStart) / openDuration),
                              progress: clamp((s - demoProgressStart) / demoProgressDuration),
                              arrival: clamp((s - demoArrivalStart) / arrivalDuration))
    }

    // MARK: Case geometry (icon-1024 units, like layers.json)

    static let seam = 498.0
    static let lidDepth = 150.0
    static let lidOpenAngle = 100.0
    static let barLeft = 338.0
    static let barRight = 686.0
    static let latchPivots = [CGPoint(x: 356, y: 540), CGPoint(x: 668, y: 540)]
    /// Where Maddy's 640 × 560 case artboard (the LoadoutCase imagesets) sits in icon space.
    static let artboard = CGRect(x: 192, y: 232, width: 640, height: 560)
    /// The four sparkles: case point, size, start (A).
    static let sparkles: [(point: CGPoint, size: Double, start: Double)] = [
        (CGPoint(x: 700, y: 566), 1.0, 0.62), (CGPoint(x: 612, y: 330), 0.8, 0.67),
        (CGPoint(x: 300, y: 476), 0.7, 0.72), (CGPoint(x: 520, y: 690), 0.6, 0.77),
    ]

    // MARK: Lid and latches

    /// The lid's angle in degrees (0 shut, 100 open), with the bounce as it shuts.
    static func lidAngle(_ ph: CaseSortPhases) -> Double {
        var theta = ph.open <= 0.32 ? 0 : lidOpenAngle * easeOutBack(clamp((ph.open - 0.32) / 0.68), 1.2)
        let a = ph.arrival
        if a > 0 {
            let kc = clamp((a - 0.12) / 0.30)
            theta = a < 0.12 ? lidOpenAngle : (kc < 1 ? lidOpenAngle * (1 - easeInCubic(kc)) : 0)
            theta += 5 * bump(0.42, 0.54, a) * (1 - clamp((a - 0.42) / 0.12))
        }
        return theta
    }

    /// The latch levers' flip in degrees, left and right (0 closed and up, 180 open and hanging).
    static func latchAngles(_ ph: CaseSortPhases) -> (left: Double, right: Double) {
        let a = ph.arrival
        if a > 0 {
            return (180 * (1 - easeInCubic(clamp((a - 0.48) / 0.09))),
                    180 * (1 - easeInCubic(clamp((a - 0.53) / 0.09))))
        }
        return (180 * easeInOutCubic(clamp(ph.open / 0.35)), 180 * easeInOutCubic(clamp((ph.open - 0.08) / 0.35)))
    }

    /// The little scale pulse after each latch clicks shut.
    static func latchPulses(_ ph: CaseSortPhases) -> (left: Double, right: Double) {
        (bump(0.57, 0.66, ph.arrival), bump(0.62, 0.71, ph.arrival))
    }

    /// The 3 px case thud as the lid lands (0…1).
    static func thud(_ ph: CaseSortPhases) -> Double { bump(0.42, 0.50, ph.arrival) }

    /// The case glow: up quickly, then settling at 38 %.
    static func glow(_ ph: CaseSortPhases) -> Double {
        smooth(0.60, 0.70, ph.arrival) * (1 - 0.62 * smooth(0.72, 1, ph.arrival))
    }

    /// The white shimmer across the bar: opacity and x (icon units, before the skew).
    static func shimmer(_ ph: CaseSortPhases) -> (opacity: Double, x: Double) {
        let a = ph.arrival
        let k = clamp((a - 0.60) / 0.26)
        return (a > 0.6 && a < 0.86 ? sin(.pi * k) : 0, mix(250, 880, k))
    }

    /// One sparkle: how far through it is (0…1) and its strength (0 when off).
    static func sparkle(_ index: Int, _ ph: CaseSortPhases) -> (k: Double, strength: Double) {
        let start = sparkles[index].start
        let k = clamp((ph.arrival - start) / 0.19)
        return (k, ph.arrival > start && k < 1 ? sin(.pi * k) : 0)
    }

    /// The header row (her `labelState`). An uninstall reads the same story backwards.
    static func label(_ ph: CaseSortPhases, direction: CaseSortDirection) -> CaseSortLabel {
        if ph.arrival >= 0.62 { return .installed }
        if ph.open <= 0 && ph.progress <= 0 { return direction == .install ? .ready : .removed }
        return .working(direction == .install ? ph.progress : 1 - ph.progress)
    }

    /// "n of N": the files done at this fraction (her `floor(p · 32)`).
    static func filesDone(_ fraction: Double, of total: Int) -> Int {
        min(total, Int((clamp(fraction) * Double(total)).rounded(.down)))
    }
}

/// Where the case and the desk are in a scene (her `L`).
struct CaseSortStage: Equatable {
    var centerX: Double
    var base: Double
    var scale: Double
    /// How far a card rises off the desk, and how high its arc peaks above that.
    var lift: Double
    var arc: Double
    /// The scene's size in points.
    var size: CGSize

    /// The 492 × 112 pt strip in the install sheet (and the Library toast).
    static let strip = CaseSortStage(centerX: 404, base: 103, scale: 0.205, lift: 12, arc: 30,
                                     size: CGSize(width: 492, height: 112))

    /// Icon-1024 units → scene points (her `C2S`).
    func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: centerX - 512 * scale + x * scale, y: base - 712 * scale + y * scale)
    }
}

// MARK: - Cards

/// The five colour-bar segments, in bar (and flight) order. Loadout's kinds map onto
/// Maddy's five card types.
enum CaseSortGroup: Int, CaseIterable, Comparable {
    case luts
    /// DCTLs, effects and generators: her clip/still cards (they change how a shot looks).
    case looks
    case titles
    case bundles
    case transitions

    init(_ kind: AssetKind) {
        switch kind {
        case .lut: self = .luts
        case .dctl, .effect, .generator: self = .looks
        case .title: self = .titles
        case .bundle: self = .bundles
        case .transition: self = .transitions
        }
    }

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    /// Her segment colours.
    var color: UInt32 { [0xFFC66A, 0xFF8A4C, 0xE65BA0, 0x8E5CF0, 0x2E9BFF][rawValue] }
    /// A card's width standing on the strip's desk.
    var deskWidth: Double { self == .looks ? 30 : self == .luts ? 31 : 33 }
    /// A card's width in its slot, and how much of it shows above the seam (icon units).
    var slotWidth: Double { self == .looks ? 78 : 70 }
    var slotShowing: Double { self == .looks ? 44 : 64 }
    /// Space before the first card of this group, and between cards within it (her row x 26…292).
    var gapBefore: Double { [42, 42, 44, 38, 40][rawValue] }
    var gapWithin: Double { [22, 36, 26, 26, 26][rawValue] }

    /// Her slot columns hold up to four cards.
    static let maxCards = 4
}

/// Maddy's nine card drawings.
enum CaseSortArt: String, CaseIterable {
    case lut0, lut1, lut2, lut3, clip0, clip1, title, drfx, transition

    static func art(for group: CaseSortGroup, index j: Int) -> CaseSortArt {
        switch group {
        case .luts: return [.lut0, .lut1, .lut2, .lut3][j % 4]
        case .looks: return [.clip0, .clip1][j % 2]
        case .titles: return .title
        case .bundles: return .drfx
        case .transitions: return .transition
        }
    }

    var size: CGSize {
        switch self {
        case .lut0, .lut1, .lut2, .lut3: return CGSize(width: 150, height: 196)
        case .clip0, .clip1: return CGSize(width: 150, height: 96)
        case .title, .drfx: return CGSize(width: 168, height: 214)
        case .transition: return CGSize(width: 160, height: 200)
        }
    }

    /// The imageset (a PDF with 2 units of margin round the card).
    var imageName: String {
        switch self {
        case .lut0: return "LoadoutCardLUT0"
        case .lut1: return "LoadoutCardLUT1"
        case .lut2: return "LoadoutCardLUT2"
        case .lut3: return "LoadoutCardLUT3"
        case .clip0: return "LoadoutCardClip0"
        case .clip1: return "LoadoutCardClip1"
        case .title: return "LoadoutCardTitle"
        case .drfx: return "LoadoutCardDrfx"
        case .transition: return "LoadoutCardTransition"
        }
    }
    static let imageMargin = 2.0

    /// Her STRIP_START tilts.
    var deskRotation: Double { [-8, -3, 2, 7, -4, 5, -5, 3, 6][Self.allCases.firstIndex(of: self)!] }

    /// The flat cards' baked desk shadow (card units): rect, corner radius, opacity.
    var deskShadow: (rect: CGRect, radius: Double, opacity: Double)? {
        switch self {
        case .lut0, .lut1, .lut2, .lut3: return (CGRect(x: -70, y: -90, width: 150, height: 196), 12, 0.4)
        case .clip0, .clip1: return (CGRect(x: -69, y: -39, width: 150, height: 96), 8, 0.45)
        default: return nil
        }
    }
}

/// Where a card is: her `translate(X,Y) skewX(K) scale(S, S·F) rotate(R)`, in scene points.
struct CaseSortCardPose: Equatable {
    enum Layer: Equatable {
        /// Resting on the desk, behind the case.
        case desk
        /// In the air, above everything.
        case flying
        /// In its slot, behind the case's front wall.
        case inCase
    }

    var x: Double
    var y: Double
    var skew: Double = 0
    var scale: Double
    var flatten: Double = 1
    var rotation: Double
    var layer: Layer = .desk
    /// The halo in the segment colour while it flies (0…0.55).
    var glow: Double = 0
}

struct CaseSortCard: Equatable {
    var group: CaseSortGroup
    var art: CaseSortArt
    /// Which bar segment (and slot column) it belongs to.
    var segment: Int
    /// Its place in the column (later cards sit lower and in front).
    var indexInGroup: Int
    var start: CaseSortCardPose
    var slot: CaseSortCardPose
    /// Its height in the slot (icon units).
    var slotHeight: Double
    /// Where its window opens in p.
    var windowStart: Double
}

/// The cards, slots and bar segments for one install (her layout block).
struct CaseSortLayout: Equatable {
    /// Nine cards stand in for any number of files, like her 9 for 32.
    static let maxCards = 9
    /// One card's flight and the gap between take-offs at her pace (5.4 s for nine cards).
    static let cardSeconds = 1.188
    static let staggerSeconds = 0.5265

    let cards: [CaseSortCard]
    /// The segments in bar order (only the groups being installed).
    let segments: [CaseSortGroup]
    /// Segment edges along the bar (icon units).
    let edges: [Double]
    /// Each card's share of p (her WIN).
    let window: Double
    /// The shortest time p takes from 0 to 1, so the flights keep her rhythm however fast the copy is.
    let minimumDuration: Double
    let stage: CaseSortStage

    init(kinds: [AssetKind], stage: CaseSortStage = .strip) {
        let counts = Dictionary(kinds.map { (CaseSortGroup($0), 1) }, uniquingKeysWith: +)
        self.init(counts: counts, stage: stage)
    }

    init(counts: [CaseSortGroup: Int], stage: CaseSortStage = .strip) {
        self.stage = stage
        let allocation = Self.allocate(counts)
        let groups = CaseSortGroup.allCases.filter { (allocation[$0] ?? 0) > 0 }
        segments = groups.isEmpty ? [.luts] : groups
        let n = Double(segments.count)
        edges = (0...segments.count).map { CaseSort.barLeft + (CaseSort.barRight - CaseSort.barLeft) * Double($0) / n }

        var flat: [(CaseSortGroup, Int)] = []
        for group in groups { for j in 0..<(allocation[group] ?? 0) { flat.append((group, j)) } }
        let count = max(flat.count, 1)
        minimumDuration = Self.cardSeconds + Double(count - 1) * Self.staggerSeconds
        window = Self.cardSeconds / minimumDuration

        // Desk positions: her spacing, centred on her row (x 26…292).
        var xs: [Double] = []
        var x = 0.0
        for (i, (group, _)) in flat.enumerated() {
            if i > 0 { x += flat[i - 1].0 == group ? group.gapWithin : group.gapBefore }
            xs.append(x)
        }
        let shift = 159 - ((xs.first ?? 0) + (xs.last ?? 0)) / 2

        var cards: [CaseSortCard] = []
        for (i, (group, j)) in flat.enumerated() {
            let art = CaseSortArt.art(for: group, index: j)
            let size = art.size
            let segment = segments.firstIndex(of: group) ?? 0
            let s = group.deskWidth / size.width
            let tilt = group == .luts || group == .looks ? art.deskRotation : [art.deskRotation, -4, 5, -2][j % 4]
            let start = CaseSortCardPose(x: xs[i] + shift, y: 100 - size.height * s / 2 - 1, scale: s, rotation: tilt)
            let sw = group.slotWidth
            let hu = size.height * sw / size.width
            let visible = group.slotShowing - Double(j) * 9
            let jitter = [-5.0, 5, -2, 4][j % 4]
            let column = (edges[segment] + edges[segment + 1]) / 2
            let p = stage.point(column + jitter, CaseSort.seam - visible + hu / 2)
            let slot = CaseSortCardPose(x: p.x, y: p.y, scale: sw * stage.scale / size.width,
                                        rotation: [-4.0, 3, -2, 5][j % 4], layer: .inCase)
            cards.append(CaseSortCard(group: group, art: art, segment: segment, indexInGroup: j, start: start,
                                      slot: slot, slotHeight: hu,
                                      windowStart: Double(i) * Self.staggerSeconds / minimumDuration))
        }
        self.cards = cards
    }

    /// Her demo: 4 LUTs, 2 clips, a title, a .drfx and a transition.
    static let demo = CaseSortLayout(counts: [.luts: 4, .looks: 2, .titles: 1, .bundles: 1, .transitions: 1])

    /// Up to nine cards: one for each group present, the rest shared out by how many files each
    /// group has (at most four a column, and never more cards than files).
    static func allocate(_ counts: [CaseSortGroup: Int]) -> [CaseSortGroup: Int] {
        let present = CaseSortGroup.allCases.filter { (counts[$0] ?? 0) > 0 }
        var out = Dictionary(uniqueKeysWithValues: present.map { ($0, 1) })
        var left = maxCards - present.count
        while left > 0 {
            let open = present.filter { out[$0]! < min(counts[$0]!, CaseSortGroup.maxCards) }
            guard let next = open.max(by: { Double(counts[$0]!) / Double(out[$0]!) < Double(counts[$1]!) / Double(out[$1]!) })
            else { break }
            out[next]! += 1
            left -= 1
        }
        return out
    }

    /// Card i's own progress through its flight (her `u_i`).
    func cardProgress(_ i: Int, _ p: Double) -> Double {
        CaseSort.clamp((p - cards[i].windowStart) / window)
    }

    /// Her `pose(c, u, A)`.
    func pose(_ i: Int, progress p: Double, arrival a: Double) -> CaseSortCardPose {
        typealias M = CaseSort
        let card = cards[i]
        let u = cardProgress(i, p)
        let s0 = card.start, sl = card.slot
        if u <= 0 { return s0 }
        let liftY = s0.y - stage.lift
        let liftScale = s0.scale * 1.06
        let liftFlatten = M.mix(s0.flatten, 1, 0.7)
        let liftRotation = s0.rotation * 0.5
        let hoverY = sl.y - (card.slotHeight * 0.55 + 70) * stage.scale
        let hoverScale = sl.scale * 1.12
        var pose: CaseSortCardPose
        if u < 0.2 {
            let e = M.easeOutCubic(u / 0.2)
            pose = CaseSortCardPose(x: s0.x, y: s0.y - stage.lift * e, skew: M.mix(s0.skew, 0, e),
                                    scale: M.mix(s0.scale, liftScale, e), flatten: M.mix(s0.flatten, liftFlatten, e),
                                    rotation: M.mix(s0.rotation, liftRotation, e), layer: u < 0.1 ? .desk : .flying)
        } else if u < 0.78 {
            let e = M.easeInOutCubic((u - 0.2) / 0.58)
            let cx = (s0.x + sl.x) / 2
            let cy = min(liftY, hoverY) - stage.arc
            let x = (1 - e) * (1 - e) * s0.x + 2 * (1 - e) * e * cx + e * e * sl.x
            let y = (1 - e) * (1 - e) * liftY + 2 * (1 - e) * e * cy + e * e * hoverY
            let dir: Double = sl.x - s0.x < 0 ? -1 : 1
            pose = CaseSortCardPose(x: x, y: y, scale: M.mix(liftScale, hoverScale, e), flatten: M.mix(liftFlatten, 1, e),
                                    rotation: M.mix(liftRotation, sl.rotation, e) + dir * 9 * sin(.pi * e), layer: .flying)
        } else {
            let k = (u - 0.78) / 0.22
            pose = CaseSortCardPose(x: sl.x, y: M.mix(hoverY, sl.y, M.easeOutBack(k, 1.6)),
                                    scale: M.mix(hoverScale, sl.scale, M.easeOutCubic(k)), rotation: sl.rotation,
                                    layer: .inCase)
        }
        if u >= 1 && a > 0 { pose.y += M.easeInCubic(M.clamp(a / 0.3)) * 95 * stage.scale }
        pose.glow = 0.55 * sin(.pi * M.clamp((u - 0.12) / 0.74))
        return pose
    }

    /// Each segment's fill (0…1): its cards' landings, `smooth(.80,.95,u)` each.
    func segmentFills(_ p: Double) -> [Double] {
        guard !cards.isEmpty else { return [CaseSort.clamp(p)] }
        var fills = Array(repeating: 0.0, count: segments.count)
        var counts = Array(repeating: 0, count: segments.count)
        for card in cards { counts[card.segment] += 1 }
        for (i, card) in cards.enumerated() {
            fills[card.segment] += CaseSort.smooth(0.80, 0.95, cardProgress(i, p)) / Double(counts[card.segment])
        }
        return fills.map { CaseSort.clamp($0) }
    }

    /// The white flash on a segment as a card lands.
    func segmentPulses(_ p: Double) -> [Double] {
        var pulses = Array(repeating: 0.0, count: segments.count)
        for (i, card) in cards.enumerated() {
            let u = cardProgress(i, p)
            pulses[card.segment] = max(pulses[card.segment], u < 1 ? CaseSort.bump(0.83, 1, u) : 0)
        }
        return pulses
    }

    /// How much of the whole bar is filled (0…1).
    func barFill(_ p: Double) -> Double {
        let fills = segmentFills(p)
        return fills.reduce(0, +) / Double(fills.count)
    }
}

// MARK: - Driver

/// What to draw: one set of phases, or (Reduce Motion) a crossfade between two.
struct CaseSortFrame: Equatable {
    struct Layer: Equatable {
        var phases: CaseSortPhases
        /// Reduce Motion: the bar follows this instead of the (still) cards.
        var bar: Double?
        var opacity: Double
    }
    var layers: [Layer]

    init(_ phases: CaseSortPhases, bar: Double? = nil) {
        layers = [Layer(phases: phases, bar: bar, opacity: 1)]
    }

    init(from a: Layer, to b: Layer, mix: Double) {
        if mix <= 0 { layers = [Layer(phases: a.phases, bar: a.bar, opacity: 1)] }
        else if mix >= 1 { layers = [Layer(phases: b.phases, bar: b.bar, opacity: 1)] }
        else { layers = [Layer(phases: a.phases, bar: a.bar, opacity: 1), Layer(phases: b.phases, bar: b.bar, opacity: mix)] }
    }
}

/// Turns real progress into the story's three numbers. Not observed: the strip's TimelineView
/// steps it once per frame.
final class CaseSortDriver {
    let direction: CaseSortDirection
    let layout: CaseSortLayout
    let reduced: Bool

    /// The story so far (for an uninstall these run from 1 back to 0).
    private(set) var phases: CaseSortPhases
    /// The real progress (0…1) of the files moving, never going back.
    private(set) var real = 0.0
    private(set) var finished = false
    private(set) var isSettled = false
    private var leadIn = 0.0
    private var hold = 0.0
    /// Reduce Motion's crossfade (0…1).
    private var fade = 0.0

    init(direction: CaseSortDirection, layout: CaseSortLayout, reduced: Bool = false) {
        self.direction = direction
        self.layout = layout
        self.reduced = reduced
        phases = direction == .install ? .ready : .installed
    }

    /// The longest a run takes once its files are done (the app's safety timer adds to this).
    static func longestDuration(_ direction: CaseSortDirection, layout: CaseSortLayout) -> Double {
        switch direction {
        case .install:
            return CaseSort.openDuration + layout.minimumDuration + 3 * CaseSort.smoothing
                + CaseSort.arrivalDuration + CaseSort.installedHold
        case .uninstall:
            return CaseSort.uninstallLeadIn + CaseSort.arrivalDuration + layout.minimumDuration
                + 3 * CaseSort.smoothing + CaseSort.openDuration + CaseSort.removedHold
        }
    }

    /// Moves the story on by `dt` seconds. Returns the beats crossed (none under Reduce Motion).
    @discardableResult
    func advance(by dt: Double, progress: Double, finished done: Bool) -> [CaseSortEvent] {
        let dt = min(max(dt, 0), 0.1)
        real = max(real, CaseSort.clamp(progress))
        if done { finished = true }
        guard !isSettled else { return [] }
        if reduced {
            if finished && real >= 1 {
                fade = min(1, fade + dt / CaseSort.reducedCrossfade)
                if fade >= 1 { settle(after: dt, hold: direction == .install ? CaseSort.installedHold : CaseSort.removedHold) }
            }
            return []
        }
        let before = phases
        switch direction {
        case .install:
            phases.open = min(1, phases.open + dt / CaseSort.openDuration)
            if phases.open >= CaseSort.progressStartsAt {
                phases.progress = approach(phases.progress, real, dt)
            }
            if phases.progress >= 1 && finished {
                phases.arrival = min(1, phases.arrival + dt / CaseSort.arrivalDuration)
            }
            if phases.arrival >= 1 { settle(after: dt, hold: CaseSort.installedHold) }
        case .uninstall:
            if leadIn < CaseSort.uninstallLeadIn {
                leadIn += dt
            } else if phases.arrival > 0 {
                phases.arrival = max(0, phases.arrival - dt / CaseSort.arrivalDuration)
            } else {
                // The story's p is what's still in the case: never less than the real files left.
                phases.progress = 1 - approach(1 - phases.progress, real, dt)
                if phases.progress <= 0 && finished {
                    phases.open = max(0, phases.open - dt / CaseSort.openDuration)
                    if phases.open <= 0 { settle(after: dt, hold: CaseSort.removedHold) }
                }
            }
        }
        return events(from: before, to: phases)
    }

    /// p eases after the real progress (a 0.25 s spring) at no more than her pace, and never passes it.
    private func approach(_ current: Double, _ target: Double, _ dt: Double) -> Double {
        guard target > current else { return current }
        let eased = (target - current) * (1 - exp(-dt * 3 / CaseSort.smoothing))
        let capped = dt / layout.minimumDuration
        var next = current + min(eased, capped)
        if target - next < 0.0005 && eased <= capped { next = target }
        return min(next, target)
    }

    private func settle(after dt: Double, hold limit: Double) {
        hold += dt
        if hold >= limit { isSettled = true }
    }

    private func events(from a: CaseSortPhases, to b: CaseSortPhases) -> [CaseSortEvent] {
        var out: [CaseSortEvent] = []
        func up(_ x: Double) -> Bool { a.arrival < x && b.arrival >= x }
        func down(_ x: Double) -> Bool { a.arrival > x && b.arrival <= x }
        if direction == .install {
            if up(0.42) { out.append(.lidShut) }
            if up(0.57) { out.append(.latchLeft) }
            if up(0.62) { out.append(.latchRight) }
        } else {
            // Backwards: the right latch flips open first, then the left, then the lid lifts.
            if down(0.62) { out.append(.latchRight) }
            if down(0.57) { out.append(.latchLeft) }
            if down(0.42) { out.append(.lidOpen) }
            if a.open > 0.32 && b.open <= 0.32 { out.append(.lidShut) }
        }
        return out
    }

    /// What to draw now.
    var frame: CaseSortFrame {
        guard reduced else { return CaseSortFrame(phases) }
        switch direction {
        case .install:
            return CaseSortFrame(from: .init(phases: .ready, bar: real, opacity: 1),
                                 to: .init(phases: .installed, bar: nil, opacity: 1), mix: fade)
        case .uninstall:
            return CaseSortFrame(from: .init(phases: .installed, bar: 1 - real, opacity: 1),
                                 to: .init(phases: .ready, bar: nil, opacity: 1), mix: fade)
        }
    }

    /// What the header row says now.
    var label: CaseSortLabel {
        guard reduced else { return CaseSort.label(phases, direction: direction) }
        if fade >= 0.5 { return direction == .install ? .installed : .removed }
        return .working(real)
    }
}
