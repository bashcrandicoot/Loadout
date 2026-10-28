import AppKit
import CoreImage

/// Built-in sample frames for LUT previews (drawn in code, so there are no stock images to license).
enum SampleFrame: String, CaseIterable, Identifiable {
    case nightExterior = "Night Exterior"
    case goldenHour = "Golden Hour"
    case portrait = "Skin Tones"
    case chart = "Grey Ramp"

    var id: String { rawValue }

    /// Draws the frame at `size` in sRGB.
    func render(size: CGSize = CGSize(width: 640, height: 360), flat: Bool = false) -> CGImage? {
        let w = Int(size.width), h = Int(size.height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
            // A log-looking flat version: lifted blacks, lowered whites, less saturation.
            guard flat else { return CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
            let l = 0.3 * r + 0.59 * g + 0.11 * b
            func f(_ c: CGFloat) -> CGFloat { 0.12 + 0.62 * pow(l + (c - l) * 0.55, 0.62) }
            return CGColor(srgbRed: f(r), green: f(g), blue: f(b), alpha: 1)
        }
        func gradient(_ top: (CGFloat, CGFloat, CGFloat), _ bottom: (CGFloat, CGFloat, CGFloat), from y0: CGFloat, to y1: CGFloat) {
            let g = CGGradient(colorsSpace: space, colors: [color(top.0, top.1, top.2), color(bottom.0, bottom.1, bottom.2)] as CFArray,
                               locations: [0, 1])!
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: min(y0, y1), width: size.width, height: abs(y1 - y0)))
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: y0), end: CGPoint(x: 0, y: y1), options: [])
            ctx.restoreGState()
        }
        func fill(_ rect: CGRect, _ c: (CGFloat, CGFloat, CGFloat)) { ctx.setFillColor(color(c.0, c.1, c.2)); ctx.fill(rect) }
        func oval(_ rect: CGRect, _ c: (CGFloat, CGFloat, CGFloat)) { ctx.setFillColor(color(c.0, c.1, c.2)); ctx.fillEllipse(in: rect) }
        let W = size.width, H = size.height

        switch self {
        case .nightExterior:
            gradient((0.02, 0.03, 0.08), (0.10, 0.12, 0.22), from: H, to: H * 0.35)
            fill(CGRect(x: 0, y: 0, width: W, height: H * 0.35), (0.05, 0.05, 0.06))
            // Buildings with lit windows.
            let towers: [(CGFloat, CGFloat, CGFloat)] = [(0.02, 0.18, 0.55), (0.22, 0.16, 0.72), (0.40, 0.2, 0.5), (0.62, 0.15, 0.8), (0.80, 0.18, 0.6)]
            for (x, wd, ht) in towers {
                let rect = CGRect(x: W * x, y: H * 0.35, width: W * wd, height: H * ht * 0.6)
                fill(rect, (0.07, 0.08, 0.11))
                var wy = rect.minY + 10
                while wy < rect.maxY - 12 {
                    var wx = rect.minX + 8
                    while wx < rect.maxX - 12 {
                        if Int(wx * 7 + wy * 3) % 5 < 2 { fill(CGRect(x: wx, y: wy, width: 6, height: 8), (0.95, 0.72, 0.38)) }
                        wx += 14
                    }
                    wy += 16
                }
            }
            // Neon signs and street lights.
            fill(CGRect(x: W * 0.27, y: H * 0.52, width: W * 0.08, height: 10), (1.0, 0.18, 0.55))
            fill(CGRect(x: W * 0.66, y: H * 0.6, width: W * 0.1, height: 10), (0.1, 0.85, 0.95))
            for x in stride(from: W * 0.08, to: W, by: W * 0.22) {
                oval(CGRect(x: x, y: H * 0.38, width: 14, height: 14), (1.0, 0.85, 0.6))
            }
            fill(CGRect(x: 0, y: H * 0.1, width: W, height: 3), (0.85, 0.75, 0.3))
        case .goldenHour:
            gradient((0.30, 0.45, 0.75), (1.0, 0.72, 0.42), from: H, to: H * 0.3)
            oval(CGRect(x: W * 0.62, y: H * 0.32, width: H * 0.22, height: H * 0.22), (1.0, 0.93, 0.75))
            gradient((0.42, 0.36, 0.18), (0.18, 0.15, 0.08), from: H * 0.3, to: 0)
            ctx.setFillColor(color(0.08, 0.06, 0.05))
            ctx.fill(CGRect(x: W * 0.2, y: H * 0.3, width: W * 0.025, height: H * 0.35))
            ctx.fillEllipse(in: CGRect(x: W * 0.13, y: H * 0.55, width: W * 0.17, height: H * 0.28))
            fill(CGRect(x: W * 0.42, y: H * 0.18, width: W * 0.05, height: H * 0.22), (0.12, 0.09, 0.08))
            oval(CGRect(x: W * 0.425, y: H * 0.39, width: W * 0.04, height: W * 0.04), (0.55, 0.38, 0.28))
        case .portrait:
            gradient((0.22, 0.28, 0.32), (0.12, 0.14, 0.16), from: H, to: 0)
            let tones: [(CGFloat, CGFloat, CGFloat)] = [(0.98, 0.84, 0.74), (0.90, 0.70, 0.56), (0.78, 0.56, 0.40),
                                                         (0.62, 0.42, 0.29), (0.45, 0.30, 0.20), (0.30, 0.20, 0.14)]
            for (i, t) in tones.enumerated() {
                let x = W * (0.06 + CGFloat(i) * 0.15)
                oval(CGRect(x: x, y: H * 0.3, width: W * 0.12, height: H * 0.42), t)
                fill(CGRect(x: x - 4, y: 0, width: W * 0.12 + 8, height: H * 0.24), (0.15 + CGFloat(i) * 0.1, 0.25, 0.45 - CGFloat(i) * 0.04))
            }
        case .chart:
            for i in 0..<16 {
                let v = CGFloat(i) / 15
                fill(CGRect(x: W * CGFloat(i) / 16, y: H * 0.5, width: W / 16 + 1, height: H * 0.5), (v, v, v))
            }
            let patches: [(CGFloat, CGFloat, CGFloat)] = [(0.45, 0.32, 0.26), (0.76, 0.58, 0.50), (0.36, 0.48, 0.61), (0.35, 0.42, 0.26),
                                                           (0.51, 0.50, 0.69), (0.39, 0.74, 0.67), (0.85, 0.48, 0.18), (0.29, 0.36, 0.65),
                                                           (0.76, 0.33, 0.38), (0.36, 0.24, 0.42), (0.62, 0.74, 0.25), (0.89, 0.63, 0.16)]
            for (i, p) in patches.enumerated() {
                let col = i % 6, row = i / 6
                fill(CGRect(x: W * CGFloat(col) / 6 + 3, y: H * (0.25 - CGFloat(row) * 0.25) + 3, width: W / 6 - 6, height: H * 0.25 - 6), p)
            }
        }
        return ctx.makeImage()
    }
}

