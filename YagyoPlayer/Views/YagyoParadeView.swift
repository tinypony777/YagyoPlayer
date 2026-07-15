import SwiftUI

enum ParadeMotionPreference {
    static func resolve(systemReduceMotion: Bool, previewOverride: Bool?) -> Bool {
        previewOverride ?? systemReduceMotion
    }
}

struct ParadeProcessionLayout: Sendable {
    static let staticLeadingInset: Double = 12
    private static let animatedLeadingOffset: Double = 70

    static func xPosition(
        index: Int,
        walkerCount: Int,
        gap: Double,
        speed: Double,
        time: TimeInterval
    ) -> Double {
        let staticPosition = staticLeadingInset + Double(index) * gap
        guard speed > 0, walkerCount > 0, gap > 0 else { return staticPosition }

        let loop = gap * Double(walkerCount)
        var x = (-time * speed + Double(index) * gap).truncatingRemainder(dividingBy: loop)
        if x < 0 { x += loop }
        return x - animatedLeadingOffset
    }
}

/// 妖怪欄間 — 音量近似を、説明可能な行進・静音・強反応へ翻訳する表示層。
/// 楽曲の拍や構成を推定せず、再生は一切操作しない。
struct YagyoParadeView: View {
    var signal: ParadeSignalSnapshot
    var residentSpriteID: String?
    var isUshimitsu: Bool
    var onMoonTap: () -> Void
    /// Deterministic fixture hook. Production call sites leave this unset.
    var previewReduceMotionOverride: Bool? = nil

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private static let launch = Date()
    private static let pixelSpriteScale: Double = 2
    private static let woodblockSpriteScale: Double = 1.62
    private static let moonRadius: Double = 19

    private var reduceMotion: Bool {
        ParadeMotionPreference.resolve(
            systemReduceMotion: systemReduceMotion,
            previewOverride: previewReduceMotionOverride
        )
    }

