import SwiftUI
import Cocoa

public enum TyperTheme {
    // MARK: - Colors matching the reference design (Lightened, airy & refined)
    public static let windowBg = Color(nsColor: NSColor(calibratedRed: 0.980, green: 0.982, blue: 0.986, alpha: 1.0)) // Crisp bright porcelain
    public static let cardBg = Color.white
    public static let itemBg = Color(nsColor: NSColor(calibratedRed: 0.958, green: 0.962, blue: 0.967, alpha: 1.0)) // Airy light pill/item
    public static let itemBgHover = Color(nsColor: NSColor(calibratedRed: 0.940, green: 0.945, blue: 0.952, alpha: 1.0))

    // High-end Deep Slate Indigo Navy (from the reference image's active cards like 'Iowan' and 'Default')
    public static let activeBorder = Color(red: 0.16, green: 0.26, blue: 0.38)
    public static let activeNavyButton = Color(red: 0.15, green: 0.24, blue: 0.35)
    public static let activeNavyPill = Color(red: 0.16, green: 0.26, blue: 0.38)

    // Border strokes
    public static let borderFaint = Color.black.opacity(0.04)
    public static let borderSubtle = Color.black.opacity(0.06)

    // Typography
    public static let textPrimary = Color(red: 0.11, green: 0.12, blue: 0.15) // Deep charcoal #1C1E26
    public static let textSecondary = Color(red: 0.47, green: 0.50, blue: 0.56) // Muted slate #78808F
    public static let textTertiary = Color(red: 0.62, green: 0.65, blue: 0.70) // Soft caption #9EA6B3

    // Radii
    public static let radiusCard: CGFloat = 20
    public static let radiusItem: CGFloat = 13
    public static let radiusPill: CGFloat = 9
}

public struct FloatingCardModifier: ViewModifier {
    var cornerRadius: CGFloat = TyperTheme.radiusCard
    var padding: CGFloat = 16

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(TyperTheme.cardBg)
                    .shadow(color: Color.black.opacity(0.035), radius: 12, x: 0, y: 5)
                    .shadow(color: Color.black.opacity(0.015), radius: 2, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(TyperTheme.borderFaint, lineWidth: 1)
            )
    }
}

public extension View {
    func floatingCard(cornerRadius: CGFloat = TyperTheme.radiusCard, padding: CGFloat = 16) -> some View {
        self.modifier(FloatingCardModifier(cornerRadius: cornerRadius, padding: padding))
    }
}

public extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        if Scanner(string: clean).scanHexInt64(&int) {
            let r, g, b: UInt64
            switch clean.count {
            case 3:
                (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
                self.init(.sRGB, red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0, opacity: 1.0)
                return
            case 6:
                (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
                self.init(.sRGB, red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0, opacity: 1.0)
                return
            default:
                break
            }
        }
        self.init(.sRGB, red: 38.0 / 255.0, green: 61.0 / 255.0, blue: 89.0 / 255.0, opacity: 1.0)
    }
}

public extension NSColor {
    var hexString: String {
        guard let srgb = usingColorSpace(.sRGB) else { return "#263D59" }
        let r = Int(round(srgb.redComponent * 255))
        let g = Int(round(srgb.greenComponent * 255))
        let b = Int(round(srgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
    }
}