/// Applies a LUT to a sample frame for the before/after preview.
enum LUTPreview {
    private static let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    private static var cache: [String: CGImage] = [:]
    private static let lock = NSLock()

    /// Log-to-Rec.709 LUTs look right on flat footage; creative ones on normal footage.
    static func expectsLog(_ url: URL) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        return ["log", "lgc", "to 709", "to_709", "to rec709", "2rec709", "-709", "_709", "cinegamut", "s-gamut", "sgamut", "braw", "film gen", "gen 5"]
            .contains { name.contains($0) }
    }

    static func image(for lutURL: URL, frame: SampleFrame) -> (before: CGImage, after: CGImage)? {
        let flat = expectsLog(lutURL)
        guard let before = frame.render(flat: flat) else { return nil }
        let key = "\(lutURL.path)|\(frame.rawValue)"
        lock.lock(); let cached = cache[key]; lock.unlock()
        if let cached { return (before, cached) }
        guard lutURL.pathExtension.lowercased() == "cube", let lut = try? CubeLUT(url: lutURL) else { return nil }
        let cube = lut.colorCubeData()
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let filter = CIFilter(name: "CIColorCubeWithColorSpace") else { return nil }
        filter.setValue(CIImage(cgImage: before), forKey: kCIInputImageKey)
        filter.setValue(cube.dimension, forKey: "inputCubeDimension")
        filter.setValue(cube.data, forKey: "inputCubeData")
        filter.setValue(space, forKey: "inputColorSpace")
        guard let output = filter.outputImage,
              let after = context.createCGImage(output, from: CGRect(x: 0, y: 0, width: before.width, height: before.height)) else { return nil }
        lock.lock(); cache[key] = after; if cache.count > 200 { cache.removeAll() }; lock.unlock()
        return (before, after)
    }
}