    var body: some View {
        GeometryReader { geometry in
            TimelineView(
                .animation(
                    minimumInterval: 1.0 / 30.0,
                    paused: reduceMotion || signal.activity == .stopped
                )
            ) { timeline in
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
        .frame(height: 142)
        .background(isUshimitsu ? YagyoPrintColor.stage : YagyoPrintColor.paperRaised)
        .clipShape(WoodblockFrameShape(cut: 10))
        .overlay {
            let shape = WoodblockFrameShape(cut: 10)
            shape.stroke(
                isUshimitsu ? YagyoPrintColor.ink : YagyoPrintColor.indigo,
                lineWidth: isUshimitsu ? 1 : 2
            )
            if !isUshimitsu {
                shape
                    .inset(by: 4)
                    .stroke(YagyoPrintColor.vermillion.opacity(0.72), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("音に反応する妖怪の行列")
        .accessibilityValue(
            signal.accessibilityValue(
                residentName: residentSprite?.name,
                isUshimitsu: isUshimitsu
            )
        )
        .accessibilityHint("月に触れると刻が変わる")
        .accessibilityAction(named: "月に触れる") { onMoonTap() }
    }

    private static func moonCenter(width: Double) -> (x: Double, y: Double) {
        (x: width - 46, y: 34)
    }

    private var palette: ParadePalette {
        isUshimitsu ? .ushimitsu : .day
    }

    private var residentSprite: YokaiSprite? {
        guard let residentSpriteID else { return nil }
        return YokaiGallery.sprite(withID: residentSpriteID)
    }

    private var isStrongActive: Bool {
        signal.strongPhase != .inactive
    }

    private var isSceneAnimated: Bool {
        !reduceMotion && signal.activity != .stopped
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let pal = palette
        let animated = isSceneAnimated
        let width = Double(size.width)
        let height = Double(size.height)

        context.fill(
            Path(CGRect(x: 0, y: 0, width: width, height: height)),
            with: .linearGradient(
                Gradient(colors: [pal.skyTop, pal.skyBottom]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: height)
            )
        )

        if !isUshimitsu {
            drawDayPrintMotifs(in: &context, width: width, height: height)
        }
        drawStars(in: &context, width: width, height: height, time: time, animated: animated)
        drawMoon(in: &context, width: width, palette: pal)
        drawFog(in: &context, width: width, time: time, palette: pal, animated: animated)

        context.fill(
            Path(CGRect(x: 0, y: height - 22, width: width, height: 22)),
            with: .color(
                isUshimitsu
                    ? Color.black.opacity(0.18)
                    : YagyoPrintColor.persimmon.opacity(0.15)
            )
        )
        context.fill(
            Path(CGRect(x: 0, y: height - 22, width: width, height: 1)),
            with: .color(
                isUshimitsu
                    ? YagyoColor.geppaku.opacity(0.08)
                    : YagyoPrintColor.vermillion.opacity(0.50)
            )
        )

        let sway1 = animated ? sin(time * 0.8) * 3 : 0
        let sway2 = animated ? sin(time * 0.6 + 2) * 4 : 0
        drawChochin(in: &context, x: 26 + sway1, y: 30, time: time, animated: animated)
        drawChochin(in: &context, x: width * 0.42 + sway2, y: 22, time: time + 3, animated: animated)

        drawProcession(in: &context, width: width, height: height, time: time)
    }

    /// Day欄間へ色版を足す。細い藍の青海波と朱の霞だけに留め、妖怪の輪郭を邪魔しない。
    private func drawDayPrintMotifs(
        in context: inout GraphicsContext,
        width: Double,
        height: Double
    ) {
        var kasumi = Path()
        kasumi.move(to: CGPoint(x: 0, y: 27))
        kasumi.addLine(to: CGPoint(x: width * 0.46, y: 27))
        kasumi.addLine(to: CGPoint(x: width * 0.41, y: 35))
        kasumi.addLine(to: CGPoint(x: 0, y: 35))
        kasumi.closeSubpath()
        context.fill(kasumi, with: .color(YagyoPrintColor.vermillion.opacity(0.10)))

        let radius = max(18, width / 12)
        for row in 0..<2 {
            for column in -1...8 {
                let offset = row.isMultiple(of: 2) ? 0.0 : radius
                let center = CGPoint(
                    x: Double(column) * radius * 2 + offset,
                    y: height - 18 - Double(row) * radius * 0.52
                )
                var wave = Path()
                wave.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(180),
                    endAngle: .degrees(360),
                    clockwise: false
                )
                context.stroke(
                    wave,
                    with: .color(YagyoPrintColor.indigo.opacity(row == 0 ? 0.16 : 0.09)),
                    lineWidth: 0.8
                )
            }
        }
    }

    private func drawStars(
        in context: inout GraphicsContext,
        width: Double,
        height: Double,
        time: TimeInterval,
        animated: Bool
    ) {
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
                with: .color(
                    isUshimitsu
                        ? YagyoPrintColor.paperRaised.opacity(alpha)
                        : YagyoPrintColor.inkMuted.opacity(alpha * 0.22)
                )
            )
        }
    }

    private func drawMoon(in context: inout GraphicsContext, width: Double, palette pal: ParadePalette) {
        let moon = Self.moonCenter(width: width)
        let radius = Self.moonRadius
        let haloRadius = radius * 2.1

        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: moon.x - haloRadius,
                    y: moon.y - haloRadius,
                    width: haloRadius * 2,
                    height: haloRadius * 2
                )
            ),
            with: .color(pal.halo)
        )
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: moon.x - radius,
                    y: moon.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            ),
            with: .color(pal.moon)
        )
        context.fill(
            Path(ellipseIn: CGRect(x: moon.x - 9.4, y: moon.y - 6.4, width: 6.8, height: 6.8)),
            with: .color(.black.opacity(0.12))
        )
        context.fill(
            Path(ellipseIn: CGRect(x: moon.x + 2.6, y: moon.y + 3.6, width: 4.8, height: 4.8)),
            with: .color(.black.opacity(0.12))
        )
    }

    private func drawFog(
        in context: inout GraphicsContext,
        width: Double,
        time: TimeInterval,
        palette pal: ParadePalette,
        animated: Bool
    ) {
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
                Path(
                    ellipseIn: CGRect(
                        x: x - blob.r,
                        y: blob.y - blob.r * 0.32,
                        width: blob.r * 2,
                        height: blob.r * 0.64
                    )
                ),
                with: .color(pal.fog)
            )
        }
    }

    private func drawChochin(
        in context: inout GraphicsContext,
        x: Double,
        y: Double,
        time: TimeInterval,
        animated: Bool
    ) {
        let sway = animated ? sin(time * 1.3) * 2 : 0
        var cord = Path()
        cord.move(to: CGPoint(x: x, y: 0))
        cord.addLine(to: CGPoint(x: x + sway, y: y))
        context.stroke(
            cord,
            with: .color(
                isUshimitsu
                    ? YagyoColor.geppaku.opacity(0.2)
                    : YagyoPrintColor.inkMuted.opacity(0.30)
            ),
            lineWidth: 1
        )

        let bx = x + sway
        let halo = chochinHalo
        let glowY = y + 11
        let glowRect = CGRect(
            x: bx - halo.width / 2,
            y: glowY - halo.height / 2,
            width: halo.width,
            height: halo.height
        )
        let glowPath = Path(ellipseIn: glowRect)

        if signal.activity == .unavailable {
            context.stroke(
                glowPath,
                with: .color(YagyoColor.chochin.opacity(0.34)),
                style: StrokeStyle(lineWidth: 1, dash: [2, 2])
            )
        } else {
            context.fill(glowPath, with: .color(YagyoColor.chochin.opacity(halo.opacity * 0.42)))
        }

        context.fill(Path(CGRect(x: bx - 4, y: y, width: 8, height: 3)), with: .color(Color(yagyoHex: 0x191420)))
        context.fill(Path(CGRect(x: bx - 5, y: y + 3, width: 10, height: 14)), with: .color(Color(yagyoHex: 0xe2903a)))
        context.fill(Path(CGRect(x: bx - 3, y: y + 5, width: 3, height: 10)), with: .color(Color(yagyoHex: 0xf5bd6a)))
        context.fill(Path(CGRect(x: bx - 4, y: y + 17, width: 8, height: 3)), with: .color(Color(yagyoHex: 0x191420)))
    }

    private var chochinHalo: (width: Double, height: Double, opacity: Double) {
        if reduceMotion {
            switch signal.levelBand {
            case .unavailable:
                return (28, 20, 0.18)
            case .low:
                return (22, 14, 0.12)
            case .medium:
                return (32, 22, 0.22)
            case .high:
                return (42, 30, 0.34)
            }
        }

        let displayLevel = signal.activity == .unavailable ? 0.35 : signal.level
        return (
            34 + displayLevel * 12,
            34 + displayLevel * 12,
            0.14 + displayLevel * 0.2
        )
    }

    private func drawProcession(
        in context: inout GraphicsContext,
        width: Double,
        height: Double,
        time: TimeInterval
    ) {
        let ids = YokaiResidency.processionIDs(
            residentID: residentSpriteID,
            isUshimitsu: isUshimitsu
        )
        let walkers = ids.compactMap { YokaiGallery.sprite(withID: $0) }
        guard !walkers.isEmpty else { return }

        let count = Double(walkers.count)
        let gap = max(86, (width + 140) / count)
        let speed = processionSpeed
        let ground = height - 20

        for (index, sprite) in walkers.enumerated() {
            let x = ParadeProcessionLayout.xPosition(
                index: index,
                walkerCount: walkers.count,
                gap: gap,
                speed: speed,
                time: time
            )

            let woodblockArt = WoodblockYokaiGallery.asset(withID: sprite.id)
            guard let frame = woodblockArt?.frame ?? frame(for: sprite, time: time) else { continue }

            let bob = bobOffset(index: index, time: time)
            let baseScale = woodblockArt == nil
                ? Self.pixelSpriteScale
                : Self.woodblockSpriteScale
            // 木版正本へ替えても、従来の妖怪ごとのhush/strong反応表は広げない。
            let supportsHushReaction = sprite.hushFrame != nil
            let supportsStrongReaction = !sprite.strongFrames.isEmpty
            let poseActivity: ParadeSignalSnapshot.Activity =
                signal.activity == .quietProxy && !supportsHushReaction
                ? .normal
                : signal.activity
            let poseStrongPhase: ParadeSignalSnapshot.StrongPhase = supportsStrongReaction
                ? signal.strongPhase
                : .inactive
            let pose = woodblockArt == nil
                ? WoodblockYokaiPose(scale: 1, verticalOffset: 0, opacity: 1)
                : WoodblockYokaiPose.resolve(
                    activity: poseActivity,
                    strongPhase: poseStrongPhase,
                    reduceMotion: reduceMotion
                )
            let drawScale = baseScale * pose.scale
            let baseWidth = Double(frame.pixelWidth) * baseScale
            let width = Double(frame.pixelWidth) * drawScale
            let height = Double(frame.pixelHeight) * drawScale
            let rect = CGRect(
                x: x - (width - baseWidth) / 2,
                y: ground - Double(frame.contentRect.maxY) * drawScale - bob + pose.verticalOffset,
                width: width,
                height: height
            )
            if pose.opacity < 0.999 {
                context.drawLayer { layer in
                    layer.opacity = pose.opacity
                    layer.draw(frame.image, in: rect)
                }
            } else {
                context.draw(frame.image, in: rect)
            }

            let isResident = index == 0 && residentSpriteID == sprite.id
            if isResident {
                drawResidentMarker(
                    in: &context,
                    above: contentRect(of: frame, drawnIn: rect, scale: drawScale)
                )
            }

            if reduceMotion, isStrongActive, supportsStrongReaction {
                drawStaticStrongOutline(
                    in: &context,
                    around: contentRect(of: frame, drawnIn: rect, scale: drawScale)
                )
            }
        }
    }

    /// キャンバス全体の描画rectから、フレームの不透明bboxが占める画面上のrectを得る。
    private func contentRect(
        of frame: SpriteFrame,
        drawnIn rect: CGRect,
        scale: Double
    ) -> CGRect {
        CGRect(
            x: rect.minX + frame.contentRect.minX * scale,
            y: rect.minY + frame.contentRect.minY * scale,
            width: frame.contentRect.width * scale,
            height: frame.contentRect.height * scale
        )
    }

    private var processionSpeed: Double {
        guard !reduceMotion else { return 0 }
        switch signal.activity {
        case .stopped:
            return 0
        case .quietProxy:
            return 14
        case .normal, .unavailable:
            return 46
        }
    }

    private func bobOffset(index: Int, time: TimeInterval) -> Double {
        guard !reduceMotion else { return 0 }
        let amplitude: Double
        switch signal.activity {
        case .stopped:
            return 0
        case .quietProxy:
            amplitude = 0.4
        case .normal:
            amplitude = 1.3 + signal.level * 0.5
        case .unavailable:
            amplitude = 1.3
        }
        return sin(time * 4 + Double(index) * 1.7) * amplitude
    }

    private func frame(for sprite: YokaiSprite, time: TimeInterval) -> SpriteFrame? {
        let idle = sprite.idleFrame ?? sprite.frames.first
        let hush = sprite.hushFrame ?? idle

        if isStrongActive, !sprite.strongFrames.isEmpty {
            if reduceMotion {
                return sprite.strongReactionFrame ?? idle
            }
            switch signal.strongPhase {
            case .inactive:
                break
            case .anticipate:
                return sprite.strongAnticipateFrame ?? idle
            case .open:
                return sprite.strongReactionFrame ?? idle
            case .recover:
                return idle
            }
        }

        switch signal.activity {
        case .stopped:
            return idle
        case .quietProxy:
            return hush
        case .normal, .unavailable:
            guard !reduceMotion, !sprite.frames.isEmpty else { return idle }
            let frameIndex = Int(max(0, time) * 4).quotientAndRemainder(dividingBy: sprite.frames.count).remainder
            return sprite.frames.dropFirst(frameIndex).first ?? idle
        }
    }

    private func drawResidentMarker(in context: inout GraphicsContext, above rect: CGRect) {
        let center = CGPoint(x: rect.midX, y: rect.minY - 11)
        var diamond = Path()
        diamond.move(to: CGPoint(x: center.x, y: center.y - 3))
        diamond.addLine(to: CGPoint(x: center.x + 3, y: center.y))
        diamond.addLine(to: CGPoint(x: center.x, y: center.y + 3))
        diamond.addLine(to: CGPoint(x: center.x - 3, y: center.y))
        diamond.closeSubpath()
        context.fill(diamond, with: .color(YagyoColor.chochin))
        context.stroke(diamond, with: .color(YagyoColor.geppaku.opacity(0.9)), lineWidth: 1)

        var stem = Path()
        stem.move(to: CGPoint(x: center.x, y: center.y + 3))
        stem.addLine(to: CGPoint(x: center.x, y: center.y + 8))
        context.stroke(stem, with: .color(YagyoColor.geppaku), lineWidth: 1)

        if reduceMotion, isStrongActive {
            context.stroke(
                Path(
                    CGRect(
                        x: center.x - 5,
                        y: center.y - 5,
                        width: 10,
                        height: 10
                    )
                ),
                with: .color(YagyoColor.kitsunebi.opacity(0.9)),
                lineWidth: 1
            )
        }
    }

    private func drawStaticStrongOutline(in context: inout GraphicsContext, around rect: CGRect) {
        context.stroke(
            Path(rect.insetBy(dx: -2, dy: -2)),
            with: .color(YagyoColor.kitsunebi.opacity(0.72)),
            style: StrokeStyle(lineWidth: 1, dash: [3, 2])
        )
    }

    private func fract(_ value: Double) -> Double {
        value - value.rounded(.down)
    }
}
