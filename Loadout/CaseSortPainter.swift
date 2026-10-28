import SwiftUI

// Draws a case-sort frame into a Canvas, layer for layer like her renderAt():
// desk → back cards → case glow → case back → cards in the case → case front → flying cards → sparkles.

extension Color {
    init(caseHex hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

/// Maddy's case layers (Assets.xcassets/LoadoutCase, each a 640 × 560 artboard).
enum CaseSortLayer: String, CaseIterable {
    case contactShadow = "LoadoutCaseContactShadow"
    case handle = "LoadoutCaseHandle"
    case lid = "LoadoutCaseLid"
    case railsLid = "LoadoutCaseRailsLid"
    case body = "LoadoutCaseBody"
    case railsBody = "LoadoutCaseRailsBody"
    case latchLeftBase = "LoadoutCaseLatchLeftBase"
    case latchRightBase = "LoadoutCaseLatchRightBase"
    case latchLeftClosed = "LoadoutCaseLatchLeftLeverClosed"
    case latchLeftOpen = "LoadoutCaseLatchLeftLeverOpen"
    case latchRightClosed = "LoadoutCaseLatchRightLeverClosed"
    case latchRightOpen = "LoadoutCaseLatchRightLeverOpen"
}

struct CaseSortPainter {
    let layout: CaseSortLayout
    /// The strip draws the night desk and the cards; the drop target is just the case.
    var drawsDesk = true
    var drawsCards = true

    private var stage: CaseSortStage { layout.stage }
    private typealias M = CaseSort

    func paint(_ frame: CaseSortFrame, in context: inout GraphicsContext) {
        for (i, layer) in frame.layers.enumerated() {
            if i == 0 {
                paint(layer.phases, bar: layer.bar, in: context)
            } else {
                // The scene is opaque, so a crossfade is the new frame drawn over the old.
                context.drawLayer { sub in
                    sub.opacity = layer.opacity
                    paint(layer.phases, bar: layer.bar, in: sub)
                }
            }
        }
    }

    private func paint(_ ph: CaseSortPhases, bar: Double?, in ctx: GraphicsContext) {
        let p = ph.progress, a = ph.arrival
        let cards = drawsCards ? layout.cards : []
        let poses = cards.indices.map { layout.pose($0, progress: p, arrival: a) }
        let us = cards.indices.map { layout.cardProgress($0, p) }

        if drawsDesk {
            ctx.draw(ctx.resolve(Image("LoadoutStripBackground")),
                     in: CGRect(origin: .zero, size: stage.size))
            // The sky glow behind the case (drawn here: a PDF loses its stop opacities).
            fillEllipse(center: CGPoint(x: 404, y: 70), rx: 260, ry: 80,
                        stops: [.init(color: Color(caseHex: 0x64D2FF, opacity: 0.30), location: 0),
                                .init(color: Color(caseHex: 0x0A84FF, opacity: 0.12), location: 0.5),
                                .init(color: Color(caseHex: 0x0A84FF, opacity: 0), location: 1)],
                        opacity: 1, in: ctx)
        }
        // Desk shadows under the resting cards.
        for (i, card) in cards.enumerated() { drawDeskShadow(card, u: us[i], in: ctx) }
        for (i, card) in cards.enumerated() where poses[i].layer == .desk { drawCard(card, poses[i], in: ctx) }

        drawCaseGlow(ph, in: ctx)

        var outer = ctx
        outer.translateBy(x: 0, y: 3 * M.thud(ph) * stage.scale / 0.92)
        let icon = iconContext(outer)
        drawCaseBack(ph, in: icon)
        for (i, card) in cards.enumerated() where poses[i].layer == .inCase { drawCard(card, poses[i], in: outer) }
        drawCaseFront(ph, bar: bar, us: us, in: icon)

        for (i, card) in cards.enumerated() where poses[i].layer == .flying { drawCard(card, poses[i], in: ctx) }
        drawSparkles(ph, in: ctx)
    }

    // MARK: Pieces

    private func iconContext(_ ctx: GraphicsContext) -> GraphicsContext {
        var c = ctx
        let origin = stage.point(0, 0)
        c.translateBy(x: origin.x, y: origin.y)
        c.scaleBy(x: stage.scale, y: stage.scale)
        return c
    }

    private func drawArt(_ layer: CaseSortLayer, in ctx: GraphicsContext) {
        ctx.draw(ctx.resolve(Image(layer.rawValue)), in: M.artboard)
    }

    /// An elliptical radial gradient (SVG's objectBoundingBox r=.5).
    private func fillEllipse(center: CGPoint, rx: Double, ry: Double, stops: [Gradient.Stop],
                             opacity: Double, in ctx: GraphicsContext) {
        guard opacity > 0.001, rx > 0, ry > 0 else { return }
        var c = ctx
        c.opacity *= opacity
        c.translateBy(x: center.x, y: center.y)
        c.scaleBy(x: rx, y: ry)
        c.fill(Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
               with: .radialGradient(Gradient(stops: stops), center: .zero, startRadius: 0, endRadius: 1))
    }

    private func cardTransform(_ pose: CaseSortCardPose, _ ctx: GraphicsContext) -> GraphicsContext {
        var c = ctx
        c.translateBy(x: pose.x, y: pose.y)
        if pose.skew != 0 { c.concatenate(CGAffineTransform(a: 1, b: 0, c: tan(pose.skew * .pi / 180), d: 1, tx: 0, ty: 0)) }
        c.scaleBy(x: pose.scale, y: pose.scale * pose.flatten)
        c.rotate(by: .degrees(pose.rotation))
        return c
    }

    private func drawDeskShadow(_ card: CaseSortCard, u: Double, in ctx: GraphicsContext) {
        guard drawsDesk else { return }
        let size = card.art.size
        let contact = 0.8 * (1 - M.smooth(0, 0.12, u))
        fillEllipse(center: CGPoint(x: card.start.x + 2, y: 100.5), rx: size.width * card.start.scale * 0.55, ry: 2.2,
                    stops: [.init(color: Color(caseHex: 0x020A1E, opacity: 0.55), location: 0),
                            .init(color: Color(caseHex: 0x020A1E, opacity: 0), location: 1)],
                    opacity: contact, in: ctx)
        if let shadow = card.art.deskShadow {
            let o = 1 - M.smooth(0, 0.14, u)
            guard o > 0.001 else { return }
            var c = cardTransform(card.start, ctx)
            c.opacity *= o
            c.fill(Path(roundedRect: shadow.rect, cornerRadius: shadow.radius),
                   with: .color(Color(caseHex: 0x020818, opacity: shadow.opacity)))
        }
    }

    private func drawCard(_ card: CaseSortCard, _ pose: CaseSortCardPose, in ctx: GraphicsContext) {
        let c = cardTransform(pose, ctx)
        let size = card.art.size
        let color = card.group.color
        if pose.glow > 0.001 {
            fillEllipse(center: .zero, rx: size.width * 0.85, ry: size.height * 0.85,
                        stops: [.init(color: Color(caseHex: color, opacity: 0.7), location: 0),
                                .init(color: Color(caseHex: color, opacity: 0), location: 1)],
                        opacity: pose.glow, in: c)
        }
        let m = CaseSortArt.imageMargin
        c.draw(c.resolve(Image(card.art.imageName)),
               in: CGRect(x: -size.width / 2 - m, y: -size.height / 2 - m, width: size.width + 2 * m, height: size.height + 2 * m))
    }

    private func drawCaseGlow(_ ph: CaseSortPhases, in ctx: GraphicsContext) {
        let g = M.glow(ph)
        guard g > 0.001 else { return }
        let sc = stage.scale
        fillEllipse(center: stage.point(512, 560), rx: 600 * sc, ry: 420 * sc,
                    stops: [.init(color: Color(caseHex: 0x64D2FF, opacity: 0.55), location: 0),
                            .init(color: Color(caseHex: 0x0A84FF, opacity: 0.22), location: 0.45),
                            .init(color: Color(caseHex: 0x0A84FF, opacity: 0), location: 1)],
                    opacity: min(1, g * 1.5), in: ctx)
        fillEllipse(center: stage.point(512, 690), rx: 420 * sc, ry: 90 * sc,
                    stops: [.init(color: Color(caseHex: 0xFF8A4C, opacity: 0.45), location: 0),
                            .init(color: Color(caseHex: 0xE65BA0, opacity: 0.16), location: 0.5),
                            .init(color: Color(caseHex: 0xE65BA0, opacity: 0), location: 1)],
                    opacity: min(1, g * 1.4), in: ctx)
    }

    private func drawCaseBack(_ ph: CaseSortPhases, in icon: GraphicsContext) {
        let theta = M.lidAngle(ph) * .pi / 180
        let c = cos(theta), s = sin(theta)
        let seam = M.seam, depth = M.lidDepth
        drawArt(.contactShadow, in: icon)
        if c > 0.05 {
            var h = icon
            h.translateBy(x: 0, y: seam - depth / 2 * s)
            h.scaleBy(x: 1, y: c)
            h.translateBy(x: 0, y: -seam)
            drawArt(.handle, in: h)
        }
        // The lid's underside: a rim, the navy lining, a pocket with its strap.
        let y0 = seam - 94 * c - depth * s
        let top = min(y0, seam - depth * s)
        let height = seam - top
        guard M.lidAngle(ph) > 0.5, height > 1 else { return }
        icon.fill(Path(roundedRect: CGRect(x: 264, y: top, width: 496, height: height),
                       cornerSize: CGSize(width: 44, height: min(44, height / 2))),
                  with: .linearGradient(Gradient(stops: [.init(color: Color(caseHex: 0xC9D2DE), location: 0),
                                                         .init(color: Color(caseHex: 0x8E9BAD), location: 0.25),
                                                         .init(color: Color(caseHex: 0x4A5568), location: 1)]),
                                        startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: top + height)))
        let inner = max(0, height - 16.8)
        if inner > 0 {
            icon.fill(Path(roundedRect: CGRect(x: 278, y: top + 14, width: 468, height: inner),
                           cornerSize: CGSize(width: 32, height: min(32, inner / 2))),
                      with: .linearGradient(Gradient(colors: [Color(caseHex: 0x1B2E5C), Color(caseHex: 0x0A1430)]),
                                            startPoint: CGPoint(x: 0, y: top + 14), endPoint: CGPoint(x: 0, y: top + 14 + inner)))
            let pocketY = top + 14 + inner * 0.18
            let pocket = inner * 0.4
            icon.fill(Path(roundedRect: CGRect(x: 318, y: pocketY, width: 388, height: pocket),
                           cornerSize: CGSize(width: 16, height: min(16, pocket / 2))),
                      with: .color(Color(caseHex: 0x2A4C8F, opacity: 0.45)))
            if pocket > 6 {
                icon.fill(Path(CGRect(x: 318, y: pocketY, width: 388, height: 3)), with: .color(Color(caseHex: 0x9CC8FF, opacity: 0.35)))
            }
        }
        if height > 20 {
            icon.fill(Path(roundedRect: CGRect(x: 300, y: top + 3, width: 424, height: 4), cornerRadius: 2),
                      with: .color(.white.opacity(0.7)))
        }
    }

    private func drawCaseFront(_ ph: CaseSortPhases, bar: Double?, us: [Double], in icon: GraphicsContext) {
        let thetaDeg = M.lidAngle(ph)
        let theta = thetaDeg * .pi / 180
        let c = cos(theta), s = sin(theta)
        let seam = M.seam
        let above = Path(CGRect(x: 0, y: 0, width: 1024, height: seam))
        let below = Path(CGRect(x: 0, y: seam, width: 1024, height: 1024 - seam))

        // The lid face: a 2D squash about the seam, as in her notes.
        if c > 0.001 {
            var lid = icon
            lid.translateBy(x: 0, y: seam - M.lidDepth * s)
            lid.scaleBy(x: 1, y: c)
            lid.translateBy(x: 0, y: -seam)
            drawArt(.lid, in: lid)
            drawArt(.railsLid, in: lid)
            var bases = lid
            bases.clip(to: above)
            drawArt(.latchLeftBase, in: bases)
            drawArt(.latchRightBase, in: bases)
        }
        drawArt(.body, in: icon)
        drawArt(.railsBody, in: icon)
        var ao = icon
        ao.opacity *= M.clamp(thetaDeg / 40)
        if ao.opacity > 0.001 {
            ao.fill(Path(CGRect(x: 264, y: seam, width: 496, height: 22)),
                    with: .linearGradient(Gradient(colors: [Color(caseHex: 0x020818, opacity: 0), Color(caseHex: 0x020818, opacity: 0.55)]),
                                          startPoint: CGPoint(x: 0, y: seam), endPoint: CGPoint(x: 0, y: seam + 22)))
        }
        drawBar(ph, bar: bar, in: icon)
        var bases = icon
        bases.clip(to: below)
        drawArt(.latchLeftBase, in: bases)
        drawArt(.latchRightBase, in: bases)

        let flips = M.latchAngles(ph), pulses = M.latchPulses(ph)
        drawLever(flips.left, pulse: pulses.left, pivot: M.latchPivots[0], closed: .latchLeftClosed, open: .latchLeftOpen, in: icon)
        drawLever(flips.right, pulse: pulses.right, pivot: M.latchPivots[1], closed: .latchRightClosed, open: .latchRightOpen, in: icon)

        // Landing sparks: five dots burst from the bar as each card lands.
        for (i, card) in layout.cards.enumerated() where drawsCards {
            let u = us[i]
            guard u > 0.84 && u < 1 else { continue }
            let kd = M.clamp((u - 0.84) / 0.16)
            let column = (layout.edges[card.segment] + layout.edges[card.segment + 1]) / 2
            var dots = icon
            dots.opacity *= 1 - kd
            for j in 0..<5 {
                let angle = (-150 + 30 * Double(j)) * .pi / 180
                let rr = 20 + 70 * M.easeOutCubic(kd)
                let r = 9 * (1 - kd) + 2
                let center = CGPoint(x: column + cos(angle) * rr, y: seam - 6 + sin(angle) * rr * 0.8)
                dots.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                          with: .color(Color(caseHex: card.group.color)))
            }
        }
    }

