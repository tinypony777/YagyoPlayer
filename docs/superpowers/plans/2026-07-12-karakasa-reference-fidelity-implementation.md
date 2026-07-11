# 唐傘・参照忠実度再設計 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Native subagents own implementation and review. Remote Desktop Commander may invoke local Codex only for Xcode generation, build, tests, Simulator operation, and QA-artifact extraction.

**Goal:** ユーザー提供の参照画と同じ、赤い正面向き・一つ目・一本足の唐傘を40×48の8フレームとして再実装し、構造テストとHatch Pet型の視覚QAで同一性を保証する。

**Architecture:** 既存の `PixelSpriteDefinition`、Swift ASCII renderer、`idle 1 + walk 4 + hush 1 + strong 2` の接続は変えない。テスト側に意味付きピクセル解析を置き、現在の紫・横向き造形で先にREDを確認してから、`KarakasaSprite.swift`だけを差し替える。最新ASCIIソースからtest-only contact sheetとGIFを決定的に生成し、独立レビューとSimulator証跡へ接続する。

**Tech Stack:** Swift 6、SwiftUI、CoreGraphics、UIKit、ImageIO、XCTest、XcodeGen、iOS Simulator

## Current execution status — 2026-07-12

- Tasks 1–3 are complete. The rejected art produced a semantic RED; the current coherent family and QA renderer pass the checked focused suite **11 / 11**, skip 0.
- Task 4 Steps 1–6 are complete: Xcode 27.0 generic build SUCCESS、iOS 27／iPhone 17 Pro full suite **65 / 65** skip 0、semantic AX Pro **4 + 1** and 17e **1 / 1** skip 0、[evidence ledger](../../evidence/step4-karakasa/README.md) generation commit `d1eca866`。
- Reduce Motion `t0`／`t+2 s` full PNGs are identical and the canvas crop has 0 differing bytes. All semantic state selection used AX element references with no coordinate taps.
- Contact sheet／GIF and all seven Simulator screenshots are APPROVED by two independent native reviewers, with 0 BLOCKER／MAJOR／MINOR findings. Pro Strong right-edge placement is INFO-only and is not clipped. User visual approval is not complete.
- Task 4 Step 7 is complete: binary evidence commit `150219fea8a13ed95ea65885f5e7b46101cff9e5` has all 9 binary hashes/links, the 5 old images are deleted, and Draft PR #13's body/state were verified. Draft PR、`main` unmerged、mixed-art、remaining-yokai separate matrix gates remain unchanged.

## Global Constraints

- 正本はユーザー提供画像 `/workspace/scratch/3ec5d53af5a1/upload/C56C38FF-7552-4132-AFEA-D0A5A729376E.jpeg`。
- 全フレームは正面向きの赤い円錐形、中央の一つ目、笑い口、桃色の舌、淡色の一本足、一足の下駄を維持する。
- キャンバス40×48 px、`anchorX = 20`、`baselineY = 45`、2倍整数表示、補間なし、透明を除き最大12色。
- フレーム数は `idle 1 + walk 4 + hush 1 + strong 2`。walkは全4枚で接地し、strongでも横長のopen傘や裏面へ変形しない。
- 紫、横顔、長い斜め柄／首、横へ流れる赤布、蛇状脚、巨大な横向き下駄を禁止する。
- reducer、playback、meter、resident、絵巻layout、他妖怪、Step 3、DSPには触れない。
- ImageGenのラスター出力を本番素材・縮小素材に使わない。本番正本は40×48 ASCII rows。
- 全8枚をcoherent familyとして評価し、walk4とstrong2は意味単位で修復・再レビューする。
- Draft PRを維持し、ユーザーの新画像承認までは `main` へmergeしない。

## File Map

- Modify: `YagyoPlayer/Views/KarakasaSprite.swift` — 承認パレットと参照忠実な8枚のASCII rows。
- Modify: `YagyoPlayerTests/PixelSpriteContractTests.swift` — 意味付きピクセル解析と構造契約。
- Create: `YagyoPlayerTests/KarakasaQAArtifactTests.swift` — contact sheet PNGとmotion-preview GIFのXCTest attachment。
- Modify: `docs/superpowers/specs/2026-07-11-yagyo-emaki-2-design.md` — 唐傘の色／strong表現を補足仕様へ委譲。
- Modify: `docs/superpowers/plans/2026-07-12-yagyo-emaki-2-karakasa-vertical-slice.md` — 旧視覚検証をsupersededとして記録。
- Replace: `docs/evidence/step4-karakasa/*` — 旧紫画像を新contact sheet、GIF、Simulator画像、READMEへ差し替える。

