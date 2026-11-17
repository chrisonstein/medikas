import SwiftUI
import AppKit
import CoreText

// MARK: - Huisstijl voor de factuur (instelbaar; opgeslagen in data.json)

struct InvoiceStyle: Codable, Equatable {
    enum Layout: String, Codable, CaseIterable, Identifiable {
        case klassiek, modern
        var id: Self { self }
        var label: String { self == .klassiek ? "Klassiek" : "Modern" }
    }
    enum Pattern: String, Codable, CaseIterable, Identifiable {
        case geen, logo, afbeelding
        var id: Self { self }
        var label: String { switch self { case .geen: "Geen"; case .logo: "Logo herhalen"; case .afbeelding: "Eigen afbeelding" } }
    }

    var layout: Layout = .klassiek
    /// Kleuren als hex (zonder #)
    var textHex = "1F2328"
    var primaryHex = "1A7378"
    var secondaryHex = "1A7378"
    var surfaceHex = "EEF4F4"
    /// Lettertypefamilies; leeg = systeemlettertype
    var headingFont = ""
    var bodyFont = ""
    var gradientLines = true
    var titleUppercase = true
    var logoHeight: Double = 56
    var pattern: Pattern = .geen
    var patternOpacity: Double = 0.25
    var patternHeight: Double = 34

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = InvoiceStyle()
        layout = c.value(.layout, d.layout)
        textHex = c.value(.textHex, d.textHex)
        primaryHex = c.value(.primaryHex, d.primaryHex)
        secondaryHex = c.value(.secondaryHex, d.secondaryHex)
        surfaceHex = c.value(.surfaceHex, d.surfaceHex)
        headingFont = c.value(.headingFont, d.headingFont)
        bodyFont = c.value(.bodyFont, d.bodyFont)
        gradientLines = c.value(.gradientLines, d.gradientLines)
        titleUppercase = c.value(.titleUppercase, d.titleUppercase)
        logoHeight = c.value(.logoHeight, d.logoHeight)
        pattern = c.value(.pattern, d.pattern)
        patternOpacity = c.value(.patternOpacity, d.patternOpacity)
        patternHeight = c.value(.patternHeight, d.patternHeight)
    }
}

/// Uitgewerkte huisstijl voor het tekenen van de PDF.
struct Brand {
    let style: InvoiceStyle
    let logo: NSImage?
    let patternImage: NSImage?

    var text: Color { Color(hex: style.textHex) ?? Color(white: 0.12) }
    var soft: Color { text.opacity(0.62) }
    var rule: Color { text.opacity(0.14) }
    var primary: Color { Color(hex: style.primaryHex) ?? invoiceAccent }
    var secondary: Color { Color(hex: style.secondaryHex) ?? primary }
    var surface: Color { Color(hex: style.surfaceHex) ?? Color(white: 0.96) }
    var line: LinearGradient {
        LinearGradient(colors: style.gradientLines ? [primary, secondary] : [primary, primary], startPoint: .leading, endPoint: .trailing)
    }
    var isModern: Bool { style.layout == .modern }

    /// Afbeelding voor het patroon onderaan (nil = geen patroon).
    var patternTile: NSImage? {
        switch style.pattern {
        case .geen: nil
        case .logo: logo
        case .afbeelding: patternImage ?? logo
        }
    }
    var patternSpace: CGFloat { patternTile == nil ? 0 : CGFloat(style.patternHeight) + 6 }

    func heading(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font { Brand.font(style.headingFont, size, weight) }
    func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { Brand.font(style.bodyFont, size, weight) }

    static func font(_ family: String, _ size: CGFloat, _ weight: Font.Weight) -> Font {
        family.isEmpty ? .system(size: size, weight: weight) : .custom(family, size: size).weight(weight)
    }
}

// MARK: - Kleuren

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    /// Hex (zonder #) van deze kleur in sRGB.
    var hex: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "000000" }
        return String(format: "%02X%02X%02X", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}

enum LogoColors {
    /// Haalt de huisstijlkleuren uit een logo: de twee meest voorkomende verzadigde tinten,
    /// de donkerste kleur als tekstkleur, en een heel lichte tint van de hoofdkleur voor vlakken.
    static func extract(from image: NSImage) -> (text: String?, primary: String, secondary: String, surface: String)? {
        let side = 48
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()

        var buckets: [Int: [(CGFloat, CGFloat, CGFloat)]] = [:]
        var darkest: (CGFloat, NSColor)?
        for x in 0..<side { for y in 0..<side {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.alphaComponent > 0.6 else { continue }
            let (h, s, b) = (c.hueComponent, c.saturationComponent, c.brightnessComponent)
            if b < 0.35, darkest == nil || b < darkest!.0 { darkest = (b, c) }
            guard s > 0.35, b > 0.3 else { continue }
            buckets[Int(h * 18) % 18, default: []].append((c.redComponent, c.greenComponent, c.blueComponent))
        }}
        let top = buckets.sorted { $0.value.count > $1.value.count }.prefix(2).map { px -> NSColor in
            let n = CGFloat(px.value.count)
            return NSColor(srgbRed: px.value.map(\.0).reduce(0, +) / n, green: px.value.map(\.1).reduce(0, +) / n,
                           blue: px.value.map(\.2).reduce(0, +) / n, alpha: 1)
        }
        guard let first = top.first else { return nil }
        let second = top.count > 1 ? top[1] : first
        let surface = first.blended(withFraction: 0.92, of: .white) ?? .white
        return (darkest.map { Color(nsColor: $0.1).hex }, Color(nsColor: first).hex, Color(nsColor: second).hex, Color(nsColor: surface).hex)
    }
}

// MARK: - Lettertypen

enum BrandFonts {
    /// Lettertypen die macOS standaard heeft en goed werken op een factuur.
    static let builtIn = ["Helvetica Neue", "Avenir Next", "Gill Sans", "Futura", "Optima", "Georgia", "Palatino", "Baskerville"]

    /// Registreert eigen lettertypebestanden (alleen voor deze app, niet systeembreed).
    static func register(_ urls: [URL]) {
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// Familienamen in een lettertypebestand.
    static func families(in url: URL) -> [String] {
        guard let descs = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else { return [] }
        return Array(Set(descs.compactMap { CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String })).sorted()
    }
}
