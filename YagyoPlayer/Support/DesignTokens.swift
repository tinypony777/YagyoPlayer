import SwiftUI

enum YagyoColor {
    static let sumi = Color(red: 0.043, green: 0.047, blue: 0.078)
    static let yoiyami = Color(red: 0.082, green: 0.090, blue: 0.149)
    static let yoiyami2 = Color(red: 0.114, green: 0.125, blue: 0.200)
    static let geppaku = Color(red: 0.914, green: 0.894, blue: 0.827)
    static let chochin = Color(red: 0.941, green: 0.651, blue: 0.235)
    static let shu = Color(red: 0.761, green: 0.251, blue: 0.180)
    static let kitsunebi = Color(red: 0.435, green: 0.827, blue: 0.878)
    static let line = Color(red: 0.173, green: 0.188, blue: 0.278)
    static let dim = Color(red: 0.541, green: 0.561, blue: 0.659)
}

struct RitualPanel: ViewModifier {
    var radius: CGFloat = 24
    var padding: CGFloat = 16
    var tint: Color = YagyoColor.chochin.opacity(0.12)

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        content
            .padding(padding)
            .background {
                shape
                    .fill(YagyoColor.yoiyami.opacity(0.78))
                    .overlay(shape.stroke(YagyoColor.line.opacity(0.9), lineWidth: 1))
            }
            .ritualGlass(shape: shape, tint: tint)
    }
}

private extension View {
    @ViewBuilder
    func ritualGlass(shape: RoundedRectangle, tint: Color) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(tint), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}

extension View {
    func ritualPanel(radius: CGFloat = 24, padding: CGFloat = 16, tint: Color = YagyoColor.chochin.opacity(0.12)) -> some View {
        modifier(RitualPanel(radius: radius, padding: padding, tint: tint))
    }
}
