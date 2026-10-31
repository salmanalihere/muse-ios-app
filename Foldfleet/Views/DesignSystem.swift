import SwiftUI

// MARK: - Foldfleet design system
//
// Deep ocean + brass. Restrained, legible, no neon, no fake 3D.
// Colours are named so a future skin (cosmetic reward) swaps one file.

public enum FleetColors {
    public static let deepOcean = Color(red: 0.03, green: 0.11, blue: 0.20)
    public static let ocean = Color(red: 0.05, green: 0.20, blue: 0.32)
    public static let oceanLight = Color(red: 0.10, green: 0.32, blue: 0.48)
    public static let brass = Color(red: 0.82, green: 0.64, blue: 0.32)
    public static let brassLight = Color(red: 0.95, green: 0.80, blue: 0.50)
    public static let paper = Color(red: 0.93, green: 0.94, blue: 0.92)
    public static let hit = Color(red: 0.85, green: 0.25, blue: 0.18)
    public static let sunk = Color(red: 0.55, green: 0.12, blue: 0.10)
    public static let miss = Color(red: 0.65, green: 0.78, blue: 0.88)
    public static let ship = Color(red: 0.55, green: 0.62, blue: 0.66)
    public static let panel = Color.white.opacity(0.07)
    public static let panelBorder = Color.white.opacity(0.14)
}

public enum FleetFonts {
    public static func title(_ size: CGFloat = 34) -> Font { .system(size: size, weight: .bold, design: .serif) }
    public static func heading(_ size: CGFloat = 20) -> Font { .system(size: size, weight: .semibold, design: .default) }
    public static func body(_ size: CGFloat = 17) -> Font { .system(size: size, weight: .regular, design: .default) }
    /// Monospaced for grid labels (A–J, 1–10) and the battle log.
    public static func mono(_ size: CGFloat = 13) -> Font { .system(size: size, weight: .medium, design: .monospaced) }
}

public struct BrassButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FleetFonts.heading(17))
            .foregroundStyle(FleetColors.deepOcean)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(FleetColors.brass, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

public struct GhostButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FleetFonts.heading(16))
            .foregroundStyle(FleetColors.paper)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(FleetColors.panel, in: Capsule())
            .overlay(Capsule().stroke(FleetColors.panelBorder, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

public extension View {
    func fleetPanel() -> some View {
        self
            .background(FleetColors.panel, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(FleetColors.panelBorder, lineWidth: 1))
    }

    func oceanBackground() -> some View {
        self.background(
            LinearGradient(
                colors: [FleetColors.deepOcean, FleetColors.ocean],
                startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        )
    }
}
