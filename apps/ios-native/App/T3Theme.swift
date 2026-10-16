import SwiftUI

// DM Sans files and scale match apps/mobile/src/lib/typography.ts.
enum T3Font {
    enum Weight { case regular, medium, bold }
    static func name(_ weight: Weight) -> String {
        switch weight { case .regular: "DMSans-Regular"; case .medium: "DMSans-Medium"; case .bold: "DMSans-Bold" }
    }
    static func scaled(_ size: Double, weight: Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font { .custom(name(weight), size: size, relativeTo: style) }
    static func fixed(_ size: Double, weight: Weight = .regular) -> Font { .custom(name(weight), fixedSize: size) }
    static var body: Font { scaled(16) }
    static var subheadline: Font { scaled(14, relativeTo: .subheadline) }
    static var caption: Font { scaled(12, relativeTo: .caption) }
    static var headline: Font { scaled(18, weight: .medium, relativeTo: .headline) }
    static var title: Font { scaled(21, weight: .bold, relativeTo: .title3) }
}

struct T3Palette {
    let id: String
    // Generated from packages/shared/src/themePalettes.ts, retaining role names.
    private static let themes: [String: [String: [String: String]]] = {
        guard let url = Bundle.main.url(forResource: "ThemeColors", withExtension: "json"), let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([String: [String: [String: String]]].self, from: data) else { return [:] }
        return values
    }()
    func color(_ role: String) -> Color {
        let variants = Self.themes[id] ?? Self.themes["t3-code"] ?? [:]
        let light = Self.uiColor(variants["light"]?[role] ?? "#27272a")
        let dark = Self.uiColor(variants["dark"]?[role] ?? "#f5f5f5")
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    private static func uiColor(_ hex: String) -> UIColor {
        let n = UInt64(hex.dropFirst(), radix: 16) ?? 0
        return UIColor(red: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255, blue: Double(n & 255) / 255, alpha: 1)
    }
    var canvas: Color { color("canvas") }
    var surface: Color { color("surface") }
    var text: Color { color("text") }
    var muted: Color { color("textMuted") }
    var border: Color { color("border") }
    var accent: Color { color("accent") }
}
private struct T3PaletteKey: EnvironmentKey { static let defaultValue = T3Palette(id: "t3-code") }
extension EnvironmentValues { var t3Theme: T3Palette { get { self[T3PaletteKey.self] } set { self[T3PaletteKey.self] = newValue } } }
