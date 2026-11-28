import SwiftUI

/// Theme mirrored from the web dashboard customization
/// (GET /api/settings/customization → background_* fields).
/// Same gradient stops as the website: c1 0% → c3 50% → c2 100%.
struct AppTheme {
    var accent = Color.cyan
    var accentStrong = Color.blue
    var fontWeightName = "500"
    var fontSize: CGFloat = 16

    private var c1 = Color(red: 0.043, green: 0.247, blue: 0.569)   // #0b3f91
    private var c2 = Color(red: 0.110, green: 0.549, blue: 1.0)     // #1c8cff
    private var c3 = Color(red: 0.545, green: 0.361, blue: 0.965)   // #8b5cf6
    private var solidColor: Color?
    private var gradientStyle = "linear"
    private var gradientOrientation = "135deg"

    static let fallback = AppTheme()

    init() {}

    init(settings: [String: Any]) {
        if let c = Self.hex(J.str(settings, "background_color_1")) { accent = c; c1 = c }
        if let c = Self.hex(J.str(settings, "background_color_2")) { accentStrong = c; c2 = c }
        if let c = Self.hex(J.str(settings, "background_color_3")) { c3 = c }
        if J.str(settings, "background_type") == "solid",
           let c = Self.hex(J.str(settings, "background_solid_color")) {
            solidColor = c
        }
        let style = J.str(settings, "background_gradient_style")
        if style == "radial" || style == "linear" { gradientStyle = style }
        let orient = J.str(settings, "background_gradient_orientation")
        if !orient.isEmpty { gradientOrientation = orient }
        fontWeightName = J.str(settings, "background_font_weight")
        let rawSize = settings["background_font_size"]
        let size = (rawSize as? Double) ?? (rawSize as? Int).map(Double.init) ?? (rawSize as? String).flatMap(Double.init) ?? 0
        if size >= 14 && size <= 28 { fontSize = CGFloat(size) }
    }

    static func hex(_ s: String) -> Color? {
        var h = s.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt64(h, radix: 16) else { return nil }
        return Color(red: Double((v >> 16) & 0xff) / 255,
                     green: Double((v >> 8) & 0xff) / 255,
                     blue: Double(v & 0xff) / 255)
    }

    /// Base font mirroring the web font-weight/font-size settings.
    var font: Font {
        let w: Font.Weight
        switch fontWeightName {
        case "400": w = .regular
        case "600": w = .semibold
        case "700": w = .bold
        case "800": w = .heavy
        default: w = .medium
        }
        return .system(size: fontSize, weight: w)
    }

    /// Full-bleed background identical to the website's body background.
    @ViewBuilder
    func backgroundView() -> some View {
        if let solid = solidColor {
            solid.ignoresSafeArea()
        } else {
            let stops: [Color] = [c1, c3, c2]
            if gradientStyle == "radial" {
                RadialGradient(colors: stops, center: .center, startRadius: 0, endRadius: 460)
                    .ignoresSafeArea()
            } else {
                LinearGradient(colors: stops,
                               startPoint: Self.gradientPoint(gradientOrientation, start: true),
                               endPoint: Self.gradientPoint(gradientOrientation, start: false))
                    .ignoresSafeArea()
            }
        }
    }

    /// CSS angle (0deg = vers le haut, sens horaire) → UnitPoint.
    private static func gradientPoint(_ cssAngle: String, start: Bool) -> UnitPoint {
        var deg = 135.0
        if let d = Double(cssAngle.replacingOccurrences(of: "deg", with: "")) { deg = d }
        let rad = deg * .pi / 180
        // direction "to" in screen coords (y down)
        let dx = sin(rad), dy = -cos(rad)
        let k = (abs(dx) + abs(dy)) / 2 // half-length so corners are covered
        let sign: CGFloat = start ? -1 : 1
        return UnitPoint(x: 0.5 + sign * dx * k, y: 0.5 + sign * dy * k)
    }
}
