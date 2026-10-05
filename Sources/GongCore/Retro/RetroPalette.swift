import Foundation

/// Colours of the retro scene. Ramps are `[outline, shadow, base, highlight]` (see `AutoShader`).
public enum RetroPalette {
    private static func ramp(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32) -> [RGBA] {
        [RGBA(hex: a), RGBA(hex: b), RGBA(hex: c), RGBA(hex: d)]
    }

    public static let suit = ramp(0x0E0A1F, 0x211A42, 0x33296A, 0x5C4FA8)
    public static let skin = ramp(0x6E3F2A, 0xC08159, 0xF0C49A, 0xFFE4C6)
    public static let headband = ramp(0x4F0D16, 0x9E2230, 0xE23A48, 0xFF8A92)
    public static let band = ramp(0x15152A, 0x36365A, 0x585887, 0x8D8DC0)
    public static let wood = ramp(0x3A2210, 0x6B4226, 0x93602F, 0xC08850)
    public static let felt = ramp(0x4F0D16, 0x9E2230, 0xC9363F, 0xEF7468)

    /// Material letters used in `NinjaSprites`.
    public static let ninjaRamps: [Character: [RGBA]] = ["s": suit, "k": skin, "r": headband, "b": band, "w": band]
    public static let ninjaFixed: [Character: RGBA] = ["W": .white, "P": RGBA(hex: 0x0E0A1F)]

    /// Gong brass, dark → bright.
    public static let brass = [0x3D2405, 0x7A5208, 0xB8860B, 0xF4B942, 0xFFE28A, 0xFFF6D0].map { RGBA(hex: $0) }
    public static let standWood = RGBA(hex: 0x6B4226)
    public static let standWoodDark = RGBA(hex: 0x3A2210)
    public static let standWoodLight = RGBA(hex: 0x93602F)
    public static let rope = RGBA(hex: 0x2A1A10)

    public static let sky = [0x3D2F78, 0x55398A, 0x7A4193, 0xA24D92, 0xCC5F83, 0xE67A6C, 0xF39A62, 0xF7BC6A].map { RGBA(hex: $0) }
    public static let starDim = RGBA(hex: 0x8B7FD0)
    public static let moon = RGBA(hex: 0xFFF4D6)
    public static let moonShade = RGBA(hex: 0xE8D6AE)
    public static let hillFar = RGBA(hex: 0x8A4A78)
    public static let hillNear = RGBA(hex: 0x6A3462)
    public static let floorTop = RGBA(hex: 0xE0A564)
    public static let floorEdge = RGBA(hex: 0xC98A4B)
    public static let floorPlank = RGBA(hex: 0x8B5A2B)
    public static let floorBottom = RGBA(hex: 0x4A2C17)
    public static let floorSeam = RGBA(hex: 0x5A3519)
    public static let floorKnot = RGBA(hex: 0x6B4226)
    public static let petal = RGBA(hex: 0xFFB7C5)
    public static let petalDark = RGBA(hex: 0xFF8FAB)

    /// Effects: shock rings, speed lines, "GONG!" text.
    public static let light = RGBA(hex: 0xFFF4D6)
    public static let gold = RGBA(hex: 0xFFE28A)
    public static let ink = RGBA(hex: 0x2A1A10)

    /// Game: shuriken steel and HUD hearts.
    public static let steel = RGBA(hex: 0xC9CCD6)
    public static let steelDark = RGBA(hex: 0x4A4E63)
    public static let heart = RGBA(hex: 0xE23A48)
    public static let heartEmpty = RGBA(hex: 0x36365A)
}
