#if canImport(CoreGraphics)
import CoreGraphics
import Foundation

extension PixelCanvas {
    /// Wraps the canvas in a CGImage (straight alpha). Draw it with interpolation `.none` to keep pixels crisp.
    public func cgImage() -> CGImage? {
        let data = rgbaBytes()
        guard let provider = CGDataProvider(data: Data(data) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
#endif
