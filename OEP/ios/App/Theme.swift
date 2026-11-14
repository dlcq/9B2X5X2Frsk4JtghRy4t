// OEP - visual system.
//
// A dark, restrained palette with a single purple/blue accent pair.  Everything
// is drawn with SwiftUI primitives (no bitmap assets): gradients, hairlines,
// typography and generous spacing carry the design.
import SwiftUI

struct OEPPalette {
    var background: Color
    var secondaryBackground: Color
    var card: Color
    var elevated: Color
    var border: Color
    var text: Color
    var subtext: Color
    var purple: Color
    var blue: Color

    var supported: Color { Color(red: 0.44, green: 0.84, blue: 0.68) }
    var partial: Color { Color(red: 0.97, green: 0.75, blue: 0.42) }
    var unsupported: Color { Color(red: 0.95, green: 0.45, blue: 0.48) }
    var unknown: Color { Color(red: 0.62, green: 0.65, blue: 0.73) }

    static func make(_ theme: AppSettings.Theme) -> OEPPalette {
        switch theme {
        case .midnight:
            return OEPPalette(
                background: Color(hex: 0x090A0F),
                secondaryBackground: Color(hex: 0x10121A),
                card: Color(hex: 0x151925),
                elevated: Color(hex: 0x1B2030),
                border: Color(hex: 0x282E3D),
                text: Color(hex: 0xF4F4F8),
                subtext: Color(hex: 0x969BAA),
                purple: Color(hex: 0x9B7BFF),
                blue: Color(hex: 0x76BFFF))
        case .oled:
            return OEPPalette(
                background: .black,
                secondaryBackground: Color(hex: 0x07080C),
                card: Color(hex: 0x0E1016),
                elevated: Color(hex: 0x151925),
                border: Color(hex: 0x22283A),
                text: Color(hex: 0xF6F6FA),
                subtext: Color(hex: 0x9297A6),
                purple: Color(hex: 0xA385FF),
                blue: Color(hex: 0x82C6FF))
        }
    }

    func color(for level: SupportLevel) -> Color {
        switch level {
        case .supported: return supported
        case .partial: return partial
        case .unsupported: return unsupported
        case .unknown: return unknown
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255.0,
                  green: Double((hex >> 8) & 0xFF) / 255.0,
                  blue: Double(hex & 0xFF) / 255.0,
                  opacity: alpha)
    }
}

private struct OEPPaletteKey: EnvironmentKey {
    static let defaultValue = OEPPalette.make(.midnight)
}

extension EnvironmentValues {
    var oep: OEPPalette {
        get { self[OEPPaletteKey.self] }
        set { self[OEPPaletteKey.self] = newValue }
    }
}

// MARK: - Typography

enum OEPFont {
    static func brand(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
    static func body(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }
    static func label(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Background

struct OEPBackground: View {
    @Environment(\.oep) private var palette
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            RadialGradient(
                colors: [palette.purple.opacity(0.16), .clear],
                center: .topLeading,
                startRadius: 8,
                endRadius: 520
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [palette.blue.opacity(0.10), .clear],
                center: .bottomTrailing,
                startRadius: 12,
                endRadius: 620
            )
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Building blocks

struct OEPCard<Content: View>: View {
    @Environment(\.oep) private var palette
    var padding: CGFloat = 18
    var content: Content

    init(padding: CGFloat = 18, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(palette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(palette.border, lineWidth: 1)
                    )
            )
    }
}

struct OEPGlowCard<Content: View>: View {
    @Environment(\.oep) private var palette
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [palette.purple.opacity(0.26), palette.blue.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing)
                        )
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(palette.card.opacity(0.86))
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(palette.border, lineWidth: 1)
                }
            )
            .shadow(color: palette.purple.opacity(0.18), radius: 26, x: 0, y: 14)
    }
}

struct SectionHeader: View {
    @Environment(\.oep) private var palette
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(OEPFont.label(11))
                .tracking(1.6)
                .foregroundStyle(palette.subtext)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(OEPFont.label(11))
                    .foregroundStyle(palette.subtext.opacity(0.8))
            }
        }
    }
}

struct SupportBadge: View {
    @Environment(\.oep) private var palette
    let level: SupportLevel
    var compact: Bool = false

    var body: some View {
        let color = palette.color(for: level)
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(compact ? level.shortTitle : level.title)
                .font(OEPFont.label(compact ? 10 : 11))
                .tracking(compact ? 0.9 : 0.2)
                .foregroundStyle(color)
        }
        .padding(.horizontal, compact ? 9 : 11)
        .padding(.vertical, compact ? 5 : 6)
        .background(
            Capsule().fill(color.opacity(0.12))
                .overlay(Capsule().strokeBorder(color.opacity(0.28), lineWidth: 1))
        )
    }
}

struct StatTile: View {
    @Environment(\.oep) private var palette
    let label: String
    let value: String
    var unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(OEPFont.label(9))
                .tracking(1.2)
                .foregroundStyle(palette.subtext)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(OEPFont.mono(18, weight: .semibold))
                    .foregroundStyle(palette.text)
                if let unit {
                    Text(unit)
                        .font(OEPFont.label(10))
                        .foregroundStyle(palette.subtext)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.elevated.opacity(0.65))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 1))
        )
    }
}

struct OEPPrimaryButtonStyle: ButtonStyle {
    @Environment(\.oep) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OEPFont.title(16))
            .foregroundStyle(Color.black.opacity(0.86))
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(colors: [palette.purple, palette.blue],
                                             startPoint: .leading,
                                             endPoint: .trailing))
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(configuration.isPressed ? 0.18 : 0))
                }
            )
            .opacity(isEnabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct OEPSecondaryButtonStyle: ButtonStyle {
    @Environment(\.oep) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OEPFont.title(15))
            .foregroundStyle(palette.text)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(palette.elevated.opacity(configuration.isPressed ? 0.9 : 0.6))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(palette.border, lineWidth: 1))
            )
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// Row used for interactive lists (settings, library entries).
struct OEPRowButtonStyle: ButtonStyle {
    @Environment(\.oep) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(configuration.isPressed ? palette.elevated.opacity(0.8) : .clear)
            )
    }
}

struct EmptyStateView: View {
    @Environment(\.oep) private var palette
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(palette.purple.opacity(0.14))
                    .frame(width: 82, height: 82)
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(palette.purple)
            }
            VStack(spacing: 8) {
                Text(title)
                    .font(OEPFont.title(19))
                    .foregroundStyle(palette.text)
                Text(message)
                    .font(OEPFont.body(14))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.subtext)
                    .padding(.horizontal, 24)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(OEPSecondaryButtonStyle())
                    .frame(maxWidth: 220)
            }
        }
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
    }
}

/// Monospaced key/value line for diagnostic data.
struct InfoRow: View {
    @Environment(\.oep) private var palette
    let key: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .font(OEPFont.body(13))
                .foregroundStyle(palette.subtext)
                .frame(width: 116, alignment: .leading)
            Text(value)
                .font(OEPFont.mono(13))
                .foregroundStyle(palette.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
