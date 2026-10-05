import AppKit
import SwiftUI

/// Colours, font and controls of the 16-bit modal (values from the approved browser preview).
enum RetroTheme {
    /// Fixed outer sizes of the modal panels (incl. the 12 pt pixel border), centred on the screen.
    static let panelWidth: CGFloat = 960
    static let primaryHeight: CGFloat = 440
    static let rowHeight: CGFloat = 80
    /// The primary panel grows by this much during the game, for the meeting buttons under the controls.
    static let gameButtonsHeight: CGFloat = 60
    /// Integer scale of the 100 × 92 px scene (4 → 400 × 368 pt).
    static let sceneScale = 4

    // Spacing (tokens from design/prototype, 2026-10-02)
    static let panelPadding: CGFloat = 24
    static let sceneInfoGap: CGFloat = 28
    static let stackSpacing: CGFloat = 12
    static let rowPaddingX: CGFloat = 16
    static let buttonPaddingX: CGFloat = 20
    static let buttonPaddingY: CGFloat = 10
    static let buttonShade: CGFloat = 4
    static let buttonGap: CGFloat = 12
    /// Black dim over the whole screen behind the panels.
    static let screenDim: CGFloat = 0.45

    // Type sizes (pt, before the per-font scale)
    static let titleSize: CGFloat = 40
    static let countdownSize: CGFloat = 20
    static let buttonSize: CGFloat = 16
    static let metaSize: CGFloat = 16
    static let rowTitleSize: CGFloat = 16
    static let rowLabelSize: CGFloat = 14
    static let rowMetaSize: CGFloat = 13

    static let panel = Color(hex: 0x1B1A2E)
    static let ink = Color(hex: 0x0F0E17)
    static let gold = Color(hex: 0xF4B942)
    static let goldDark = Color(hex: 0xB8860B)
    static let button = Color(hex: 0x2E2C4A)
    static let buttonDark = Color(hex: 0x15142A)
    static let text = Color(hex: 0xFFFFFE)
    static let muted = Color(hex: 0xA7A9BE)

    /// Silkscreen is bundled in Contents/Resources/Fonts (ATSApplicationFontsPath) when available;
    /// `swift run` or a build without the font falls back to SF Mono. Each font has its own optical scale
    /// so the token sizes look the same as in the browser tuner.
    static let pixelFamily = "Silkscreen"
    static let pixelFontScale: CGFloat = 0.8
    static let fallbackFontScale: CGFloat = 0.9
    static let hasPixelFont = NSFontManager.shared.availableFontFamilies.contains(pixelFamily)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

extension Font {
    static func pixel(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        RetroTheme.hasPixelFont
            ? .custom(RetroTheme.pixelFamily, size: size * RetroTheme.pixelFontScale).weight(weight)
            : .system(size: size * RetroTheme.fallbackFontScale, weight: weight, design: .monospaced)
    }
}

/// Square panel with the double pixel border (ink / gold / ink).
struct PixelPanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(RetroTheme.panel)
            .padding(4).background(RetroTheme.ink)
            .padding(4).background(RetroTheme.gold)
            .padding(4).background(RetroTheme.ink)
    }
}

extension View {
    func pixelPanel() -> some View { modifier(PixelPanel()) }
}

/// Blocky 8/16-bit button: flat fill, 3 px inset shadow bottom-right, 2 px ink outline; sinks 1 px when pressed.
struct PixelButtonStyle: ButtonStyle {
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        let fill = primary ? RetroTheme.gold : RetroTheme.button
        let shade = primary ? RetroTheme.goldDark : RetroTheme.buttonDark
        configuration.label
            .font(.pixel(RetroTheme.buttonSize, weight: .semibold))
            .foregroundStyle(primary ? RetroTheme.ink : RetroTheme.text)
            .padding(.horizontal, RetroTheme.buttonPaddingX).padding(.vertical, RetroTheme.buttonPaddingY)
            .background(fill)
            .overlay(alignment: .bottom) { shade.frame(height: RetroTheme.buttonShade) }
            .overlay(alignment: .trailing) { shade.frame(width: RetroTheme.buttonShade) }
            .padding(2).background(RetroTheme.ink)
            .offset(y: configuration.isPressed ? 1 : 0)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .contentShape(Rectangle())
    }
}
