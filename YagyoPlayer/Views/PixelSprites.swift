import CoreGraphics
import SwiftUI

/// ドット絵の妖怪たち — 行列用 SNES 契約(40×48 px、最大12色、`anchorX = 20`、
/// `baselineY = 45`、2倍整数表示)の基盤。各妖怪の行文字列は
/// `KarakasaSprite.swift` などの `*Sprite.swift` を正本とし、
/// 補間なしの Image として保持する。

struct SpriteFrame: @unchecked Sendable {
    let image: Image
    let pixelWidth: CGFloat
    let pixelHeight: CGFloat

    var pixelSize: CGSize { CGSize(width: pixelWidth, height: pixelHeight) }
}

struct PixelSpriteDefinition: Sendable {
    let name: String
    let rows: [String]
    let palette: [Character: UInt32]
    let anchorX: Int
    let baselineY: Int

    var usedSymbols: Set<Character> {
        Set(rows.joined()).subtracting(["."])
    }

    var unknownSymbols: Set<Character> {
        usedSymbols.subtracting(palette.keys)
    }

    var usedColorCount: Int {
        Set(usedSymbols.compactMap { palette[$0] }).count
    }

    var lowestOpaqueY: Int {
        rows.indices.last { rows[$0].contains { $0 != "." } } ?? -1
    }

    var hasTransparentTopAndSideMargins: Bool {
        guard rows.first?.allSatisfy({ $0 == "." }) == true else { return false }
        return rows.allSatisfy { $0.first == "." && $0.last == "." }
    }
}

struct YokaiSprite: @unchecked Sendable {
    let id: String
    let name: String
    let role: String
    /// 歩行サイクル(walk 4)。
    let frames: [SpriteFrame]
    let idleFrame: SpriteFrame?
    /// 静音近似の専用姿勢。契約上は唐傘だけが持ち、他は idle へ fallback する。
    let hushFrame: SpriteFrame?
    /// 強反応の anticipate / reaction。空の妖怪は強反応しない。
    let strongFrames: [SpriteFrame]

    var resolvedIdleFrame: SpriteFrame { idleFrame ?? frames[0] }
    var resolvedHushFrame: SpriteFrame { hushFrame ?? resolvedIdleFrame }

    init(
        id: String,
        name: String,
        role: String,
        frames: [SpriteFrame],
        idleFrame: SpriteFrame? = nil,
        hushFrame: SpriteFrame? = nil,
        strongFrames: [SpriteFrame] = []
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.frames = frames
        self.idleFrame = idleFrame
        self.hushFrame = hushFrame
        self.strongFrames = strongFrames
    }
}

enum PixelArt {
    static func frame(_ definition: PixelSpriteDefinition) -> SpriteFrame {
        precondition(definition.rows.count == 48, "\(definition.name) must be 48 pixels high")
        precondition(
            definition.rows.allSatisfy { $0.utf8.count == 40 },
            "\(definition.name) must be exactly 40 ASCII pixels wide"
        )
        precondition(
            definition.unknownSymbols.isEmpty,
            "\(definition.name) contains unknown palette symbols: \(definition.unknownSymbols)"
        )
        return frame(rows: definition.rows, palette: definition.palette)
    }

    static func frame(rows: [String], palette: [Character: UInt32]) -> SpriteFrame {
        let height = rows.count
        let width = rows.map(\.count).max() ?? 1

        var data = [UInt8](repeating: 0, count: width * height * 4)
        for (y, row) in rows.enumerated() {
            for (x, character) in row.enumerated() {
                guard let hex = palette[character] else { continue }
                let offset = (y * width + x) * 4
                data[offset] = UInt8((hex >> 16) & 0xff)
                data[offset + 1] = UInt8((hex >> 8) & 0xff)
                data[offset + 2] = UInt8(hex & 0xff)
                data[offset + 3] = 0xff
            }
        }

        guard
            let provider = CGDataProvider(data: Data(data) as CFData),
            let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else {
            return SpriteFrame(image: Image(systemName: "questionmark"), pixelWidth: 1, pixelHeight: 1)
        }

        let image = Image(decorative: cgImage, scale: 1)
            .interpolation(.none)
        return SpriteFrame(image: image, pixelWidth: CGFloat(width), pixelHeight: CGFloat(height))
    }
}

