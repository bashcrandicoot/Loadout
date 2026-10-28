import SwiftUI
import AppKit

// The flight case from Loadout's icon (Maddy's A4 · Kit Case — Color Bar), drawn from her
// vector layers in Assets.xcassets/LoadoutCase so it can open, latch and fill. Every layer
// is on the same 640 × 560 case artboard (icon-1024 minus (192, 232)), so the layers stack in
// register and only the pivots below are numbers. Her notes: docs/case-art.md and
// docs/case-art/layers.json.

/// One of Maddy's case layers, named after its imageset.
enum CaseArtLayer: String, CaseIterable {
    case contactShadow = "LoadoutCaseContactShadow"
    case handle = "LoadoutCaseHandle"
    case body = "LoadoutCaseBody"
    case lid = "LoadoutCaseLid"
    case railsBody = "LoadoutCaseRailsBody"
    case railsLid = "LoadoutCaseRailsLid"
    case colorBar = "LoadoutCaseColorBar"
    case latchLeftBase = "LoadoutCaseLatchLeftBase"
    case latchLeftLeverClosed = "LoadoutCaseLatchLeftLeverClosed"
    case latchLeftLeverOpen = "LoadoutCaseLatchLeftLeverOpen"
    case latchRightBase = "LoadoutCaseLatchRightBase"
    case latchRightLeverClosed = "LoadoutCaseLatchRightLeverClosed"
    case latchRightLeverOpen = "LoadoutCaseLatchRightLeverOpen"

    /// The rig groups from layers.json, back to front (the latch plates are split at the seam).
    static let lidGroup: [CaseArtLayer] = [.handle, .lid, .railsLid]
    static let bodyGroup: [CaseArtLayer] = [.body, .railsBody, .colorBar, .latchLeftBase, .latchRightBase]

    var isInCatalog: Bool { NSImage(named: rawValue) != nil }
}

/// Where things are on the 640 × 560 case artboard (y down, like SwiftUI).
enum CaseGeometry {
    static let artboard = CGSize(width: 640, height: 560)
    /// The lid meets the body here (the hinge line, icon y 498).
    static let seamY = 266.0
    /// The top of the lid (icon y 404).
    static let lidTopY = 172.0
    /// The case's outline (lid + body, icon 264…760 × 404…719).
    static let shellRect = CGRect(x: 72, y: 172, width: 496, height: 315)
    /// The shell's corner radius (Maddy's caseShape clip, rx 48).
    static let cornerRadius = 48.0
    /// Maddy's rails run down both sides of the shell, 30 units wide.
    static let railWidth = 30.0
    /// Everything that's drawn, handle and contact shadow included.
    static let visibleRect = CGRect(x: 64, y: 72, width: 512, height: 448)
    /// Lever pins (icon [356, 540] and [668, 540]).
    static let latchPivots = [CGPoint(x: 164, y: 308), CGPoint(x: 476, y: 308)]
    /// The gradient inside the colour bar's well (icon 338, 580, 348 × 78, r 39); the fill grows from its left edge.
    static let barFillRect = CGRect(x: 146, y: 348, width: 348, height: 78)
    /// The bar's well colour, from Maddy's SVG (#111A2E).
    static let barWell = Color(red: 0x11 / 255, green: 0x1A / 255, blue: 0x2E / 255)
    /// The contact shadow's centre.
    static let shadowCenter = CGPoint(x: 320, y: 498)
    /// Where the Restart / Update Lists badge pops on (its centre).
    static let badgeCenter = CGPoint(x: 540, y: 176)
    /// Cards drop in (and lift out) here.
    static let mouthCenter = CGPoint(x: 320, y: seamY)

    static func unit(_ point: CGPoint) -> UnitPoint {
        UnitPoint(x: point.x / artboard.width, y: point.y / artboard.height)
    }
}

/// A layer on the full artboard, at `scale` points per artboard unit.
struct CaseLayerImage: View {
    let layer: CaseArtLayer
    let scale: Double

    init(_ layer: CaseArtLayer, scale: Double) {
        self.layer = layer
        self.scale = scale
    }

    var body: some View {
        Image(layer.rawValue)
            .resizable()
            .interpolation(.high)
            .frame(width: CaseGeometry.artboard.width * scale, height: CaseGeometry.artboard.height * scale)
    }
}

// MARK: - The case, split around the cards

/// The parts behind the cards: contact shadow, the inside, and the lid group (lid, rails, handle).
struct CaseBack: View {
    let pose: CasePose
    let scale: Double