---

### Task 1: 参照忠実度の構造契約をREDで固定する

**Files:**
- Modify: `YagyoPlayerTests/PixelSpriteContractTests.swift`

**Interfaces:**
- Consumes: `KarakasaSpriteArt.palette`、`KarakasaSpriteArt.allDefinitions`、`PixelSpriteDefinition.rows`。
- Produces: test-only `PixelPoint`、`PixelBounds`、`points(in:symbols:yRange:)`、`bounds(of:)`、`componentCount(_:)`。

- [x] **Step 1: test-only解析helperを書く**

```swift
private struct PixelPoint: Hashable {
    let x: Int
    let y: Int
}

private struct PixelBounds: Equatable {
    let minX: Int
    let maxX: Int
    let minY: Int
    let maxY: Int

    var width: Int { maxX - minX + 1 }
    var height: Int { maxY - minY + 1 }
    var doubledCenterX: Int { minX + maxX }
}

private func points(
    in definition: PixelSpriteDefinition,
    symbols: Set<Character>,
    yRange: ClosedRange<Int>? = nil
) -> Set<PixelPoint> {
    Set(definition.rows.enumerated().flatMap { y, row in
        row.enumerated().compactMap { x, symbol in
            guard symbols.contains(symbol), yRange?.contains(y) ?? true else { return nil }
            return PixelPoint(x: x, y: y)
        }
    })
}

private func bounds(of points: Set<PixelPoint>) -> PixelBounds {
    PixelBounds(
        minX: points.map(\.x).min()!,
        maxX: points.map(\.x).max()!,
        minY: points.map(\.y).min()!,
        maxY: points.map(\.y).max()!
    )
}
```

`componentCount`は上下左右の4近傍BFSとし、指定された座標帯の同一symbol群だけを数える。production helperは追加しない。

```swift
private func componentCount(_ source: Set<PixelPoint>) -> Int {
    var remaining = source
    var count = 0
    while let start = remaining.first {
        count += 1
        var stack = [start]
        remaining.remove(start)
        while let point = stack.popLast() {
            let neighbors = [
                PixelPoint(x: point.x - 1, y: point.y),
                PixelPoint(x: point.x + 1, y: point.y),
                PixelPoint(x: point.x, y: point.y - 1),
                PixelPoint(x: point.x, y: point.y + 1),
            ]
            for neighbor in neighbors where remaining.remove(neighbor) != nil {
                stack.append(neighbor)
            }
        }
    }
    return count
}
```

- [x] **Step 2: 現行アートで失敗する参照契約testを書く**

```swift
func testKarakasaPaletteIsReferenceFaithfulAndContainsNoLegacyPurple() {
    let approved: Set<UInt32> = [
        0x24160f, 0x8e2f2d, 0xc94545, 0xe45c5e, 0xf37a76, 0xfff3da,
        0xf18da6, 0xc85f7e, 0xf5d7c5, 0x80512f, 0x4a2e1f, 0xd5a32c,
    ]
    let banned: Set<UInt32> = [0x6e5aa8, 0x3f315f, 0x9f88d1, 0x2b203d]
    XCTAssertEqual(Set(KarakasaSpriteArt.palette.values), approved)
    XCTAssertTrue(Set(KarakasaSpriteArt.palette.values).isDisjoint(with: banned))
}

func testEveryFrameKeepsTheRedFrontFacingCyclopsAndSingleLeg() {
    for frame in KarakasaSpriteArt.allDefinitions {
        let canopy = points(in: frame, symbols: ["R", "r", "c", "h"], yRange: 6...37)
        let canopyBounds = bounds(of: canopy)
        XCTAssertGreaterThanOrEqual(canopy.count, 260, frame.name)
        XCTAssertLessThanOrEqual(abs(canopyBounds.doubledCenterX - 39), 2, frame.name)
        XCTAssertGreaterThanOrEqual(
            Double(canopyBounds.height) / Double(canopyBounds.width),
            0.75,
            frame.name
        )

        let eyeWhite = points(in: frame, symbols: ["w"], yRange: 11...19)
        let pupil = points(in: frame, symbols: ["k"], yRange: 12...18)
        XCTAssertEqual(componentCount(eyeWhite), 1, frame.name)
        XCTAssertFalse(pupil.isEmpty, frame.name)
        XCTAssertLessThanOrEqual(abs(bounds(of: eyeWhite).doubledCenterX - 39), 2, frame.name)

        let leg = points(in: frame, symbols: ["l"], yRange: 32...44)
        XCTAssertEqual(componentCount(leg), 1, frame.name)
        XCTAssertLessThanOrEqual(abs(bounds(of: leg).doubledCenterX - 39), 2, frame.name)

        let geta = points(in: frame, symbols: ["b", "B", "g"], yRange: 41...45)
        XCTAssertTrue(geta.contains { $0.y == 45 }, frame.name)
        XCTAssertFalse(frame.rows[46].contains { $0 != "." }, frame.name)
        XCTAssertFalse(frame.rows[47].contains { $0 != "." }, frame.name)
    }
}
```

