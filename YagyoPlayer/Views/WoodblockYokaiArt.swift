import SwiftUI
import UIKit

/// 承認済みのneutral idleを、resident IDへ結び付ける表示専用の版画アセット。
/// 既存のpixel定義は互換fallbackとQA資料として残し、再生・DSP状態は受け取らない。
struct WoodblockYokaiAsset: @unchecked Sendable {
    static let logicalCanvasSize: CGFloat = 64

    let id: String
    let assetName: String
    /// Asset Catalogに正本が収録されているときだけ、新表示へ切り替える。
    let isAvailable: Bool
    /// 442px正本上のalpha bbox（左上原点）を64pt論理キャンバスへ正規化した値。
    let contentRect: CGRect
    /// TimelineViewの更新ごとにImageを作り直さない表示用キャッシュ。
    let image: Image
    let frame: SpriteFrame
}

enum WoodblockYokaiGallery {
    static let all: [WoodblockYokaiAsset] = [
        asset(
            id: "oni",
            name: "YokaiOniWoodblock",
            rect: CGRect(x: 9.412, y: 5.357, width: 45.466, height: 54.733)
        ),
        asset(
            id: "mokugyo",
            name: "YokaiMokugyoWoodblock",
            rect: CGRect(x: 8.109, y: 5.068, width: 43.729, height: 51.692)
        ),
        asset(
            id: "kasa",
            name: "YokaiKasaWoodblock",
            rect: CGRect(x: 10.281, y: 4.489, width: 37.068, height: 54.443)
        ),
        asset(
            id: "kappa",
            name: "YokaiKappaWoodblock",
            rect: CGRect(x: 10.281, y: 8.109, width: 44.163, height: 47.783)
        ),
        asset(
            id: "kitsune",
            name: "YokaiKitsuneWoodblock",
            rect: CGRect(x: 4.054, y: 10.570, width: 56.471, height: 41.701)
        ),
        asset(
            id: "tengu",
            name: "YokaiTenguWoodblock",
            rect: CGRect(x: 10.136, y: 4.923, width: 40.253, height: 53.719)
        ),
        asset(
            id: "yuki",
            name: "YokaiYukiWoodblock",
            rect: CGRect(x: 7.529, y: 2.606, width: 48.072, height: 60.814)
        ),
        asset(
            id: "biwa",
            name: "YokaiBiwaWoodblock",
            rect: CGRect(x: 6.226, y: 2.317, width: 47.638, height: 60.235)
        ),
        asset(
            id: "hitotsume",
            name: "YokaiHitotsumeWoodblock",
            rect: CGRect(x: 13.321, y: 5.937, width: 36.489, height: 57.484)
        )
    ]

    static func asset(withID id: String) -> WoodblockYokaiAsset? {
        all.first { $0.id == id && $0.isAvailable }
    }

    static func asset(for trackID: UUID) -> WoodblockYokaiAsset? {
        asset(withID: YokaiResidency.spriteID(for: trackID))
    }

    private static func asset(id: String, name: String, rect: CGRect) -> WoodblockYokaiAsset {
        let image = Image(name)
            .renderingMode(.original)
            .interpolation(.high)
        return WoodblockYokaiAsset(
            id: id,
            assetName: name,
            isAvailable: UIImage(named: name) != nil,
            contentRect: rect,
            image: image,
            frame: SpriteFrame(
                image: image,
                pixelWidth: WoodblockYokaiAsset.logicalCanvasSize,
                pixelHeight: WoodblockYokaiAsset.logicalCanvasSize,
                contentRect: rect
            )
        )
    }
}

/// 同じneutral idleから派生する、表示上の静音・強反応。
/// 歩行は既存の水平移動とbobを使い、別の絵を独立生成しない。
struct WoodblockYokaiPose: Equatable, Sendable {
    let scale: Double
    let verticalOffset: Double
    let opacity: Double

    static func resolve(
        activity: ParadeSignalSnapshot.Activity,
        strongPhase: ParadeSignalSnapshot.StrongPhase,
        reduceMotion: Bool
    ) -> Self {
        if strongPhase != .inactive {
            guard !reduceMotion else {
                return Self(scale: 1, verticalOffset: 0, opacity: 1)
            }
            switch strongPhase {
            case .inactive:
                break
            case .anticipate:
                return Self(scale: 0.96, verticalOffset: 2, opacity: 0.94)
            case .open:
                return Self(scale: 1.07, verticalOffset: -2, opacity: 1)
            case .recover:
                return Self(scale: 1.02, verticalOffset: -1, opacity: 1)
            }
        }

        switch activity {
        case .stopped, .normal:
            return Self(scale: 1, verticalOffset: 0, opacity: 1)
        case .unavailable:
            return Self(scale: 0.98, verticalOffset: 1, opacity: 0.88)
        case .quietProxy:
            return Self(scale: 0.95, verticalOffset: 2, opacity: 0.78)
        }
    }
}