    var body: some View {
        let open = CaseMotion.clamp(pose.lidOpen, 0, 1.2)
        let s = scale
        ZStack(alignment: .topLeading) {
            // Lifting the case (a bounce) shrinks and fades its shadow.
            CaseLayerImage(.contactShadow, scale: s)
                .scaleEffect(x: 1 + pose.bounce / 160, y: 1, anchor: CaseGeometry.unit(CaseGeometry.shadowCenter))
                .opacity(1 + pose.bounce / 50)
            Group {
                CaseInterior(open: open, scale: s)
                lid(open: open)
            }
            .offset(y: pose.bounce * s)
        }
        .frame(width: CaseGeometry.artboard.width * s, height: CaseGeometry.artboard.height * s, alignment: .topLeading)
    }

    /// The lid lifts off the seam and tips back on its rear hinge, so its front face foreshortens.
    private func lid(open: Double) -> some View {
        ZStack(alignment: .topLeading) {
            CaseLayerImage(.handle, scale: scale)
            CaseLayerImage(.lid, scale: scale).lidCornersTucked(scale: scale)
            CaseLayerImage(.railsLid, scale: scale)
            // The latch plates straddle the seam: their top half (the catch) rides on the lid.
            ForEach([CaseArtLayer.latchLeftBase, .latchRightBase], id: \.self) {
                CaseLayerImage($0, scale: scale).seamClipped(above: true, scale: scale)
            }
        }
        .rotation3DEffect(.degrees(open * 52), axis: (x: 1, y: 0, z: 0),
                          anchor: UnitPoint(x: 0.5, y: CaseGeometry.lidTopY / CaseGeometry.artboard.height),
                          perspective: 0.35)
        .offset(y: -open * 46 * scale)
    }
}

/// The dark inside, seen between the lifted lid and the body. Maddy's set has no interior
/// layer, so this one is drawn in her well colour.
struct CaseInterior: View {
    let open: Double
    let scale: Double

    var body: some View {
        Canvas { context, _ in
            guard open > 0.001 else { return }
            let s = scale
            let shell = CaseGeometry.shellRect
            let depth = 30 + open * 60
            let rect = CGRect(x: (shell.minX + 14) * s, y: (CaseGeometry.seamY - depth) * s,
                              width: (shell.width - 28) * s, height: (depth + 4) * s)
            let path = Path(roundedRect: rect, cornerRadius: 14 * s)
            context.fill(path, with: .linearGradient(
                Gradient(colors: [Color(red: 0.23, green: 0.27, blue: 0.34), CaseGeometry.barWell]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        }
        .frame(width: CaseGeometry.artboard.width * scale, height: CaseGeometry.artboard.height * scale)
        .opacity(CaseMotion.smooth(0, 0.1, open))
    }
}

/// The parts in front of the cards: the body group (body, rails, colour bar, latch plates),
/// the latch levers, and the badge.
struct CaseFront: View {
    let pose: CasePose
    let scale: Double
    var badgeText: String?

    var body: some View {
        let s = scale
        ZStack(alignment: .topLeading) {
            CaseLayerImage(.body, scale: s)
            CaseLayerImage(.railsBody, scale: s)
            CaseBar(fill: pose.bar, glint: pose.glint, scale: s)
            CaseLayerImage(.latchLeftBase, scale: s).seamClipped(above: false, scale: s)
            CaseLayerImage(.latchRightBase, scale: s).seamClipped(above: false, scale: s)
            CaseLatch(closed: .latchLeftLeverClosed, open: .latchLeftLeverOpen,
                      value: pose.latches.first ?? 1, pivot: CaseGeometry.latchPivots[0], scale: s)
            CaseLatch(closed: .latchRightLeverClosed, open: .latchRightLeverOpen,
                      value: pose.latches.last ?? 1, pivot: CaseGeometry.latchPivots[1], scale: s)
            if let badgeText, pose.badge > 0 {
                CaseBadge(text: badgeText, scale: s)
                    .scaleEffect(max(0.01, pose.badge))
                    .opacity(CaseMotion.clamp(pose.badge * 3))
                    .position(x: CaseGeometry.badgeCenter.x * s, y: CaseGeometry.badgeCenter.y * s)
            }
        }
        .offset(y: pose.bounce * s)
        .frame(width: CaseGeometry.artboard.width * s, height: CaseGeometry.artboard.height * s, alignment: .topLeading)
    }
}

extension View {
    /// Maddy's note: stacked, the lid and the (90 % opaque) lid rails both antialias along the
    /// case's rounded top corners, and the lid's white edge shows through as a faint seam.
    /// Pulling the lid 1.5 units in under the rails only tucks its edge out of sight.
    func lidCornersTucked(scale: Double) -> some View {
        let shell = CaseGeometry.shellRect
        let inset = shell.insetBy(dx: 1.5, dy: 1.5)
        return mask(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 46.5 * scale, style: .circular)
                    .frame(width: inset.width * scale, height: inset.height * scale)
                    .offset(x: inset.minX * scale, y: inset.minY * scale)
                // Between the rails (30 wide each side) the lid keeps its full edge.
                Rectangle()
                    .frame(width: (shell.width - 2 * CaseGeometry.railWidth) * scale, height: shell.height * scale)
                    .offset(x: (shell.minX + CaseGeometry.railWidth) * scale, y: shell.minY * scale)
            }
            .frame(width: CaseGeometry.artboard.width * scale, height: CaseGeometry.artboard.height * scale, alignment: .topLeading)
        }
    }

    /// Keeps the part of a layer above the seam (with a 1-unit overlap hidden behind the
    /// body, so the two halves meet without a hairline) or below it.
    func seamClipped(above: Bool, scale: Double) -> some View {
        let size = CaseGeometry.artboard
        let seam = CaseGeometry.seamY
        let rect = above ? CGRect(x: 0, y: 0, width: size.width, height: seam + 1)
                         : CGRect(x: 0, y: seam, width: size.width, height: size.height - seam)
        return mask(alignment: .topLeading) {
            Rectangle()
                .frame(width: rect.width * scale, height: rect.height * scale)
                .offset(y: rect.minY * scale)
        }
    }
}

/// A latch lever swinging 180° on its pin: the closed lever up to edge-on, then Maddy's open
/// lever from edge-on to hanging down. `value` 1 = closed (it may overshoot a little).
struct CaseLatch: View {
    let closed: CaseArtLayer
    let open: CaseArtLayer
    let value: Double
    let pivot: CGPoint
    let scale: Double

