import AppKit
import SwiftUI

extension Tokens {
    /// The panel's background surfaces (screen spec §1's palette).
    ///
    /// **Opaque, deliberately — no material underneath.**
    ///
    /// The panel floats over whatever the user happens to have open, so a
    /// translucent surface hands control of its own luminance to the desktop.
    /// That is what made the panel wash out over a white window: tab labels
    /// and formatting-bar icons were drawn in `text.secondary` against a
    /// surface that had drifted almost to white, and their contrast collapsed.
    ///
    /// The screen spec anticipated this and prescribed a flat tint composited
    /// *over* a material — 88% for the panel, 80% for the rail — to keep some
    /// of the material's character while bounding the drift. The arithmetic
    /// does not support it. Against the worst-case backdrops (pure white and
    /// pure black) those opacities leave `text.secondary` at:
    ///
    ///     light rail over black   2.91   fails AA
    ///     dark panel over white   2.63   fails AA
    ///     dark rail  over white   2.12   fails AA   ← the reported case
    ///
    /// Solving for the alpha that holds 4.5:1 in the worst case gives 0.92 to
    /// 0.99 depending on surface. At 0.99 the backdrop contributes one percent;
    /// there is no material left to see. A translucency that must be 99% opaque
    /// to be legible is not translucency, so this drops the material rather
    /// than keeping a decorative one percent of it.
    ///
    /// The alternative — keep the material and raise every foreground to
    /// `text.primary` — also passes, and was rejected: it flattens the
    /// secondary tier out of existence, so an inactive tab reads exactly like
    /// an active one and the formatting bar loses its "quiet until it applies
    /// to your caret" affordance. Losing the blur costs less than losing the
    /// hierarchy.
    enum Surface {
        /// The left tab rail.
        case rail
        /// The panel body, and the collapsed handle that is the panel at rest.
        case panel
        /// Popovers and sheets, which sit above the panel and must read as
        /// separated from it.
        case elevated

        var color: Color {
            switch self {
            case .rail:     Self.adaptive(light: 0xF5F5F7, dark: 0x1E1E20)
            case .panel:    Self.adaptive(light: 0xFBFBFD, dark: 0x242426)
            case .elevated: Self.adaptive(light: 0xFFFFFF, dark: 0x2C2C2E)
            }
        }

        /// Resolved per appearance rather than read once, so the panel follows
        /// a light/dark switch live. A colour captured at construction is the
        /// other half of the macOS defect this file exists to fix.
        private static func adaptive(light: UInt32, dark: UInt32) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(hex: isDark ? dark : light)
            })
        }
    }
}

private extension NSColor {
    /// 24-bit RGB, as the screen spec writes them.
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension View {
    /// Fills the view's background with an opaque surface. See `Tokens.Surface`
    /// for why it is opaque.
    func notebarSurface(_ surface: Tokens.Surface) -> some View {
        background(surface.color)
    }
}
