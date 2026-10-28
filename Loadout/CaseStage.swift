import SwiftUI
import AppKit

// The flight case at work: files drop into it on install and lift out of it when they're
// removed or turned off. Ida's motion spec, drawn with `CaseArt` and timed by `CaseDriver`;
// the bar on the case is the real copy progress (`CaseRun.progress`), never a timer.

/// One install, removal or turn-off as the case shows it.
struct CaseRun: Identifiable, Equatable {
    let id = UUID()
    var direction: CaseDirection
    var cards: [CaseCard]
    /// The real copy progress, 0…1.
    var progress: Double = 0
    /// Every file is in place (and the index is saved).
    var finished = false
    /// What Resolve needs afterwards (shows the badge on a stash).
    var refresh: ResolveRefresh = .none
    /// "Turning off 3 LUTs", for the Library toast.
    var caption: String = ""
}

/// One of the tiles that fly into (or out of) the case.
struct CaseCard: Identifiable, Equatable {
    var id: Int
    var symbol: String
    /// The count on the tile ("12"), or "+4" for the overflow tile.
    var label: String?

    static let maxCards = 6

    /// One tile per kind, with how many of that kind (an install).
    static func cards(kinds: [AssetKind]) -> [CaseCard] {
        let counts = Dictionary(kinds.map { ($0, 1) }, uniquingKeysWith: +)
        let ordered = AssetKind.allCases.filter { counts[$0] != nil }.prefix(maxCards)
        return ordered.enumerated().map { index, kind in
            let n = counts[kind] ?? 0
            return CaseCard(id: index, symbol: kind.symbol, label: n > 1 ? "\(n)" : nil)
        }
    }

    /// One tile per item, up to five, then a "+n" tile (a removal or turn-off).
    static func cards(items: [LibraryItem]) -> [CaseCard] {
        if items.count <= maxCards {
            return items.enumerated().map { CaseCard(id: $0.offset, symbol: $0.element.kind.symbol) }
        }
        var cards = items.prefix(maxCards - 1).enumerated().map { CaseCard(id: $0.offset, symbol: $0.element.kind.symbol) }
        cards.append(CaseCard(id: maxCards - 1, symbol: "ellipsis", label: "+\(items.count - (maxCards - 1))"))
        return cards
    }
}

enum Haptics {
    /// A soft tick as a latch snaps (only on a Force Touch trackpad; silent otherwise).
    static func latch() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

// MARK: - Layout

/// Where the case and the queued cards go in each place it appears.
enum CaseLayout {
    /// The top of the drop sheet.
    case sheet
    /// The toast over the Library for removals and turn-offs.
    case toast
    /// The window's drag-over highlight: the case alone, centred.
    case target

    var size: CGSize {
        switch self {
        case .sheet: return CGSize(width: 500, height: 150)
        case .toast: return CGSize(width: 340, height: 112)
        case .target: return CGSize(width: 200, height: 150)
        }
    }

    /// Points per case-artboard unit.
    var caseScale: Double {
        switch self {
        case .sheet: return 0.29
        case .toast: return 0.2
        case .target: return 0.28
        }
    }

    /// The case artboard's top-left corner, placed so its visible part sits where it should.
    var caseOrigin: CGPoint {
        let s = caseScale
        let visible = CaseGeometry.visibleRect
        let w = visible.width * s, h = visible.height * s
        let topLeft: CGPoint
        switch self {
        case .sheet: topLeft = CGPoint(x: size.width - w - 34, y: size.height - h - 2)
        case .toast: topLeft = CGPoint(x: size.width - w - 14, y: size.height - h - 2)
        case .target: topLeft = CGPoint(x: (size.width - w) / 2, y: size.height - h - 2)
        }
        return CGPoint(x: topLeft.x - visible.minX * s, y: topLeft.y - visible.minY * s)
    }

    var cardSize: CGSize {
        self == .toast ? CGSize(width: 26, height: 32) : CGSize(width: 34, height: 42)
    }

    /// Where queued card `index` of `count` waits.
    func slot(_ index: Int, of count: Int) -> CGPoint {
        let gap = cardSize.width + (self == .toast ? 8 : 12)
        let row = self == .toast ? size.height - 30 : size.height / 2 + 8
        let left = self == .toast ? 22.0 : 40.0
        let right = caseOrigin.x + CaseGeometry.visibleRect.minX * caseScale - 24 - cardSize.width / 2
        let start = max(left + cardSize.width / 2, right - gap * Double(count - 1))
        return CGPoint(x: start + gap * Double(index), y: row)
    }

