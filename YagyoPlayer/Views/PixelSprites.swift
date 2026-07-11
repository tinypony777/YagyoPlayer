import CoreGraphics
import SwiftUI

/// ドット絵の妖怪たち — 百鬼夜行ビートマシン(Web版)の絵柄をそのまま移植。
/// 行文字列 + 1文字パレットから CGImage を組み立て、拡大してもにじまないよう
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
    let frames: [SpriteFrame]
    let hitFrame: SpriteFrame?
    let idleFrame: SpriteFrame?
    let hushFrame: SpriteFrame?
    let strongFrames: [SpriteFrame]
    let jump: CGFloat
    let squash: Bool
    let flare: Bool
    /// 強打(大きな山)のときだけ hitFrame を見せる
    let hitOnStrongOnly: Bool

    var resolvedIdleFrame: SpriteFrame { idleFrame ?? frames[0] }
    var resolvedHushFrame: SpriteFrame { hushFrame ?? resolvedIdleFrame }

    init(
        id: String,
        name: String,
        role: String,
        frames: [SpriteFrame],
        hitFrame: SpriteFrame? = nil,
        idleFrame: SpriteFrame? = nil,
        hushFrame: SpriteFrame? = nil,
        strongFrames: [SpriteFrame] = [],
        jump: CGFloat,
        squash: Bool = false,
        flare: Bool = false,
        hitOnStrongOnly: Bool = false
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.frames = frames
        self.hitFrame = hitFrame
        self.idleFrame = idleFrame
        self.hushFrame = hushFrame
        self.strongFrames = strongFrames
        self.jump = jump
        self.squash = squash
        self.flare = flare
        self.hitOnStrongOnly = hitOnStrongOnly
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
    // 共通: k=墨 w=月白
    private static let ink: [Character: UInt32] = ["k": 0x191420, "w": 0xfff3e0]

    private static func palette(_ extra: [Character: UInt32]) -> [Character: UInt32] {
        ink.merging(extra) { _, new in new }
    }

    // --- 鬼太鼓 ---
    private static let oniPal = palette([
        "h": 0xf0e2c0, "r": 0xd9503a, "R": 0x8e2c1f,
        "y": 0xe8b04b, "Y": 0x7a4a1c, "m": 0x3d2b1a, "p": 0xe8a13a
    ])
    private static let oniA = PixelArt.frame(rows: [
        "..hh......hh..",
        "..hh......hh..",
        "...kkkkkkkk...",
        "..krrrrrrrrk..",
        "..krwkrrwkrk..",
        "..krrrrrrrrk..",
        "..krrkkkkrrk..",
        "...krrrrrrk...",
        ".YYYYYYYYYYYY.",
        ".YyyyyyyyyyyY.",
        ".YyymyyyymyyY.",
        ".YyyyyyyyyyyY.",
        ".YYYYYYYYYYYY.",
        "...pp....pp...",
        "...pp....pp...",
        "...kk....kk...",
    ], palette: oniPal)
    private static let oniB = PixelArt.frame(rows: [
        "..hh......hh..",
        "..hh......hh..",
        "...kkkkkkkk...",
        "..krrrrrrrrk..",
        "..krwkrrwkrk..",
        "..krrrrrrrrk..",
        "..krrkkkkrrk..",
        "...krrrrrrk...",
        ".YYYYYYYYYYYY.",
        ".YyyyyyyyyyyY.",
        ".YyymyyyymyyY.",
        ".YyyyyyyyyyyY.",
        ".YYYYYYYYYYYY.",
        "....pp..pp....",
        "....pp..pp....",
        "....kk..kk....",
    ], palette: oniPal)

    // --- 木魚 ---
    private static let mokuPal = palette([
        "m": 0xc98d4f, "M": 0x8a5a2e, "r": 0xb03a2e, "R": 0x7c241c
    ])
    private static let mokuA = PixelArt.frame(rows: [
        "...kkkkkkk...",
        "..kmmmmmmmk..",
        ".kmwkmmmwkmk.",
        ".kmmmmmmmmmk.",
        ".kMkkkkkkkMk.",
        "..kmmmmmmmk..",
        "...kkkkkkk...",
        "..rrrrrrrrr..",
        ".rrRrrrrrRrr.",
    ], palette: mokuPal)

    // --- 河童 ---
    private static let kappaPal = palette([
        "g": 0x4e9e5f, "G": 0x2e6b3d, "y": 0xe8c85a,
        "o": 0xe08a3c, "s": 0xcaa46a, "S": 0x8a6a3a
    ])
    private static let kappaA = PixelArt.frame(rows: [
        "...yyyyy....",
        "..GgggggG...",
        "..ggggggg...",
        ".gwkggwkgg..",
        "oogggggggg..",
        ".ggggggggs..",
        ".gGggggggss.",
        ".gggggggsSs.",
        "..gggggggs..",
        "..gg...gg...",
        "..gg...gg...",
        "..GG...GG...",
    ], palette: kappaPal)
    private static let kappaB = PixelArt.frame(rows: [
        "...yyyyy....",
        "..GgggggG...",
        "..ggggggg...",
        ".gwkggwkgg..",
        "oogggggggg..",
        ".ggggggggs..",
        ".gGggggggss.",
        ".gggggggsSs.",
        "..gggggggs..",
        "...gg.gg....",
        "...gg.gg....",
        "...GG.GG....",
    ], palette: kappaPal)

    // --- 狐火 ---
    private static let kitsPal = palette(["c": 0x7fd8e6, "C": 0x3a9fb5])
    private static let kitsA = PixelArt.frame(rows: [
        "..c......c..",
        "..cc....cc..",
        "..ccc..ccc..",
        "..cccccccc..",
        ".cccwwwwccc.",
        ".ccwwwwwwcc.",
        ".ccwwkwkwcc.",
        ".ccwwwwwwcc.",
        "..ccwwwwcc..",
        "...ccwwcc...",
        "....cccc....",
        ".....cc.....",
    ], palette: kitsPal)
    private static let kitsB = PixelArt.frame(rows: [
        "...c.....c..",
        "..cc.....cc.",
        "..ccc..ccc..",
        "..cccccccc..",
        ".cccwwwwccc.",
        ".ccwwwwwwcc.",
        ".ccwwkwkwcc.",
        ".ccwwwwwwcc.",
        "..ccwwwwcc..",
        "...ccwwcc...",
        "....cccc....",
        "....cc......",
    ], palette: kitsPal)

    // --- 天狗 ---
    private static let tenguPal = palette([
        "r": 0xd9503a, "b": 0x28324e, "B": 0x141a30,
        "h": 0xf0e2c0, "l": 0x5a8a4e, "L": 0x3d6337
    ])
    private static let tenguA = PixelArt.frame(rows: [
        "......kkk......",
        ".....khhhk.....",
        "....krrrrrk....",
        "....krwkrrk....",
        "rrrrkrrrrrkBB..",
        "....krrkrrkBBB.",
        ".....krrrk.BB..",
        "..l..kbbbbkB...",
        ".lll.bbbbbbb...",
        "..L.bbbbbbbb...",
        "..Lbbbbbbbb....",
        "....bbbbbb.....",
        "....bb..bb.....",
        "....bb..bb.....",
        "....kk..kk.....",
    ], palette: tenguPal)
    private static let tenguB = PixelArt.frame(rows: [
        "......kkk......",
        ".....khhhk.....",
        "....krrrrrk....",
        "....krwkrrk....",
        "rrrrkrrrrrkBB..",
        "....krrkrrkBBB.",
        ".....krrrk.BB..",
        "..l..kbbbbkB...",
        ".lll.bbbbbbb...",
        "..L.bbbbbbbb...",
        "..Lbbbbbbbb....",
        "....bbbbbb.....",
        ".....bb.bb.....",
        ".....bb.bb.....",
        ".....kk.kk.....",
    ], palette: tenguPal)
    private static let tenguHit = PixelArt.frame(rows: [
        "......kkk...BB.",
        ".....khhhk.BBB.",
        "....krrrrrkBB..",
        ".lll.krwkrrkBBB",
        "rrrrkrrrrrkBBB.",
        ".lL.krrkrrkBB..",
        "..L..krrrk.....",
        ".....kbbbbk....",
        ".....bbbbbbb...",
        "....bbbbbbbb...",
        "...bbbbbbbb....",
        "....bbbbbb.....",
        "....bb..bb.....",
        "....bb..bb.....",
        "....kk..kk.....",
    ], palette: tenguPal)

    // --- 雪女 ---
    private static let yukiPal = palette([
        "f": 0xf6e8e2, "b": 0xcfdcec, "W": 0xf4f6fa
    ])
    private static let yukiA = PixelArt.frame(rows: [
        "..kkkkkk....",
        ".kkkkkkkk...",
        ".kkfffffkk..",
        ".kkfkfkfkk..",
        ".kkfffffkk..",
        ".kkkfffkkk..",
        ".k.WWWWW.k..",
        ".k.WbWWbW.k.",
        ".kWWWWWWWWk.",
        ".kWWbWWbWWk.",
        "..WWWWWWWW..",
        "..WWWWWWW...",
        "...WbWWW....",
        "....WWW.....",
        "..b..W...b..",
        "............",
    ], palette: yukiPal)
    private static let yukiB = PixelArt.frame(rows: [
        "..kkkkkk....",
        ".kkkkkkkk...",
        ".kkfffffkk..",
        ".kkfkfkfkk..",
        ".kkfffffkk..",
        ".kkkfffkkk..",
        ".k.WWWWW.k..",
        ".k.WbWWbW.k.",
        ".kWWWWWWWWk.",
        ".kWWbWWbWWk.",
        "..WWWWWWWW..",
        "...WWWWWW...",
        "....WWWb....",
        ".....WW.....",
        "..b...W..b..",
        "............",
    ], palette: yukiPal)

    // --- 琵琶牧々 ---
    private static let biwaPal = palette([
        "m": 0xc98d4f, "M": 0x8a5a2e, "b": 0x4a4458,
        "B": 0x332f42, "h": 0xe8d5a8
    ])
    private static let biwaA = PixelArt.frame(rows: [
        "....hkkh......",
        "....hkkh......",
        ".....kk.......",
        ".....kk.......",
        "....kmmk......",
        "...kmmmmk.....",
        "..kmmmmmmk....",
        "..kmwkmwkk....",
        "..kmmmmmmk....",
        "..kmMmmMmk....",
        "...kmmmmk.....",
        "..bbbbbbbbb...",
        ".bbbbbbbbbbb..",
        ".bBbbbbbbbBb..",
        "...bb...bb....",
        "...kk...kk....",
    ], palette: biwaPal)
    private static let biwaB = PixelArt.frame(rows: [
        "....hkkh......",
        "....hkkh......",
        ".....kk.......",
        ".....kk.......",
        "....kmmk......",
        "...kmmmmk.....",
        "..kmmmmmmk....",
        "..kmwkmwkk....",
        "..kmmmmmmk....",
        "..kmMmmMmk....",
        "...kmmmmk.....",
        "..bbbbbbbbb...",
        ".bbbbbbbbbbb..",
        ".bBbbbbbbbBb..",
        "....bb.bb.....",
        "....kk.kk.....",
    ], palette: biwaPal)

    // --- 一つ目小僧(丑三つ時のしんがり) ---
    private static let hitoPal = palette([
        "f": 0xe8c9a8, "i": 0x4a3f78, "r": 0xd9503a
    ])
    private static let hitoA = PixelArt.frame(rows: [
        "..kkkkk..",
        ".kkkkkkk.",
        ".kfffffk.",
        ".kfwwwfk.",
        ".kfwkwfk.",
        ".kfwwwfk.",
        ".kffrffk.",
        "..iiiii..",
        ".iiiiiii.",
        ".iiiiiii.",
        "..ii.ii..",
        "..kk.kk..",
    ], palette: hitoPal)
    private static let hitoB = PixelArt.frame(rows: [
        "..kkkkk..",
        ".kkkkkkk.",
        ".kfffffk.",
        ".kfwwwfk.",
        ".kfwkwfk.",
        ".kfwwwfk.",
        ".kffrffk.",
        "..iiiii..",
        ".iiiiiii.",
        ".iiiiiii.",
        "...ii.ii.",
        "...kk.kk.",
    ], palette: hitoPal)

    // --- ぬりかべ ---
    private static let nuriPal = palette(["g": 0x9a9aa4, "G": 0x6f6f7a])
    static let nurikabe = PixelArt.frame(rows: [
        "kkkkkkkkkkkkkk",
        "kggggggggggggk",
        "kgwkgggggwkggk",
        "kggggggggggggk",
        "kgGgggGgggGggk",
        "kggggggggggggk",
        "kkkkkkkkkkkkkk",
        "..kk......kk..",
    ], palette: nuriPal)

    /// 夜行の並び順 — Web版と同じ(琵琶牧々はしんがり)。
    static let parade: [YokaiSprite] = [
        YokaiSprite(id: "oni", name: "鬼太鼓", role: "Taiko Oni", frames: [oniA, oniB], jump: 7),
        YokaiSprite(id: "mokugyo", name: "木魚", role: "Mokugyo", frames: [mokuA, mokuA], jump: 5, squash: true),
        YokaiSprite(
            id: "kasa",
            name: "唐傘",
            role: "Kasa-obake",
            frames: KarakasaSpriteArt.walk.map { PixelArt.frame($0) },
            hitFrame: PixelArt.frame(KarakasaSpriteArt.strong[1]),
            idleFrame: PixelArt.frame(KarakasaSpriteArt.idle[0]),
            hushFrame: PixelArt.frame(KarakasaSpriteArt.hush[0]),
            strongFrames: KarakasaSpriteArt.strong.map { PixelArt.frame($0) },
            jump: 6,
            hitOnStrongOnly: true
        ),
        YokaiSprite(id: "kappa", name: "河童", role: "Kappa", frames: [kappaA, kappaB], jump: 6),
        YokaiSprite(id: "kitsune", name: "狐火", role: "Kitsunebi", frames: [kitsA, kitsB], jump: 3, flare: true),
        YokaiSprite(id: "tengu", name: "天狗", role: "Tengu", frames: [tenguA, tenguB], hitFrame: tenguHit, jump: 8),
        YokaiSprite(id: "yuki", name: "雪女", role: "Yuki-onna", frames: [yukiA, yukiB], jump: 2),
        YokaiSprite(id: "biwa", name: "琵琶牧々", role: "Biwa-bokuboku", frames: [biwaA, biwaB], jump: 4),
    ]

    static let hitotsume = YokaiSprite(
        id: "hitotsume", name: "一つ目小僧", role: "Hitotsume-kozō",
        frames: [hitoA, hitoB], jump: 0
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
