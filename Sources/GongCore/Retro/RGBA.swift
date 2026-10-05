import Foundation

/// 8-bit straight-alpha colour used by the pixel renderer.
public struct RGBA: Equatable, Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// `RGBA(hex: 0x3D2F78)` — opaque.
    public init(hex: UInt32) {
        self.init(r: UInt8((hex >> 16) & 0xFF), g: UInt8((hex >> 8) & 0xFF), b: UInt8(hex & 0xFF))
    }

    public static let clear = RGBA(r: 0, g: 0, b: 0, a: 0)
    public static let white = RGBA(hex: 0xFFFFFF)
}