追加testで、walk4のcanopy中心差≤1 px・幅差合計≤2 px・下駄軸≤2 px、hushの下方移動≤2 px、strong anticipateの圧縮≤1 px、reactionの片側拡張≤2 pxをidle基準で検証する。

```swift
func testKarakasaAnimationPreservesTheRegisteredIdleGeometry() {
    let canopySymbols: Set<Character> = ["R", "r", "c", "h"]
    let idle = bounds(of: points(in: KarakasaSpriteArt.idle[0], symbols: canopySymbols))

    for walk in KarakasaSpriteArt.walk {
        let current = bounds(of: points(in: walk, symbols: canopySymbols))
        XCTAssertLessThanOrEqual(abs(current.doubledCenterX - idle.doubledCenterX), 2, walk.name)
        XCTAssertLessThanOrEqual(abs(current.width - idle.width), 2, walk.name)
        let geta = bounds(of: points(in: walk, symbols: ["b", "B", "g"], yRange: 41...45))
        XCTAssertLessThanOrEqual(abs(geta.doubledCenterX - 39), 4, walk.name)
    }

    let hush = bounds(of: points(in: KarakasaSpriteArt.hush[0], symbols: canopySymbols))
    XCTAssertTrue((0...2).contains(hush.minY - idle.minY))

    let anticipate = bounds(of: points(in: KarakasaSpriteArt.strong[0], symbols: canopySymbols))
    XCTAssertLessThanOrEqual(abs(anticipate.width - idle.width), 2)

    let reaction = bounds(of: points(in: KarakasaSpriteArt.strong[1], symbols: canopySymbols))
    XCTAssertGreaterThanOrEqual(reaction.minX, idle.minX - 2)
    XCTAssertLessThanOrEqual(reaction.maxX, idle.maxX + 2)
    XCTAssertLessThanOrEqual(abs(reaction.doubledCenterX - idle.doubledCenterX), 2)
}
```

- [x] **Step 3: Remote Desktopのlocal CodexでREDを確認する**

tests-only checkpointをfeature branchへ同期してから、local Codexはコードを編集せず次を実行する。

```bash
xcodegen generate
xcodebuild -project YagyoPlayer.xcodeproj -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -only-testing:YagyoPlayerTests/PixelSpriteContractTests test
```

Expected: 既存紫パレット、赤canopy不足、中心／一本足契約のいずれかでFAIL。test discoveryやcompile errorでの失敗はREDとして受け入れず修正する。

- [x] **Step 4: tests-only checkpointをコミットする**

```bash
git add YagyoPlayerTests/PixelSpriteContractTests.swift
git commit -m "test: reject off-model Karakasa frames"
```

---

### Task 2: 赤い正面唐傘のcoherent 8-frame familyを実装する

**Files:**
- Modify: `YagyoPlayer/Views/KarakasaSprite.swift`

**Interfaces:**
- Consumes: Task 1のpalette、symbol、座標帯、drift contract。
- Produces: `KarakasaSpriteArt.idle/walk/hush/strong/allDefinitions` の既存surfaceを維持した新しい8枚。

- [x] **Step 1: 承認パレットへ置換する**

```swift
static let palette: [Character: UInt32] = [
    "k": 0x24160f,
    "R": 0x8e2f2d, "r": 0xc94545, "c": 0xe45c5e, "h": 0xf37a76,
    "w": 0xfff3da,
    "p": 0xf18da6, "P": 0xc85f7e,
    "l": 0xf5d7c5,
    "b": 0x80512f, "B": 0x4a2e1f, "g": 0xd5a32c,
]
```

- [x] **Step 2: idleをcanonical registration frameとして描き直す**

40文字×48行を実データで書く。全体は概ね `x3...36/y1...45`、canopy `x3...36/y6...35`、cap `x15...24/y1...8`、eye `x16...23/y12...18`、mouth `x14...25/y18...21`、tongue `x17...22/y20...27`、leg `x18...21/y34...43`、geta `x16...23/y43...45`。赤い三角形を主面積とし、中央から裾への布の折りだけでSNES陰影を付ける。