    private func drawLever(_ phi: Double, pulse: Double, pivot: CGPoint, closed: CaseSortLayer, open: CaseSortLayer,
                           in icon: GraphicsContext) {
        let k = cos(phi * .pi / 180)
        let grow = 1 + 0.08 * pulse
        var c = icon
        c.translateBy(x: pivot.x, y: pivot.y)
        c.scaleBy(x: grow, y: (k >= 0 ? max(k, 0.02) : -k) * grow)
        c.translateBy(x: -pivot.x, y: -pivot.y)
        drawArt(k >= 0 ? closed : open, in: c)
    }

    private var filmGradient: Gradient {
        Gradient(stops: [.init(color: Color(caseHex: 0xFFC66A), location: 0), .init(color: Color(caseHex: 0xFF8A4C), location: 0.3),
                         .init(color: Color(caseHex: 0xE65BA0), location: 0.55), .init(color: Color(caseHex: 0x8E5CF0), location: 0.78),
                         .init(color: Color(caseHex: 0x2E9BFF), location: 1)])
    }

    /// The colour bar, drawn in code (her bar group): it is the progress bar.
    private func drawBar(_ ph: CaseSortPhases, bar: Double?, in icon: GraphicsContext) {
        let pill = CGRect(x: 338, y: 580, width: 348, height: 78)
        let pillPath = Path(roundedRect: pill, cornerRadius: 39)
        let film = GraphicsContext.Shading.linearGradient(filmGradient, startPoint: CGPoint(x: pill.minX, y: 0),
                                                           endPoint: CGPoint(x: pill.maxX, y: 0))
        icon.fill(Path(roundedRect: CGRect(x: 324, y: 566, width: 376, height: 106), cornerRadius: 53), with: .color(.white.opacity(0.95)))
        icon.fill(Path(roundedRect: CGRect(x: 328, y: 570, width: 368, height: 98), cornerRadius: 49), with: .color(Color(caseHex: 0x111A2E)))
        icon.fill(pillPath, with: .color(Color(caseHex: 0x1A2747)))
        var faint = icon
        faint.opacity *= 0.14
        faint.fill(pillPath, with: film)

        let p = bar ?? ph.progress
        let fills = layout.segmentFills(p)
        let pulses = bar == nil ? layout.segmentPulses(p) : fills.map { _ in 0 }
        let edges = layout.edges
        let last = fills.count - 1
        var fillPath = Path()
        for (k, f) in fills.enumerated() where f > 0 {
            let w = (edges[k + 1] - edges[k] + (k < last ? 1 : 0)) * f
            fillPath.addRect(CGRect(x: edges[k], y: 570, width: w, height: 98))
        }
        if !fillPath.isEmpty {
            var lit = icon
            lit.clip(to: fillPath)
            lit.fill(pillPath, with: film)
        }
        var inPill = icon
        inPill.clip(to: pillPath)
        for (k, pulse) in pulses.enumerated() where pulse > 0.001 {
            inPill.fill(Path(CGRect(x: edges[k], y: 580, width: edges[k + 1] - edges[k], height: 78)),
                        with: .color(.white.opacity(0.55 * pulse)))
        }
        let shimmer = M.shimmer(ph)
        if shimmer.opacity > 0.001 {
            var sh = inPill
            sh.opacity *= shimmer.opacity
            sh.concatenate(CGAffineTransform(a: 1, b: 0, c: tan(-18 * .pi / 180), d: 1, tx: 0, ty: 0))
            sh.fill(Path(CGRect(x: shimmer.x, y: 580, width: 90, height: 78)),
                    with: .linearGradient(Gradient(stops: [.init(color: .white.opacity(0), location: 0),
                                                           .init(color: .white.opacity(0.75), location: 0.5),
                                                           .init(color: .white.opacity(0), location: 1)]),
                                          startPoint: CGPoint(x: shimmer.x, y: 0), endPoint: CGPoint(x: shimmer.x + 90, y: 0)))
        }
        icon.fill(Path(roundedRect: CGRect(x: 362, y: 587, width: 300, height: 6), cornerRadius: 3), with: .color(.white.opacity(0.45)))
        for edge in edges.dropFirst().dropLast() {
            icon.fill(Path(roundedRect: CGRect(x: edge - 1.5, y: 584, width: 3, height: 70), cornerRadius: 1.5),
                      with: .color(.white.opacity(0.35)))
        }
    }