    var body: some View {
        let angle = (1 - value) * 180
        let anchor = CaseGeometry.unit(pivot)
        if angle <= 90 {
            CaseLayerImage(closed, scale: scale)
                .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), anchor: anchor, perspective: 0.5)
        } else {
            CaseLayerImage(open, scale: scale)
                .rotation3DEffect(.degrees(angle - 180), axis: (x: 1, y: 0, z: 0), anchor: anchor, perspective: 0.5)
        }
    }
}

/// Maddy's colour bar as the progress bar: her layer, with the part not yet filled covered in
/// the bar's own well colour, plus a glint once it's full.
struct CaseBar: View {
    let fill: Double
    let glint: Double?
    let scale: Double

    var body: some View {
        let s = scale
        let rect = CaseGeometry.barFillRect
        let pill = Path(roundedRect: CGRect(x: rect.minX * s, y: rect.minY * s, width: rect.width * s, height: rect.height * s),
                        cornerRadius: rect.height / 2 * s)
        let fill = CaseMotion.clamp(fill)
        ZStack(alignment: .topLeading) {
            CaseLayerImage(.colorBar, scale: s)
            Canvas { context, _ in
                guard fill < 1 else { return }
                context.clip(to: pill)
                let edge = (rect.minX + rect.width * fill) * s
                let empty = CGRect(x: edge, y: rect.minY * s, width: (rect.maxX * s) - edge + 1, height: rect.height * s)
                context.fill(Path(empty), with: .color(CaseGeometry.barWell))
                // A soft lit edge where the fill stops.
                if fill > 0.01 {
                    context.fill(Path(CGRect(x: edge, y: rect.minY * s, width: max(1, 3 * s), height: rect.height * s)),
                                 with: .color(.white.opacity(0.25)))
                }
            }
            if let glint {
                Canvas { context, _ in
                    context.clip(to: pill)
                    let x = (rect.minX - 50 + (rect.width + 100) * glint) * s
                    let band = Path { p in
                        p.move(to: CGPoint(x: x - 14 * s, y: rect.maxY * s))
                        p.addLine(to: CGPoint(x: x + 16 * s, y: rect.minY * s))
                        p.addLine(to: CGPoint(x: x + 44 * s, y: rect.minY * s))
                        p.addLine(to: CGPoint(x: x + 14 * s, y: rect.maxY * s))
                        p.closeSubpath()
                    }
                    context.fill(band, with: .linearGradient(
                        Gradient(colors: [.white.opacity(0), .white.opacity(0.85), .white.opacity(0)]),
                        startPoint: CGPoint(x: x - 14 * s, y: 0), endPoint: CGPoint(x: x + 44 * s, y: 0)))
                }
            }
        }
        .frame(width: CaseGeometry.artboard.width * s, height: CaseGeometry.artboard.height * s, alignment: .topLeading)
    }
}

/// "Restart" or "Update Lists", on the case's corner.
struct CaseBadge: View {
    let text: String
    var scale: Double = 0.3

    var body: some View {
        let size = max(9, 34 * scale)
        HStack(spacing: size * 0.3) {
            Image(systemName: "arrow.clockwise").font(.system(size: size * 0.85, weight: .bold))
            Text(text).font(.system(size: size, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, size * 0.65)
        .padding(.vertical, size * 0.3)
        .background(Capsule().fill(Color.orange))
        .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        .fixedSize()
    }

    static func text(for refresh: ResolveRefresh) -> String? {
        switch refresh {
        case .none: return nil
        case .updateLists: return "Update Lists"
        case .restart: return "Restart"
        }
    }
}