- [x] **Step 3: walk4をidleから派生させる**

全4枚で下駄をy45へ接地。下駄軸±2 px、脚±1 px、裾と舌の遅れ1 pxだけでcontact→push→cross→settleを作る。顔・cap・canopy中心を±1 px以内に保ち、4枚を一組でself-reviewする。

- [x] **Step 4: hush1とstrong2をidleから派生させる**

hushはbodyを最大2 px下げ、脚を2〜3 px畳み、舌を2 px収納、上瞼を1 px下げる。strong anticipateは最大1 px圧縮、reactionは裾を片側最大2 px張り、目と舌を1〜2 px強調する。横長open、傘裏面、横顔は禁止。

- [x] **Step 5: focused testをGREENにする**

Remote Desktopのlocal CodexでTask 1と同じcommandを実行する。Expected: `PixelSpriteContractTests` PASS。実装subagentは結果を受けて8枚をfamily単位で修正する。

- [x] **Step 6: sprite replacementをコミットする**

```bash
git add YagyoPlayer/Views/KarakasaSprite.swift
git commit -m "fix: redraw Karakasa from the approved reference"
```

---

### Task 3: contact sheetとmotion previewを同じASCIIから生成する

**Files:**
- Create: `YagyoPlayerTests/KarakasaQAArtifactTests.swift`

**Interfaces:**
- Consumes: `KarakasaSpriteArt.allDefinitions` の順序 `idle + walk + hush + strong`。
- Produces: XCTest attachments `karakasa-contact-sheet.png` と `karakasa-motion-preview.gif`。

- [x] **Step 1: nearest-neighbor raster helperをtest targetへ書く**

`rows/palette`からRGBA bufferを作り、1 pixelを2×2へ整数複製する。contact sheetは8枚を状態順に横並びとし、生成途中の画像や別sourceを混在させない。

- [x] **Step 2: contact sheet testを追加する**

```swift
func testExportsReferenceFaithfulKarakasaContactSheet() throws {
    let data = try KarakasaQARenderer.contactSheet(
        definitions: KarakasaSpriteArt.allDefinitions,
        scale: 2,
        gap: 8
    )
    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
    attachment.name = "karakasa-contact-sheet.png"
    attachment.lifetime = .keepAlways
    add(attachment)
}
```

- [x] **Step 3: motion preview GIF testを追加する**

`idle, walk0...3, walk0...3, hush, hush, strong0, strong1, strong1, idle`をImageIOでGIF化する。walkは125 ms、idle/hushは300 ms、strong anticipateは70 ms、reactionは270 msを基準とし、nearest-neighborの2倍画像だけを使う。

- [x] **Step 4: artifact testを実行・抽出する**

```bash
xcodebuild -project YagyoPlayer.xcodeproj -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -only-testing:YagyoPlayerTests/KarakasaQAArtifactTests \
  -resultBundlePath /tmp/KarakasaQA.xcresult test
xcrun xcresulttool export attachments \
  --path /tmp/KarakasaQA.xcresult \
  --output-path /tmp/karakasa-qa-attachments
```

Expected: PNG/GIFが抽出され、テストPASS。Xcode版でexport構文が異なる場合は `xcresulttool help export attachments` を確認し、repoを編集せず正しい引数で再実行する。

- [x] **Step 5: 独立native art reviewを行う**

実作者ではないsubagentへ、参照JPEG、idle、contact sheet、GIFを渡す。輪郭、顔、比率、赤palette、中央軸、接地、walk cadence、hush、strong、size poppingを比較し、identity/style driftをBLOCKERとする。walkに指摘があれば4枚すべて、strongなら2枚すべてを再確認して修正し、同じreviewerが解消を確認する。

- [x] **Step 6: QA artifact supportをコミットする**

```bash
git add YagyoPlayerTests/KarakasaQAArtifactTests.swift
git commit -m "test: render coherent Karakasa QA artifacts"
```

---

### Task 4: Xcode・Simulator・証跡を再検証してDraft PRを更新する

**Files:**
- Modify: `docs/superpowers/specs/2026-07-11-yagyo-emaki-2-design.md`
- Modify: `docs/superpowers/plans/2026-07-12-yagyo-emaki-2-karakasa-vertical-slice.md`
- Modify: `docs/evidence/step4-karakasa/README.md`
- Replace/remove: `docs/evidence/step4-karakasa/*.png`
- Create: `docs/evidence/step4-karakasa/karakasa-contact-sheet.png`
- Create: `docs/evidence/step4-karakasa/karakasa-motion-preview.gif`

