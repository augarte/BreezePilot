import SwiftUI
import UIKit

enum BreezePilotPalette {
    static let accent = adaptive(light: 0x0057BA, dark: 0x8AC5FF)
    static let action = Color(uiColor: rgb(0x005BC7))
    static let navy = Color(uiColor: rgb(0x102651))
    static let gold = Color(uiColor: rgb(0xFFD65B))
    static let canvas = adaptive(light: 0xF2F7FF, dark: 0x0D1728)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x17243A)
    static let ice = adaptive(light: 0xEAF3FF, dark: 0x203550)
    static let temperatureGradient = LinearGradient(colors: [action, navy], startPoint: .topLeading, endPoint: .bottomTrailing)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            rgb(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    private static func rgb(_ value: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