    private static let starPath: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -40))
        p.addCurve(to: CGPoint(x: 40, y: 0), control1: CGPoint(x: 5, y: -6), control2: CGPoint(x: 6, y: -5))
        p.addCurve(to: CGPoint(x: 0, y: 40), control1: CGPoint(x: 6, y: 5), control2: CGPoint(x: 5, y: 6))
        p.addCurve(to: CGPoint(x: -40, y: 0), control1: CGPoint(x: -5, y: 6), control2: CGPoint(x: -6, y: 5))
        p.addCurve(to: CGPoint(x: 0, y: -40), control1: CGPoint(x: -6, y: -5), control2: CGPoint(x: -5, y: -6))
        p.closeSubpath()
        return p
    }()

    private func drawSparkles(_ ph: CaseSortPhases, in ctx: GraphicsContext) {
        for (i, spark) in M.sparkles.enumerated() {
            let (k, v) = M.sparkle(i, ph)
            guard v > 0.001 else { continue }
            var c = ctx
            c.opacity *= v
            let at = stage.point(spark.point.x, spark.point.y)
            c.translateBy(x: at.x, y: at.y)
            c.rotate(by: .degrees(30 * k))
            let size = spark.size * v * stage.scale * 1.35
            c.scaleBy(x: size, y: size)
            c.fill(Path(ellipseIn: CGRect(x: -46, y: -46, width: 92, height: 92)),
                   with: .radialGradient(Gradient(stops: [.init(color: .white.opacity(0.9), location: 0),
                                                          .init(color: Color(caseHex: 0x9FD8FF, opacity: 0.35), location: 0.35),
                                                          .init(color: Color(caseHex: 0x64D2FF, opacity: 0), location: 1)]),
                                         center: .zero, startRadius: 0, endRadius: 46))
            c.fill(Self.starPath, with: .color(.white))
        }
    }
}

/// The dark 492 × 112 scene.
struct CaseSortScene: View {
    var frame: CaseSortFrame
    var layout: CaseSortLayout

    var body: some View {
        Canvas(opaque: true) { context, _ in
            CaseSortPainter(layout: layout).paint(frame, in: &context)
        }
        .frame(width: layout.stage.size.width, height: layout.stage.size.height)
    }
}
