import SwiftUI

// Gemini-style theme: nền phẳng tối, gradient xanh-tím-hồng đặc trưng.
// Giữ tên `SpaceTheme` để tương thích toàn bộ code đang gọi.
enum SpaceTheme {
    // MARK: - Backgrounds (giữ nền space động: surface bán trong suốt để lộ nền)
    static let background = Color(hex: 0x07051A)      // chỉ dùng nếu cần nền tĩnh
    static let backgroundEnd = Color(hex: 0x07051A)
    static let surface = Color.white.opacity(0.06)    // card/surface — kính mờ
    static let surface2 = Color.white.opacity(0.10)   // surface nổi hơn (user bubble)
    static let surface3 = Color.white.opacity(0.14)
    static let card = Color.white.opacity(0.06)
    static let cardBorder = Color.white.opacity(0.10)
    static let bar = Color.clear
    static let inputBar = Color.clear
    static let subtle = Color.white.opacity(0.05)

    // MARK: - Text
    static let primary = Color(hex: 0xE3E3E3)
    static let secondary = Color(hex: 0xC4C7C5)
    static let tertiary = Color(hex: 0x9AA0A6)
    static let quaternary = Color(hex: 0x5F6368)

    // MARK: - Gemini palette
    static let blue    = Color(hex: 0x4796E3)
    static let purple  = Color(hex: 0x9177C7)
    static let pink    = Color(hex: 0xD56F76)
    static let green   = Color(hex: 0x37BE5F)
    static let amber   = Color(hex: 0xFCC934)
    static let red     = Color(hex: 0xF28B82)

    // Alias cho code cũ (cosmic palette -> ánh xạ sang Gemini)
    static let cyan      = blue
    static let azure     = blue
    static let violet    = purple
    static let magenta   = pink
    static let coral     = pink
    static let lime      = green
    static let emerald   = green

    // MARK: - Brand gradient (chữ ký Gemini)
    static let accentGradient = LinearGradient(
        colors: [blue, purple, pink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Provider gradients
    static func providerGradient(_ name: String) -> LinearGradient {
        let key = name.lowercased()
        switch key {
        case let s where s.contains("anthropic"):
            return LinearGradient(colors: [pink, amber], startPoint: .topLeading, endPoint: .bottomTrailing)
        case let s where s.contains("openai"):
            return LinearGradient(colors: [green, blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        case let s where s.contains("google"):
            return LinearGradient(colors: [blue, pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        case let s where s.contains("meta"):
            return LinearGradient(colors: [purple, blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        case let s where s.contains("mistral"):
            return LinearGradient(colors: [amber, pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        case let s where s.contains("groq"):
            return LinearGradient(colors: [green, blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            return LinearGradient(colors: [blue, purple, pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    static func providerHue(_ name: String) -> Color {
        let key = name.lowercased()
        if key.contains("anthropic") { return pink }
        if key.contains("openai") { return green }
        if key.contains("google") { return blue }
        if key.contains("meta") { return purple }
        if key.contains("mistral") { return amber }
        if key.contains("groq") { return green }
        return purple
    }

    // MARK: - Aliases
    static var accentStart: Color { blue }
    static var accentEnd: Color { pink }

    // MARK: - Status
    static let connected = green
    static let connectedGlow = green.opacity(0.5)
    static let busy = amber
    static let busyBg = amber.opacity(0.14)
    static let error = red

    // MARK: - Layout
    static let radiusCard: CGFloat = 20
    static let radiusBubble: CGFloat = 20
    static let radiusSmall: CGFloat = 14
    static let borderWidth: CGFloat = 1
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

extension View {
    func spaceCard(tint: Color? = nil) -> some View {
        self
            .background(SpaceTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: SpaceTheme.radiusCard, style: .continuous)
                    .stroke(SpaceTheme.cardBorder, lineWidth: SpaceTheme.borderWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: SpaceTheme.radiusCard, style: .continuous))
    }

    func glassBar() -> some View {
        self.background(SpaceTheme.bar)
    }

    func spaceRadius(_ radius: CGFloat) -> some View {
        self.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    func spaceBackground() -> some View {
        ZStack {
            SpaceBackground()
            self
        }
    }
}

struct SectionLabel: View {
    let text: String
    let accent: Color?

    init(_ text: String, accent: Color? = nil) {
        self.text = text
        self.accent = accent
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.4)
            .foregroundColor(SpaceTheme.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)
    }
}
