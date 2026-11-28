import SwiftUI

/// Dashboard theme — mirrors `settings.js` customization (3-color gradient).
/// Fetched from GET /api/settings/customization and applied to native tabs.
struct AppTheme {
    var accent = Color.cyan
    var accent2 = Color.cyan
    var accent3 = Color.cyan
    var solid = Color(red: 0.04, green: 0.04, blue: 0.07)
    var isGradient = true
    var gradientStyle = "linear" // "linear" | "radial"
    var orientation = "135deg"

    static let fallback = AppTheme()

    init() {}

    init(settings: [String: Any]) {
        isGradient = J.str(settings, "background_type") != "solid"
        gradientStyle = J.str(settings, "background_gradient_style") == "radial" ? "radial" : "linear"
        let o = J.str(settings, "background_gradient_orientation")
        orientation = o.isEmpty ? "135deg" : o
        if let c = Self.hex(J.str(settings, "background_solid_color")) { solid = c }
        if let c = Self.hex(J.str(settings, "background_color_1")) { accent = c }
        if let c = Self.hex(J.str(settings, "background_color_2")) { accent2 = c }
        if let c = Self.hex(J.str(settings, "background_color_3")) { accent3 = c }
    }

    static func hex(_ s: String) -> Color? {
        var h = s.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt64(h, radix: 16) else { return nil }
        return Color(red: Double((v >> 16) & 0xff) / 255,
                     green: Double((v >> 8) & 0xff) / 255,
                     blue: Double(v & 0xff) / 255)
    }

    /// Gradient stops match the website: c1 0% → c3 50% → c2 100%.
    private var stops: [Gradient.Stop] {
        [Gradient.Stop(color: accent, location: 0),
         Gradient.Stop(color: accent3, location: 0.5),
         Gradient.Stop(color: accent2, location: 1)]
    }

    /// UnitPoints for the CSS angle (0deg = vers le haut, sens horaire).
    private var points: (UnitPoint, UnitPoint) {
        let deg = Double(orientation.replacingOccurrences(of: "deg", with: "")) ?? 135
        let rad = deg * .pi / 180
        let dx = sin(rad), dy = -cos(rad) // écran : y vers le bas
        return (UnitPoint(x: 0.5 - CGFloat(dx) / 2, y: 0.5 - CGFloat(dy) / 2),
                UnitPoint(x: 0.5 + CGFloat(dx) / 2, y: 0.5 + CGFloat(dy) / 2))
    }

    /// Full-bleed background matching the website theme.
    @ViewBuilder var background: some View {
        if isGradient {
            let (start, end) = points
            if gradientStyle == "radial" {
                RadialGradient(stops: stops, center: .center, startRadius: 0, endRadius: 400)
            } else {
                LinearGradient(stops: stops, startPoint: start, endPoint: end)
            }
        } else {
            solid
        }
    }
}
