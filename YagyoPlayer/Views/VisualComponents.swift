import SwiftUI

struct YagyoBackdrop: View {
    var progress: Double

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    YagyoColor.sumi,
                    Color(red: 0.071, green: 0.035, blue: 0.094),
                    YagyoColor.sumi
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Canvas { context, size in
                let center = CGPoint(x: size.width * (0.32 + progress * 0.24), y: size.height * 0.12)
                let moonRect = CGRect(x: center.x - 82, y: center.y - 82, width: 164, height: 164)
                context.fill(Path(ellipseIn: moonRect), with: .color(YagyoColor.chochin.opacity(0.09)))
                context.stroke(Path(ellipseIn: moonRect.insetBy(dx: 18, dy: 18)), with: .color(YagyoColor.geppaku.opacity(0.08)), lineWidth: 1)

                for index in 0..<18 {
                    let y = size.height * CGFloat(index) / 17
                    let alpha = 0.04 + Double(index % 4) * 0.01
                    var path = Path()
                    path.move(to: CGPoint(x: -20, y: y))
                    path.addCurve(
                        to: CGPoint(x: size.width + 20, y: y + CGFloat(index % 3) * 14),
                        control1: CGPoint(x: size.width * 0.22, y: y - 20),
                        control2: CGPoint(x: size.width * 0.72, y: y + 24)
                    )
                    context.stroke(path, with: .color(YagyoColor.line.opacity(alpha)), lineWidth: 1)
                }
            }
            .ignoresSafeArea()
        }
    }
}

struct CircularWaveform: View {
    var progress: Double
    var isPlaying: Bool

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.35
            let count = 76

            for index in 0..<count {
                let normalized = Double(index) / Double(count)
                let angle = normalized * .pi * 2 - .pi / 2
                let pulse = sin((normalized * 8 + progress * 3.5) * .pi * 2)
                let length = CGFloat(12 + (pulse + 1) * (isPlaying ? 12 : 5))
                let inner = radius - length * 0.35
                let outer = radius + length

                var path = Path()
                path.move(to: point(center: center, radius: inner, angle: angle))
                path.addLine(to: point(center: center, radius: outer, angle: angle))

                let color = index % 11 == 0 ? YagyoColor.kitsunebi : YagyoColor.geppaku
                context.stroke(path, with: .color(color.opacity(isPlaying ? 0.86 : 0.42)), lineWidth: index % 11 == 0 ? 2.2 : 1.4)
            }

            let ring = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            context.stroke(ring, with: .color(YagyoColor.chochin.opacity(0.52)), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func point(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }
}