enum YokaiGallery {
    /// 夜行の並び順 — Web版と同じ(琵琶牧々はしんがり)。
    /// resident 割当の互換 roster は `YokaiResidency.stableSpriteIDs` が別に固定する。
    static let parade: [YokaiSprite] = [
        YokaiSprite(
            id: "oni", name: "鬼太鼓", role: "Taiko Oni",
            frames: OniSpriteArt.walk.map { PixelArt.frame($0) },
            idleFrame: PixelArt.frame(OniSpriteArt.idle[0]),
            strongFrames: OniSpriteArt.strong.map { PixelArt.frame($0) }
        ),
        YokaiSprite(
            id: "mokugyo", name: "木魚", role: "Mokugyo",
            frames: MokugyoSpriteArt.walk.map { PixelArt.frame($0) },
            idleFrame: PixelArt.frame(MokugyoSpriteArt.idle[0]),
            strongFrames: MokugyoSpriteArt.strong.map { PixelArt.frame($0) }
        ),
        YokaiSprite(
            id: "kasa", name: "唐傘", role: "Kasa-obake",
            frames: KarakasaSpriteArt.walk.map { PixelArt.frame($0) },
            idleFrame: PixelArt.frame(KarakasaSpriteArt.idle[0]),
            hushFrame: PixelArt.frame(KarakasaSpriteArt.hush[0]),
            strongFrames: KarakasaSpriteArt.strong.map { PixelArt.frame($0) }
        ),
        YokaiSprite(
            id: "kappa", name: "河童", role: "Kappa",
            frames: KappaSpriteArt.walk.map { PixelArt.frame($0) },
            idleFrame: PixelArt.frame(KappaSpriteArt.idle[0])
        ),
        YokaiSprite(
            id: "kitsune", name: "狐火", role: "Kitsunebi",
            frames: KitsunebiSpriteArt.walk.map { PixelArt.frame($0) },
            idleFrame: PixelArt.frame(KitsunebiSpriteArt.idle[0]),
            strongFrames: KitsunebiSpriteArt.strong.map { PixelArt.frame($0) }
        ),
        YokaiSprite(
            id: "tengu", name: "天狗", role: "Tengu",
            frames: TenguSpriteArt.walk.map { PixelArt.frame($0) },
            idleFrame: PixelArt.frame(TenguSpriteArt.idle[0]),
            strongFrames: TenguSpriteArt.strong.map { PixelArt.frame($0) }
        ),
        YokaiSprite(
            id: "yuki", name: "雪女", role: "Yuki-onna",
            frames: YukiOnnaSpriteArt.walk.map { PixelArt.frame($0) },
            idleFrame: PixelArt.frame(YukiOnnaSpriteArt.idle[0])
        ),
        YokaiSprite(
            id: "biwa", name: "琵琶牧々", role: "Biwa-bokuboku",
            frames: BiwaBokubokuSpriteArt.walk.map { PixelArt.frame($0) },
            idleFrame: PixelArt.frame(BiwaBokubokuSpriteArt.idle[0])
        ),
    ]

    static let hitotsume = YokaiSprite(
        id: "hitotsume", name: "一つ目小僧", role: "Hitotsume-kozō",
        frames: HitotsumeSpriteArt.walk.map { PixelArt.frame($0) },
        idleFrame: PixelArt.frame(HitotsumeSpriteArt.idle[0])
    )

    static func sprite(withID id: String) -> YokaiSprite? {
        if id == hitotsume.id { return hitotsume }
        return parade.first { $0.id == id }
    }

    /// トラックに妖怪を割り当てる — UUIDから安定して同じ妖怪が出る。
    static func sprite(for id: UUID) -> YokaiSprite {
        sprite(withID: YokaiResidency.spriteID(for: id)) ?? parade[0]
    }
}
