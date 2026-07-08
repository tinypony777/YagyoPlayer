import SwiftUI

/// 夜行絵巻 — 妖怪の行列が右から左へ流れる。Web版「百鬼夜行ビートマシン」の
/// 看板ビジュアルを SwiftUI Canvas に移植したもの。再生中は音声レベルに
/// 合わせて妖怪が跳ね、提灯が明滅する。月に触れると刻が変わる。
struct YagyoParadeView: View {
    var isPlaying: Bool
    var level: Double
    var isUshimitsu: Bool
    var onMoonTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let launch = Date()
    private static let spriteScale: Double = 3
    private static let moonRadius: Double = 19

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { timeline in
                Canvas { context, size in
                    var context = context
                    let time = max(0, timeline.date.timeIntervalSince(Self.launch))
                    draw(in: &context, size: size, time: time)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                let moon = Self.moonCenter(width: Double(geometry.size.width))
                let dx = Double(location.x) - moon.x
                let dy = Double(location.y) - moon.y
                if (dx * dx + dy * dy).squareRoot() < 30 {
                    onMoonTap()
                }
            }
        }
        .frame(height: 158)
        .background(Color(yagyoHex: 0x05060d))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(yagyoHex: 0x3a3524).opacity(0.9), lineWidth: 1)
        }
        .accessibilityElement()
        .accessibilityLabel("妖怪の夜行絵巻")
        .accessibilityHint("月に触れると刻が変わる")
        .accessibilityAction(named: "月に触れる") { onMoonTap() }
    }

    private static func moonCenter(width: Double) -> (x: Double, y: Double) {
        (x: width - 46, y: 34)
    }

    private var palette: ParadePalette {
        isUshimitsu ? .ushimitsu : .day
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let pal = palette
        let animated = !reduceMotion
        let width = Double(size.width)
        let height = Double(size.height)

        // 夜空
        context.fill(
            Path(CGRect(x: 0, y: 0, width: width, height: height)),
            with: .linearGradient(
                Gradient(colors: [pal.skyTop, pal.skyBottom]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: height)
            )
        )

        drawStars(in: &context, width: width, height: height, time: time, animated: animated)
        drawMoon(in: &context, width: width, palette: pal)
        drawFog(in: &context, width: width, time: time, palette: pal, animated: animated)

        // 地面
        context.fill(
            Path(CGRect(x: 0, y: height - 22, width: width, height: 22)),
            with: .color(.black.opacity(0.35))
        )
        context.fill(
            Path(CGRect(x: 0, y: height - 22, width: width, height: 1)),
            with: .color(YagyoColor.geppaku.opacity(0.08))
        )

        // 提灯
        let pulse = isPlaying ? level : 0
        let sway1 = animated ? sin(time * 0.8) * 3 : 0
        let sway2 = animated ? sin(time * 0.6 + 2) * 4 : 0
        drawChochin(in: &context, x: 26 + sway1, y: 30, pulse: pulse, time: time, animated: animated)
        drawChochin(in: &context, x: width * 0.42 + sway2, y: 22, pulse: pulse, time: time + 3, animated: animated)

        drawProcession(in: &context, width: width, height: height, time: time, animated: animated)
    }

    private func drawStars(in context: inout GraphicsContext, width: Double, height: Double, time: TimeInterval, animated: Bool) {
        for index in 0..<26 {
            let seed = Double(index)
            let x = fract(sin(seed * 12.9898) * 43758.5453) * width
            let y = fract(sin(seed * 78.233) * 12543.123) * height * 0.55
            let big = fract(sin(seed * 3.7) * 951.135) < 0.2
            let phase = fract(sin(seed * 45.164) * 7635.31) * 6.28
            let alpha = animated ? 0.35 + 0.35 * sin(time * 0.7 + phase) : 0.5
            let side: Double = big ? 2 : 1
            context.fill(
                Path(CGRect(x: x, y: y, width: side, height: side)),
                with: .color(Color(yagyoHex: 0xcdd6ea).opacity(alpha))
            )
        }
    }

    private func drawMoon(in context: inout GraphicsContext, width: Double, palette pal: ParadePalette) {
        let moon = Self.moonCenter(width: width)
        let radius = Self.moonRadius

        let haloRadius = radius * 2.1
        context.fill(
            Path(ellipseIn: CGRect(x: moon.x - haloRadius, y: moon.y - haloRadius, width: haloRadius * 2, height: haloRadius * 2)),
            with: .color(pal.halo)
        )
        context.fill(
            Path(ellipseIn: CGRect(x: moon.x - radius, y: moon.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(pal.moon)
        )
        // クレーター
        context.fill(
            Path(ellipseIn: CGRect(x: moon.x - 6 - 3.4, y: moon.y - 3 - 3.4, width: 6.8, height: 6.8)),
            with: .color(.black.opacity(0.12))
        )
        context.fill(
            Path(ellipseIn: CGRect(x: moon.x + 5 - 2.4, y: moon.y + 6 - 2.4, width: 4.8, height: 4.8)),
            with: .color(.black.opacity(0.12))
        )
    }

    private func drawFog(in context: inout GraphicsContext, width: Double, time: TimeInterval, palette pal: ParadePalette, animated: Bool) {
        let blobs: [(x0: Double, y: Double, r: Double, v: Double)] = [
            (0.08, 110, 70, 6), (0.36, 96, 95, -4), (0.67, 118, 80, 5)
        ]
        for blob in blobs {
            let range = width + blob.r * 2
            var x = blob.x0 * width + (animated ? blob.v * time : 0)
            x = x.truncatingRemainder(dividingBy: range)
            if x < 0 { x += range }
            x -= blob.r
            context.fill(
                Path(ellipseIn: CGRect(x: x - blob.r, y: blob.y - blob.r * 0.32, width: blob.r * 2, height: blob.r * 0.64)),
                with: .color(pal.fog)
            )
        }
    }

    private func drawChochin(in context: inout GraphicsContext, x: Double, y: Double, pulse: Double, time: TimeInterval, animated: Bool) {
        // 紐の先で振り子のように揺れる
        let sway = animated ? sin(time * 1.3) * 2 : 0
        var cord = Path()
        cord.move(to: CGPoint(x: x, y: 0))
        cord.addLine(to: CGPoint(x: x + sway, y: y))
        context.stroke(cord, with: .color(YagyoColor.geppaku.opacity(0.2)), lineWidth: 1)

        let bx = x + sway
        let glowRadius = 17 + pulse * 6
        let glowY = y + 11
        context.fill(
            Path(ellipseIn: CGRect(x: bx - glowRadius, y: glowY - glowRadius, width: glowRadius * 2, height: glowRadius * 2)),
            with: .radialGradient(
                Gradient(colors: [YagyoColor.chochin.opacity(0.14 + pulse * 0.2), .clear]),
                center: CGPoint(x: bx, y: glowY),
                startRadius: 0,
                endRadius: glowRadius
            )
        )

        context.fill(Path(CGRect(x: bx - 4, y: y, width: 8, height: 3)), with: .color(Color(yagyoHex: 0x191420)))
        context.fill(Path(CGRect(x: bx - 5, y: y + 3, width: 10, height: 14)), with: .color(Color(yagyoHex: 0xe2903a)))
        context.fill(Path(CGRect(x: bx - 3, y: y + 5, width: 3, height: 10)), with: .color(Color(yagyoHex: 0xf5bd6a)))
        context.fill(Path(CGRect(x: bx - 4, y: y + 17, width: 8, height: 3)), with: .color(Color(yagyoHex: 0x191420)))
    }

    private func drawProcession(in context: inout GraphicsContext, width: Double, height: Double, time: TimeInterval, animated: Bool) {
        var walkers = YokaiGallery.parade
        if isUshimitsu {
            walkers.append(YokaiGallery.hitotsume)
        }

        let count = Double(walkers.count)
        let gap = max(86, (width + 140) / count)
        let loop = gap * count
        let speed: Double = animated ? 46 : 0
        let frameIndex = animated ? Int(time * 4) % 2 : 0
        let ground = height - 20
        let scale = Self.spriteScale

        for (index, sprite) in walkers.enumerated() {
            // 丑三つ時のしんがり(一つ目小僧)は何にも反応せず、ただ付いてくる
            let isExtra = index >= YokaiGallery.parade.count

            var x = (-time * speed + Double(index) * gap).truncatingRemainder(dividingBy: loop)
            if x < 0 { x += loop }
            x -= 70

            let bob = animated ? sin(time * 4 + Double(index) * 1.7) * 1.6 : 0

            // 音の山に合わせた跳ね — 妖怪ごとに位相をずらす
            var react: Double = 0
            if isPlaying && animated && !isExtra {
                let wave = max(0, sin(time * 2 * .pi * 1.9 + Double(index) * 1.13))
                react = wave * wave * level
            }
            let jump = Double(sprite.jump) * react * 1.6

            var frame = sprite.frames[frameIndex % sprite.frames.count]
            if let hit = sprite.hitFrame, react > (sprite.hitOnStrongOnly ? 0.8 : 0.6) {
                frame = hit
            }

            let baseWidth = Double(frame.pixelWidth) * scale
            var drawWidth = baseWidth
            var drawHeight = Double(frame.pixelHeight) * scale
            if react > 0 {
                if sprite.flare {
                    drawWidth *= 1 + 0.22 * react
                    drawHeight *= 1 + 0.22 * react
                }
                if sprite.squash {
                    drawHeight *= 1 - 0.16 * react
                }
            }

            let rect = CGRect(
                x: x - (drawWidth - baseWidth) / 2,
                y: ground - drawHeight - bob - jump,
                width: drawWidth,
                height: drawHeight
            )
            context.draw(frame.image, in: rect)

            // 木魚のバチ — 山が来ると振り上がる
            if index == 1 {
                var stick = context
                stick.translateBy(x: rect.maxX + 2, y: rect.minY + 4)
                stick.rotate(by: .radians(-0.6 + min(1, react) * 1.1))
                stick.fill(
                    Path(CGRect(x: 0, y: 0, width: 3, height: 16)),
                    with: .color(Color(yagyoHex: 0xf0e2c0))
                )
            }

            // 強い山で白くひらめく
            if react > 0.85 {
                context.blendMode = .plusLighter
                context.fill(Path(rect), with: .color(.white.opacity((react - 0.85) * 1.2)))
                context.blendMode = .normal
            }
        }
    }

    private func fract(_ value: Double) -> Double {
        value - value.rounded(.down)
    }
}
