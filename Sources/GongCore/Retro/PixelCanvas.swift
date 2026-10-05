import Foundation

/// A small RGBA framebuffer with the drawing primitives the retro scene needs.
/// Coordinates are rounded to the nearest pixel; drawing outside the canvas is a no-op.
public struct PixelCanvas: Equatable {
    public let width: Int
    public let height: Int
    public private(set) var pixels: [RGBA]

    public init(width: Int, height: Int, fill: RGBA = .clear) {
        self.width = width
        self.height = height
        pixels = Array(repeating: fill, count: width * height)
    }

    public subscript(x: Int, y: Int) -> RGBA {
        guard x >= 0, y >= 0, x < width, y < height else { return .clear }
        return pixels[y * width + x]
    }

    public mutating func set(_ x: Int, _ y: Int, _ color: RGBA, alpha: Double = 1) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let a = alpha * Double(color.a) / 255
        if a >= 1 { pixels[y * width + x] = color; return }
        if a <= 0 { return }
        let dst = pixels[y * width + x]
        let da = Double(dst.a) / 255
        let outA = a + da * (1 - a)
        func mix(_ s: UInt8, _ d: UInt8) -> UInt8 {
            UInt8(((Double(s) * a + Double(d) * da * (1 - a)) / outA).rounded())
        }
        pixels[y * width + x] = RGBA(r: mix(color.r, dst.r), g: mix(color.g, dst.g), b: mix(color.b, dst.b),
                                     a: UInt8((outA * 255).rounded()))
    }

    public mutating func set(_ x: Double, _ y: Double, _ color: RGBA, alpha: Double = 1) {
        guard x.isFinite, y.isFinite else { return }
        set(Int(x.rounded()), Int(y.rounded()), color, alpha: alpha)
    }

    public mutating func fillRect(x: Int, y: Int, w: Int, h: Int, _ color: RGBA, alpha: Double = 1) {
        guard w > 0, h > 0 else { return }
        for yy in y..<(y + h) { for xx in x..<(x + w) { set(xx, yy, color, alpha: alpha) } }
    }

    /// Straight line from (x0,y0) to (x1,y1) stamped with a `thickness`×`thickness` square per step.
    public mutating func line(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ color: RGBA,
                              thickness: Int = 1, alpha: Double = 1) {
        let n = max(1, Int(max(abs(x1 - x0), abs(y1 - y0))))
        let half = Double(thickness - 1) / 2
        for i in 0...n {
            let t = Double(i) / Double(n)
            let x = x0 + (x1 - x0) * t, y = y0 + (y1 - y0) * t
            fillRect(x: Int((x - half).rounded()), y: Int((y - half).rounded()), w: thickness, h: thickness, color, alpha: alpha)
        }
    }

    /// Composites `other` with its top-left at (x, y).
    public mutating func draw(_ other: PixelCanvas, x: Int, y: Int, alpha: Double = 1) {
        for yy in 0..<other.height {
            for xx in 0..<other.width {
                let c = other.pixels[yy * other.width + xx]
                if c.a > 0 { set(x + xx, y + yy, c, alpha: alpha) }
            }
        }
    }

    /// Whole-canvas offset (camera shake); vacated pixels repeat the nearest edge.
    public func shifted(dx: Int, dy: Int) -> PixelCanvas {
        var out = PixelCanvas(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                let sx = min(max(x - dx, 0), width - 1), sy = min(max(y - dy, 0), height - 1)
                out.pixels[y * width + x] = pixels[sy * width + sx]
            }
        }
        return out
    }

    /// Scales so the width becomes `newWidth`: nearest-neighbour when growing, box average when shrinking.
    /// Only integer factors are supported (e.g. 64 → 16, 32, 128 … 1024).
    public func scaled(to newWidth: Int) -> PixelCanvas {
        if newWidth >= width {
            let f = max(1, newWidth / width)
            var out = PixelCanvas(width: width * f, height: height * f)
            for y in 0..<out.height { for x in 0..<out.width { out.pixels[y * out.width + x] = self[x / f, y / f] } }
            return out
        }
        let f = max(1, width / max(1, newWidth))
        var out = PixelCanvas(width: width / f, height: height / f)
        for y in 0..<out.height {
            for x in 0..<out.width {
                var r = 0.0, g = 0.0, b = 0.0, a = 0.0
                for yy in 0..<f {
                    for xx in 0..<f {
                        let c = self[x * f + xx, y * f + yy]
                        let ca = Double(c.a) / 255
                        r += Double(c.r) * ca; g += Double(c.g) * ca; b += Double(c.b) * ca; a += ca
                    }
                }
                let n = Double(f * f)
                guard a > 0 else { continue }
                out.pixels[y * out.width + x] = RGBA(r: UInt8((r / a).rounded()), g: UInt8((g / a).rounded()),
                                                     b: UInt8((b / a).rounded()), a: UInt8((a / n * 255).rounded()))
            }
        }
        return out
    }

    /// Exact pixel rotation clockwise by `quarterTurns` × 90° (negative = counter-clockwise).
    public func rotated(quarterTurns: Int) -> PixelCanvas {
        let q = ((quarterTurns % 4) + 4) % 4
        guard q != 0 else { return self }
        let ow = q == 2 ? width : height, oh = q == 2 ? height : width
        var out = PixelCanvas(width: ow, height: oh)
        for y in 0..<height {
            for x in 0..<width {
                let (nx, ny): (Int, Int)
                switch q {
                case 1: (nx, ny) = (height - 1 - y, x)
                case 2: (nx, ny) = (width - 1 - x, height - 1 - y)
                default: (nx, ny) = (y, width - 1 - x)
                }
                out.pixels[ny * ow + nx] = pixels[y * width + x]
            }
        }
        return out
    }

    /// The left `width` columns (the scene is the left part of the game world).
    public func cropped(width w: Int) -> PixelCanvas {
        let w = min(max(1, w), width)
        var out = PixelCanvas(width: w, height: height)
        for y in 0..<height { for x in 0..<w { out.pixels[y * w + x] = pixels[y * width + x] } }
        return out
    }

    /// Bottom-most row that contains a non-transparent pixel.
    public var lowestOpaqueRow: Int? {
        for y in stride(from: height - 1, through: 0, by: -1) where (0..<width).contains(where: { pixels[y * width + $0].a > 0 }) {
            return y
        }
        return nil
    }

    /// Straight-alpha RGBA bytes, row-major from the top-left.
    public func rgbaBytes() -> [UInt8] {
        var out = [UInt8](); out.reserveCapacity(pixels.count * 4)
        for p in pixels { out.append(p.r); out.append(p.g); out.append(p.b); out.append(p.a) }
        return out
    }
}
