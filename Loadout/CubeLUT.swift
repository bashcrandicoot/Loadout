import CoreImage
import simd
import Foundation

/// A parsed `.cube` LUT (Resolve/Adobe format), 1D or 3D.
struct CubeLUT {
    enum ParseError: LocalizedError {
        case notACube, badSize, badData(Int)
        var errorDescription: String? {
            switch self {
            case .notACube: return "This isn’t a .cube LUT."
            case .badSize: return "The LUT size is missing or unusual."
            case .badData(let line): return "The LUT data is damaged near line \(line)."
            }
        }
    }

    var title: String?
    /// Points per side for 3D, entries for 1D.
    var size: Int
    var is3D: Bool
    var domainMin: SIMD3<Float> = .zero
    var domainMax: SIMD3<Float> = .one
    /// RGB triples, red fastest (the .cube order).
    var values: [SIMD3<Float>]

    init(url: URL) throws {
        guard let text = try? String(contentsOf: url, encoding: .utf8) ?? String(contentsOf: url, encoding: .isoLatin1) else {
            throw ParseError.notACube
        }
        try self.init(text: text)
    }

    init(text: String) throws {
        var size3 = 0, size1 = 0
        var title: String?
        var dmin = SIMD3<Float>.zero, dmax = SIMD3<Float>.one
        var values: [SIMD3<Float>] = []
        var lineNumber = 0
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            lineNumber += 1
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let head = parts.first else { continue }
            switch head.uppercased() {
            case "TITLE":
                title = line.dropFirst(5).trimmingCharacters(in: CharacterSet(charactersIn: " \t\""))
            case "LUT_3D_SIZE":
                size3 = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
            case "LUT_1D_SIZE":
                size1 = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
            case "DOMAIN_MIN":
                if let v = Self.triple(parts.dropFirst()) { dmin = v }
            case "DOMAIN_MAX":
                if let v = Self.triple(parts.dropFirst()) { dmax = v }
            case "LUT_3D_INPUT_RANGE", "LUT_1D_INPUT_RANGE":
                if parts.count >= 3, let lo = Float(parts[1]), let hi = Float(parts[2]) {
                    dmin = SIMD3(repeating: lo); dmax = SIMD3(repeating: hi)
                }
            default:
                guard let v = Self.triple(parts[...]) else {
                    if head.first?.isLetter == true { continue }   // unknown keyword
                    throw ParseError.badData(lineNumber)
                }
                values.append(v)
            }
        }
        if size3 > 0 {
            guard (2...256).contains(size3) else { throw ParseError.badSize }
            guard values.count >= size3 * size3 * size3 else { throw ParseError.badData(lineNumber) }
            self.size = size3; self.is3D = true
            self.values = Array(values.prefix(size3 * size3 * size3))
        } else if size1 > 0 {
            guard (2...65536).contains(size1) else { throw ParseError.badSize }
            guard values.count >= size1 else { throw ParseError.badData(lineNumber) }
            self.size = size1; self.is3D = false
            self.values = Array(values.prefix(size1))
        } else {
            throw ParseError.notACube
        }
        self.title = title
        self.domainMin = dmin
        self.domainMax = dmax
    }

    private static func triple<S: Sequence>(_ parts: S) -> SIMD3<Float>? where S.Element == Substring {
        let nums = parts.prefix(3).compactMap { Float($0) }
        return nums.count == 3 ? SIMD3(nums[0], nums[1], nums[2]) : nil
    }

    /// Looks up one colour (trilinear for 3D, linear per channel for 1D).
    func apply(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        let range = domainMax - domainMin
        var t = (rgb - domainMin) / SIMD3(max(range.x, 1e-6), max(range.y, 1e-6), max(range.z, 1e-6))
        t = simd_clamp(t, .zero, .one)
        let n = Float(size - 1)
        if !is3D {
            func channel(_ x: Float, _ c: Int) -> Float {
                let p = x * n, i = min(Int(p), size - 2), f = p - Float(i)
                return values[i][c] * (1 - f) + values[i + 1][c] * f
            }
            return SIMD3(channel(t.x, 0), channel(t.y, 1), channel(t.z, 2))
        }
        let p = t * n
        let i0 = SIMD3<Int>(min(Int(p.x), size - 2), min(Int(p.y), size - 2), min(Int(p.z), size - 2))
        let f = p - SIMD3<Float>(Float(i0.x), Float(i0.y), Float(i0.z))
        func v(_ r: Int, _ g: Int, _ b: Int) -> SIMD3<Float> { values[r + g * size + b * size * size] }
        let c00 = v(i0.x, i0.y, i0.z) * (1 - f.x) + v(i0.x + 1, i0.y, i0.z) * f.x
        let c10 = v(i0.x, i0.y + 1, i0.z) * (1 - f.x) + v(i0.x + 1, i0.y + 1, i0.z) * f.x
        let c01 = v(i0.x, i0.y, i0.z + 1) * (1 - f.x) + v(i0.x + 1, i0.y, i0.z + 1) * f.x
        let c11 = v(i0.x, i0.y + 1, i0.z + 1) * (1 - f.x) + v(i0.x + 1, i0.y + 1, i0.z + 1) * f.x
        let c0 = c00 * (1 - f.y) + c10 * f.y
        let c1 = c01 * (1 - f.y) + c11 * f.y
        return c0 * (1 - f.z) + c1 * f.z
    }

    /// A Core Image colour cube of `dimension` points per side (resampled, max 64).
    func colorCubeData(dimension: Int? = nil) -> (data: Data, dimension: Int) {
        let d = dimension ?? (is3D ? min(size, 64) : 33)
        var floats: [Float] = []
        floats.reserveCapacity(d * d * d * 4)
        let n = Float(d - 1)
        let range = domainMax - domainMin
        for b in 0..<d {
            for g in 0..<d {
                for r in 0..<d {
                    let input = domainMin + SIMD3(Float(r) / n, Float(g) / n, Float(b) / n) * range
                    let out = (is3D && d == size) ? values[r + g * size + b * size * size] : apply(input)
                    floats += [out.x, out.y, out.z, 1]
                }
            }
        }
        return (floats.withUnsafeBufferPointer { Data(buffer: $0) }, d)
    }
}
