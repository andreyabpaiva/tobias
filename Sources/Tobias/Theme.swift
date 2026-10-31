import AppKit
import SwiftUI

/// Design tokens from the "Pixel Concept" design: warm paper, ink outlines, one green accent.
/// Views only read from here.
enum Theme {
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 14
        static let large: CGFloat = 20
    }

    enum Palette {
        static let accent = Color(light: 0x3E8E5A, dark: 0x5DB57D)
        static let accentText = Color(light: 0x2F6E45, dark: 0x7CC796)
        static let accentTint = Color(light: 0xE3F0E6, dark: 0x22382A)
        static let accentStripe = Color(light: 0xDCEBDF, dark: 0x2A4433)
        static let selectedRow = Color(light: 0xF2F7F3, dark: 0x26302A)
        static let selectedShadow = Color(light: 0xCFE2D4, dark: 0x1A2A1F)

        static let ground = Color(light: 0xF6F5F1, dark: 0x1F1F1D)
        static let chrome = Color(light: 0xEFEDE8, dark: 0x262624)
        static let paper = Color(light: 0xFBFAF7, dark: 0x2A2A27)
        static let surface = Color(light: 0xFFFFFF, dark: 0x30302D)
        static let ink = Color(light: 0x2B2B29, dark: 0xF0EFEA)
        static let line = Color(light: 0x3A3936, dark: 0xA9A79F)
        static let secondaryText = Color(light: 0x5E5D58, dark: 0xB4B2AA)
        static let tertiaryText = Color(light: 0x6B6A65, dark: 0x9C9A92)
        static let shadow = Color(light: 0xD9D7D0, dark: 0x141413)
        static let shadowSoft = Color(light: 0xE6E4DE, dark: 0x181816)
        static let dash = Color(light: 0xCFCDC6, dark: 0x4A4945)

        static let barFill = Color(light: 0x8E8C85, dark: 0x8E8C85)
        static let barTrack = paper
        static let used = Color(light: 0xCFCDC6, dark: 0x55534E)
        static let neutralBadge = Color(light: 0xECEAE4, dark: 0x3A3936)

        static let warning = Color(light: 0x9A5A16, dark: 0xE0A060)
        static let warningText = Color(light: 0x7A4810, dark: 0xE8B27A)
        static let warningTint = Color(light: 0xF3E6D4, dark: 0x3D2F1E)
        static let note = Color(light: 0xF5EDC9, dark: 0x3F3923)
        static let noteText = Color(light: 0x4A4945, dark: 0xD6D3C8)

        static let destructive = Color(light: 0xB3261E, dark: 0xE5675E)
        static let destructiveBorder = Color(light: 0x7E1A14, dark: 0xB3261E)
        static let destructiveText = Color(light: 0x8E1D17, dark: 0xF08A82)
        static let success = accentText
    }

    enum Typography {
        /// Patrick Hand, bundled with the app. Falls back to the closest handwriting face macOS ships.
        static let handFamily: String = {
            BundledFonts.register()
            return ["Patrick Hand", "Noteworthy", "Chalkboard SE"]
                .first { NSFontManager.shared.availableMembers(ofFontFamily: $0) != nil }
                ?? "Noteworthy"
        }()

        static func hand(_ size: CGFloat) -> Font { .custom(handFamily, fixedSize: size) }
        static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }

        static let title = hand(32)
        static let figure = hand(44)
        static let sectionTitle = hand(20)
        static let rowTitle = hand(20)
        static let body = hand(17)
        static let caption = hand(16)
        static let button = hand(19)
        static let badge = hand(15)
        static let rowSize = mono(14)
        static let monoCaption = mono(12)
    }
}

/// Fonts shipped in the app's resource bundle, registered for this process only.
enum BundledFonts {
    static func register() {
        guard let folder = fontsFolder(),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return }
        for url in files where url.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// Same lookup as the catalog: `Bundle.module` looks next to the .app, so check Contents/Resources first.
    private static func fontsFolder() -> URL? {
        if let resources = Bundle.main.resourceURL,
           let bundle = Bundle(url: resources.appendingPathComponent("tobias_Tobias.bundle")),
           let url = bundle.url(forResource: "Fonts", withExtension: nil) {
            return url
        }
        return Bundle.module.url(forResource: "Fonts", withExtension: nil)
    }
}

extension Color {
    /// A color that follows the window's light or dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