**Interfaces:**
- Consumes: review済み8-frame family、focused/full test結果、QA attachments、Simulator screenshots。
- Produces: rejected purple evidenceを含まないDraft PR上の新しい承認候補。

- [x] **Step 1: native final code/spec reviewを行う**

変更範囲がsprite、tests、docs/evidenceだけで、reducer/playback/layout/other yokaiに差分がないことを確認する。BLOCKER/MAJORを解消する。

- [x] **Step 2: Remote Desktopのlocal Codexで生成・build・testsを実行する**

```bash
xcodegen --version
xcodegen generate
xcodebuild -project YagyoPlayer.xcodeproj -scheme YagyoPlayer \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project YagyoPlayer.xcodeproj -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -only-testing:YagyoPlayerTests/PixelSpriteContractTests \
  -only-testing:YagyoPlayerTests/KarakasaQAArtifactTests test
xcodebuild -project YagyoPlayer.xcodeproj -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' test
```

Expected: BUILD SUCCEEDED、focused/full tests PASS、skip数を記録。生成順だけのpbxproj churnは戻さない。

- [x] **Step 3: semantic Simulator evidenceを取得する**

`-step4-parade-preview`で起動し、AX elementRefだけでNormal／Karakasa、Quiet／Karakasa、Strong／Karakasa、Strong／Karakasa／Ushimitsu、Strong／Karakasa／Reduce Motionを選択した。iPhone 17 Proはstate matrix 4 / 4とReduce Motion stability 1 / 1、最小幅iPhone 17eはdefault Normal + Karakasa 1 / 1で、すべてskip 0。座標推測tapは使用していない。Reduce Motionの`t0`／`t+2 s` full PNGは同一SHA-256で、canvas cropのdiffering bytesは0。

- [x] **Step 4: rejected evidenceを完全に差し替える**

旧紫画像を同じフォルダに承認候補として残さない。新contact sheet、GIF、Normal／Quiet／Strong／Strong + Ushimitsu／Strong + Reduce Motion `t0`／`t+2 s`／最小幅画像とREADMEだけを`docs/evidence/step4-karakasa/`の正本とする。READMEへ参照忠実度spec、semantic order、device、test結果、hash、QA状態、ユーザー承認待ちを記録する。

- [x] **Step 5: docsとDraft PR用ledgerを更新する**

parent specの旧「紫」と横長openを補足specへ委譲し、旧検証実績をsupersededとして明記した。Draft PR用の画像リンクとledgerを準備し、Draft、`main`未merge、ユーザー視覚承認待ちを維持した。GitHub上の最終同期はStep 7で確認した。

- [x] **Step 6: validation commitを作る**

```bash
git add README.md \
  docs/CHOREOGRAPHY.md \
  docs/DESIGN_NAV.md \
  docs/PRODUCT_DIRECTION.md \
  docs/superpowers/specs/2026-07-11-yagyo-emaki-2-design.md \
  docs/superpowers/plans/2026-07-12-yagyo-emaki-2-karakasa-vertical-slice.md \
  docs/superpowers/specs/2026-07-12-karakasa-reference-fidelity-redesign.md \
  docs/superpowers/plans/2026-07-12-karakasa-reference-fidelity-implementation.md \
  docs/evidence/step4-karakasa/README.md
git commit -m "docs: publish current Karakasa evidence"
```

Binary artifacts were generated from `d1eca866`; their GitHub path synchronization and link confirmation were completed in Step 7.

- [x] **Step 7: GitHub同期と最終確認**

feature branch `agent/step4-yagyo-emaki-2`だけを更新した。binary evidence commit `150219fea8a13ed95ea65885f5e7b46101cff9e5`で9 binary blobのSHA-256と画像link、旧5画像削除を確認。Draft PR #13は本文更新済み、`draft = true`、`merged = false`、base `main`。`main` SHA `256a45a8c9d9efb8db09970f3e40e6d1f5ef28fc`は不変。2名の独立native visual QAも全artifactをAPPROVEDした。最終handoffはユーザー本人の視覚承認要求で止め、`main`へmergeしない。

## Self-Review

- specの正面赤唐傘、8枚、座標、動作上限、Hatch Pet型QA、非目標をTasks 1–4で全てカバーした。
- production interfaceは変えず、test-only helper/artifact rendererだけを追加する。
- REDは旧紫アートに対する意味的failで確認し、compile/test discovery failureを許容しない。
- 未確定の穴埋め項目や、具体性のない実装指示は含めない。
- 実行方式はユーザー指定どおりSubagent-Driven Development。Remote Desktop Commanderは実装・レビューに使わない。