    func casePoint(_ point: CGPoint, bounce: Double = 0) -> CGPoint {
        CGPoint(x: caseOrigin.x + point.x * caseScale, y: caseOrigin.y + (point.y + bounce) * caseScale)
    }
}

// MARK: - One frame

/// The case and its cards in one pose. Pure drawing, so the film renderer can use it too.
struct CaseScene: View {
    let frame: CaseFrame
    var direction: CaseDirection = .stash
    var cards: [CaseCard] = []
    var layout: CaseLayout
    var badgeText: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(frame.poses.enumerated()), id: \.offset) { _, layer in
                posed(layer.pose).opacity(layer.opacity)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func posed(_ pose: CasePose) -> some View {
        let s = layout.caseScale
        return ZStack(alignment: .topLeading) {
            placed(CaseBack(pose: pose, scale: s))
            ForEach(cards) { card in
                if let cardPose = pose.cards.first(where: { $0.index == card.id }) {
                    cardView(card, pose: cardPose)
                }
            }
            placed(CaseFront(pose: pose, scale: s, badgeText: badgeText))
                // Maddy's glyph shadow (blur 6, y +5, black 18%), which isn't in the vectors.
                .shadow(color: .black.opacity(0.18), radius: 6 * s, y: 5 * s)
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
    }

    private func placed<V: View>(_ view: V) -> some View {
        view.offset(x: layout.caseOrigin.x, y: layout.caseOrigin.y)
    }

    @ViewBuilder
    private func cardView(_ card: CaseCard, pose: CardPose) -> some View {
        let n = cards.count
        let mouth = layout.casePoint(CaseGeometry.mouthCenter)
        let tile = CaseCardTile(card: card, size: layout.cardSize)
        switch direction {
        case .stash:
            if pose.travel < 0 {
                tile.position(layout.slot(card.id, of: n))
            } else if pose.travel < 1 {
                // An arc from the queue up and over into the case's mouth.
                let t = CaseMotion.easeOut(pose.travel) * 0.35 + pose.travel * 0.65
                let start = layout.slot(card.id, of: n)
                let end = CGPoint(x: mouth.x, y: mouth.y + 40 * layout.caseScale)
                let control = CGPoint(x: (start.x + end.x) / 2, y: min(start.y, end.y) - 260 * layout.caseScale)
                let point = CGPoint(x: bezier(start.x, control.x, end.x, t), y: bezier(start.y, control.y, end.y, t))
                tile
                    .rotationEffect(.degrees(-14 * sin(.pi * pose.travel)))
                    .scaleEffect(CaseMotion.mix(1, 0.42, CaseMotion.smooth(0.25, 1, pose.travel)))
                    .opacity(1 - CaseMotion.smooth(0.82, 1, pose.travel))
                    .position(point)
            }
        case .unload:
            if pose.travel > 0 && pose.travel < 1 {
                // Up out of the case, growing a little, then gone.
                let k = CaseMotion.easeOut(pose.travel)
                let spread = (Double(card.id) - Double(n - 1) / 2) * 56 * layout.caseScale
                let point = CGPoint(x: mouth.x + spread * k, y: mouth.y + (30 - 330 * k) * layout.caseScale)
                tile
                    .scaleEffect(CaseMotion.mix(0.42, 0.9, k))
                    .opacity(CaseMotion.smooth(0, 0.12, pose.travel) * (1 - CaseMotion.smooth(0.55, 1, pose.travel)))
                    .position(point)
            }
        }
    }

    private func bezier(_ a: Double, _ b: Double, _ c: Double, _ t: Double) -> Double {
        (1 - t) * (1 - t) * a + 2 * (1 - t) * t * b + t * t * c
    }
}

/// A white tile with the kind's symbol (and how many) on it.
struct CaseCardTile: View {
    let card: CaseCard
    let size: CGSize

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size.width * 0.2, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.22), radius: 3, y: 1.5)
            RoundedRectangle(cornerRadius: size.width * 0.2, style: .continuous)
                .strokeBorder(.black.opacity(0.1), lineWidth: 0.5)
            VStack(spacing: 2) {
                Image(systemName: card.symbol)
                    .font(.system(size: size.width * 0.42, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                if let label = card.label {
                    Text(label)
                        .font(.system(size: size.width * 0.28, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color(white: 0.35))
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Live

/// The case following a `CaseRun` (or idling when there's none). Calls `onSettled` once
/// when a run has finished and its last frame has been held.
struct CaseStage: View {
    var run: CaseRun?
    /// Cards waiting in the queue before Install is pressed.
    var idleCards: [CaseCard] = []
    var layout: CaseLayout
    var onSettled: (UUID) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var engine = CaseEngine()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: run == nil || engine.settledID == run?.id)) { timeline in
            let step = engine.step(at: timeline.date, run: run, reduced: reduceMotion, onSettled: onSettled)
            CaseScene(frame: step ?? idleFrame,
                      direction: run?.direction ?? .stash,
                      cards: run?.cards ?? idleCards,
                      layout: layout,
                      badgeText: run.flatMap { CaseBadge.text(for: $0.refresh) })
        }
        .frame(width: layout.size.width, height: layout.size.height)
    }

    private var idleFrame: CaseFrame {
        CaseFrame(.idle(cards: idleCards.count))
    }
}

/// Holds the driver for the run on screen. Not observed: the timeline redraws every frame.
final class CaseEngine {
    private(set) var runID: UUID?
    private(set) var settledID: UUID?
    private var driver: CaseDriver?
    private var lastDate: Date?

    func step(at date: Date, run: CaseRun?, reduced: Bool, onSettled: @escaping (UUID) -> Void) -> CaseFrame? {
        guard let run else {
            runID = nil
            driver = nil
            return nil
        }
        if run.id != runID {
            runID = run.id
            driver = CaseDriver(direction: run.direction, cards: run.cards.count, reduced: reduced)
            lastDate = date
        }
        guard let driver else { return nil }
        let dt = lastDate.map { date.timeIntervalSince($0) } ?? 0
        lastDate = date
        let events = driver.advance(by: dt, progress: run.progress, finished: run.finished)
        if events.contains(where: { $0 == .latchLeft || $0 == .latchRight }) {
            Haptics.latch()
        }
        if driver.isSettled, settledID != run.id {
            settledID = run.id
            let id = run.id
            DispatchQueue.main.async { onSettled(id) }
        }
        return driver.frame(badge: run.refresh != .none)
    }
}

/// The case in the window's drop highlight: the lid swings wide and the case bounces.
struct CaseDropTarget: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            CaseScene(frame: CaseFrame(reduceMotion ? CasePose(lidOpen: CaseMotion.hoverOpen, latches: [0, 0])
                                                    : CaseMotion.hoverPose(elapsed: elapsed)),
                      layout: .target)
        }
        .frame(width: CaseLayout.target.size.width, height: CaseLayout.target.size.height)
        .onAppear { start = Date() }
    }
}
