import SwiftUI

// MARK: - Animated Space Background
// Vũ trụ sống động: cực quang, sao nhiều màu, ngân hà xoắn, hành tinh, sao băng

struct SpaceBackground: View {
    var body: some View {
        ZStack {
            // 1. Base gradient sâu - không còn 1 màu phẳng
            LinearGradient(
                colors: [
                    SpaceTheme.background,
                    Color(red: 0.05, green: 0.02, blue: 0.13),
                    Color(red: 0.03, green: 0.04, blue: 0.15),
                    Color(red: 0.08, green: 0.02, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // 2. Aurora trên đỉnh
            AuroraLayer()

            // 3. Ngân hà xoắn xa xa
            DistantGalaxy()

            // 4. Nebula nhiều màu
            NebulaLayer()

            // 5. Sao nhiều màu - đỏ/xanh/trắng/vàng
            ColorfulStarfield()

            // 6. Hành tinh nhỏ trang trí
            DecorPlanet()

            // 7. Sao băng
            ShootingStarsLayer()

            // 8. Vignette nhẹ ở góc
            RadialGradient(
                colors: [.clear, .black.opacity(0.35)],
                center: .center,
                startRadius: 200,
                endRadius: 700
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .drawingGroup()
    }
}

// MARK: - Aurora (cực quang)

struct AuroraLayer: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        Canvas { ctx, size in
            for i in 0..<3 {
                let band = i
                let yOffset = size.height * 0.08 + CGFloat(i) * 30
                var path = Path()
                let amplitude: CGFloat = 26 + CGFloat(i) * 8
                path.move(to: CGPoint(x: -50, y: yOffset))
                for x in stride(from: -50.0, through: size.width + 50, by: 8) {
                    let xC = CGFloat(x)
                    let y = yOffset + sin((xC / 80) + phase + CGFloat(band)) * amplitude
                    path.addLine(to: CGPoint(x: xC, y: y))
                }
                path.addLine(to: CGPoint(x: size.width + 50, y: 0))
                path.addLine(to: CGPoint(x: -50, y: 0))
                path.closeSubpath()

                let colors: [Color] = (band == 0)
                    ? [SpaceTheme.lime.opacity(0.28), .clear]
                    : (band == 1)
                        ? [SpaceTheme.cyan.opacity(0.22), .clear]
                        : [SpaceTheme.violet.opacity(0.20), .clear]

                ctx.fill(
                    path,
                    with: .linearGradient(
                        Gradient(colors: colors),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: 0, y: yOffset + 60)
                    )
                )
            }
        }
        .blur(radius: 22)
        .blendMode(.screen)
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.linear(duration: 22).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

// MARK: - Distant Galaxy

struct DistantGalaxy: View {
    @State private var rotate: Double = 0

    var body: some View {
        ZStack {
            // Bulge giữa
            Circle()
                .fill(
                    RadialGradient(
                        colors: [SpaceTheme.amber.opacity(0.7), SpaceTheme.coral.opacity(0.3), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 22
                    )
                )
                .frame(width: 60, height: 60)
                .blur(radius: 6)

            // Đĩa xoắn (ellipse)
            ForEach(0..<2) { i in
                Ellipse()
                    .stroke(
                        AngularGradient(
                            colors: [
                                SpaceTheme.violet.opacity(0.5),
                                SpaceTheme.magenta.opacity(0.4),
                                SpaceTheme.azure.opacity(0.5),
                                .clear,
                                SpaceTheme.violet.opacity(0.4)
                            ],
                            center: .center
                        ),
                        lineWidth: i == 0 ? 18 : 10
                    )
                    .frame(width: 180, height: 70)
                    .blur(radius: i == 0 ? 12 : 6)
                    .opacity(i == 0 ? 0.6 : 0.9)
            }
        }
        .rotationEffect(.degrees(-22))
        .position(x: UIScreen.main.bounds.width * 0.78, y: 130)
        .opacity(0.85)
        .rotationEffect(.degrees(rotate))
        .onAppear {
            withAnimation(.linear(duration: 200).repeatForever(autoreverses: false)) {
                rotate = 360
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Nebula (cải tiến đa màu)

struct NebulaLayer: View {
    var body: some View {
        ZStack {
            NebulaOrb(color: SpaceTheme.violet, size: 360, offset: CGSize(width: -130, height: -240), duration: 15)
            NebulaOrb(color: SpaceTheme.magenta, size: 280, offset: CGSize(width: 160, height: -300), duration: 19)
            NebulaOrb(color: SpaceTheme.azure, size: 320, offset: CGSize(width: -100, height: 280), duration: 23)
            NebulaOrb(color: SpaceTheme.coral, size: 200, offset: CGSize(width: 140, height: 360), duration: 17)
            NebulaOrb(color: SpaceTheme.cyan, size: 240, offset: CGSize(width: 80, height: 60), duration: 26)
        }
        .ignoresSafeArea()
    }
}

struct NebulaOrb: View {
    let color: Color
    let size: CGFloat
    let offset: CGSize
    let duration: Double
    @State private var animate = false

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.32), color.opacity(0.08), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
            .blur(radius: 50)
            .blendMode(.screen)
            .offset(
                x: offset.width + (animate ? 28 : -28),
                y: offset.height + (animate ? -22 : 22)
            )
            .scaleEffect(animate ? 1.25 : 0.85)
            .opacity(animate ? 1 : 0.55)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: duration)
                    .repeatForever(autoreverses: true)
                ) {
                    animate = true
                }
            }
    }
}

// MARK: - Colorful Starfield

struct ColorfulStarfield: View {
    private let stars: [ColorStarSpec] = (0..<110).map { i in
        let palette: [Color] = [
            .white, .white, .white, .white,           // đa số sao trắng
            SpaceTheme.cyan,
            SpaceTheme.amber,
            SpaceTheme.coral.opacity(0.9),
            SpaceTheme.violet.opacity(0.9)
        ]
        return ColorStarSpec(
            x: CGFloat.random(in: 0...1),
            y: CGFloat.random(in: 0...1),
            size: CGFloat.random(in: 0.6...2.6),
            duration: Double.random(in: 1.5...4.0),
            delay: Double.random(in: 0...4),
            color: palette[i % palette.count]
        )
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(stars) { star in
                    ColorStar(spec: star)
                        .position(
                            x: star.x * geo.size.width,
                            y: star.y * geo.size.height
                        )
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct ColorStarSpec: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let duration: Double
    let delay: Double
    let color: Color
}

struct ColorStar: View {
    let spec: ColorStarSpec
    @State private var bright = false

    var body: some View {
        Circle()
            .fill(spec.color)
            .frame(width: spec.size, height: spec.size)
            .opacity(bright ? 1.0 : 0.18)
            .scaleEffect(bright ? 1.3 : 0.8)
            .shadow(color: spec.color.opacity(bright ? 0.7 : 0), radius: bright ? 3 : 0)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: spec.duration)
                    .repeatForever(autoreverses: true)
                    .delay(spec.delay)
                ) {
                    bright = true
                }
            }
    }
}

// MARK: - Decor Planet (hành tinh ở góc)

struct DecorPlanet: View {
    @State private var rotate = false

    var body: some View {
        ZStack {
            // Vòng halo
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            SpaceTheme.cyan.opacity(0.5),
                            SpaceTheme.magenta.opacity(0.4),
                            SpaceTheme.amber.opacity(0.4),
                            SpaceTheme.cyan.opacity(0.5)
                        ],
                        center: .center
                    ),
                    lineWidth: 1.2
                )
                .frame(width: 140, height: 50)
                .rotationEffect(.degrees(-18))
                .blur(radius: 0.5)

            // Body hành tinh
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            SpaceTheme.coral,
                            SpaceTheme.magenta,
                            SpaceTheme.violet
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 60, height: 60)
                .overlay(
                    // Highlight
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(0.5), .clear],
                                center: UnitPoint(x: 0.3, y: 0.25),
                                startRadius: 0,
                                endRadius: 30
                            )
                        )
                )
                .shadow(color: SpaceTheme.magenta.opacity(0.5), radius: 18)
        }
        .position(x: UIScreen.main.bounds.width * 0.82, y: UIScreen.main.bounds.height * 0.78)
        .opacity(0.85)
        .rotationEffect(.degrees(rotate ? 8 : -8))
        .onAppear {
            withAnimation(.easeInOut(duration: 12).repeatForever(autoreverses: true)) {
                rotate.toggle()
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Shooting Stars

struct ShootingStarsLayer: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ShootingStar(delay: 2, travel: geo.size, hue: SpaceTheme.cyan)
                ShootingStar(delay: 7, travel: geo.size, hue: SpaceTheme.amber)
                ShootingStar(delay: 12, travel: geo.size, hue: .white)
                ShootingStar(delay: 18, travel: geo.size, hue: SpaceTheme.magenta)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct ShootingStar: View {
    let delay: Double
    let travel: CGSize
    let hue: Color
    @State private var go = false

    private let startX: CGFloat
    private let startY: CGFloat

    init(delay: Double, travel: CGSize, hue: Color) {
        self.delay = delay
        self.travel = travel
        self.hue = hue
        self.startX = CGFloat.random(in: 0.05...0.7)
        self.startY = CGFloat.random(in: 0.05...0.4)
    }

    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [hue.opacity(0.95), hue.opacity(0.5), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 80, height: 1.8)
            .rotationEffect(.degrees(20))
            .shadow(color: hue.opacity(0.8), radius: 4)
            .position(
                x: go ? startX * travel.width + 280 : startX * travel.width,
                y: go ? startY * travel.height + 140 : startY * travel.height
            )
            .opacity(go ? 0 : 1)
            .onAppear {
                animate()
            }
    }

    private func animate() {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeIn(duration: 1.1)) {
                go = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                go = false
                DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 18...28)) {
                    animate()
                }
            }
        }
    }
}
