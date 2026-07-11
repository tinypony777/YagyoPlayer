# 夜行絵巻 2.0 唐傘縦切り Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** SNES相当の唐傘基準体を、`averagePower`由来の正直な視覚信号、resident先導、Reduce Motion、VoiceOverへ縦切り接続し、feature branch上のSimulatorで承認可能にする。

**Architecture:** 既存の15 Hzメータリングと再生経路は維持し、純粋値型`ParadeSignalReducer`と表示専用`ParadeSignalCoordinator`を追加する。residentの互換割当と唐傘のピクセル定義を独立した純粋モデルにし、SwiftUI Canvasは単一の`ParadeSignalSnapshot`を読む。高頻度更新は小さなwrapper内へ閉じ、Playback TrustとライブラリUIを巻き込まない。

**Tech Stack:** Swift 6、SwiftUI Canvas、AVFoundation `AVAudioPlayer`、Combine `ObservableObject`、XCTest、XcodeGen、iOS 26+。

> **2026-07-12 supersession note:** 本planのreducer、resident、playback表示境界、Reduce Motion、VoiceOver等の実装履歴は有効だが、Task 3で制作した初期の紫色・横向き／長い柄・横に開く唐傘と、Task 7で得たそのスクリーンショットは不採用となった。唐傘アートの現行正本は [`2026-07-12-karakasa-reference-fidelity-redesign.md`](../specs/2026-07-12-karakasa-reference-fidelity-redesign.md)、実行手順は [`2026-07-12-karakasa-reference-fidelity-implementation.md`](./2026-07-12-karakasa-reference-fidelity-implementation.md) とする。互換性のため reducer phase `.open`、`strongOpen`、旧証跡ファイル名に含まれる `open` は維持してよいが、現行の見た目は横に開いた傘ではなく正面reactionである。

## 現在のアート候補（2026-07-12）

現在の40×48 px候補は、8枚すべてを一つの coherent frame family とし、正面向きの赤〜珊瑚色の円錐形、茶色の頭頂と金色の帯、中央の一つ目、曲線の笑い口、桃色の舌、淡色の一本足、一足の茶／金色の下駄を共有する。`idle 1 + walk 4 + hush 1 + strong 2` の接続は変えず、strongは正面形を保つ anticipate／reaction として描く。

- 旧アートを拒否する参照忠実度Task 1は、Xcode 27／iOS 27で意味的なREDを確認済み。
- 現在候補は、Xcode 27／iOS 27で構造テスト9件とQA artifactテスト2件の **11 / 11 focused QA GREEN**。同じソースからPNG contact sheetとGIF motion previewを抽出し、独立視覚QAも承認済み。
- 再設計Task 4はXcode 27.0 generic build、checked projectのfull suite **65 / 65**、Pro semantic AX **4 + 1**、17e default **1 / 1**（すべてskip 0）まで完了。Reduce Motionの`t0`／`t+2 s` full PNGは同一でcanvas crop差分0。[現在の証跡ledger](../../evidence/step4-karakasa/README.md)を正本とする。
- contact sheet／GIFの独立native QAはAPPROVED。Simulator画像の最終native目視QA、GitHub同期の最終確認、ユーザー見た目承認は未完了。このplan末尾の旧full-suite／Simulator結果を現在候補へ流用しない。
- Draft PRを維持し、`main`へmergeしない。唐傘だけが新画風のmixed-art状態であり、残りの妖怪はユーザーの唐傘承認後に別frame matrixを提示し、別承認を得るまで制作しない。

## Global Constraints

- Step 3、Core AI、Music Understanding、DSP、FFT、PCM tap、`AVAudioEngine`、FFmpegは使用しない。
- 再生音、Audio Session、Remote Command、Now Playing、統計の記録条件を変更しない。
- 技術語は`quietProxy`／静音近似、`strongRiseProxy`／強い音量上昇近似とし、拍・アタック・デジタル無音・サビ・曲構成を検出したと書かない。
- 唐傘は40×48 px、2倍整数表示、透明を除き最大12色、共通baseline、`idle 1 + walk 4 + hush 1 + strong 2`の8フレームとする。
- 現行唐傘は全フレームで正面向きの赤〜珊瑚色の円錐形、茶色の頭頂／金帯、一つ目／笑い口／桃色の舌、淡色の一本足／一足の下駄を保持する。紫、横顔、長い柄、横に開いた傘や裏面は不採用で再導入しない。
- resident互換rosterは`[oni, mokugyo, kasa, kappa, kitsune, tengu, yuki, biwa]`から並べ替えない。
- `playCount / lastPlayedAt / playHourCounts`をアンロック、ランク、色強度、収集UIへ使わない。
- Reduce Motionでは位置、scale、位相、フレーム循環を止めても、音量帯、strong、residentの意味を形とVoiceOverで残す。
- 唐傘だけがSNES画風の混在状態はfeature branchとDraft PRに留め、`main`へ統合しない。
- 実装とレビューはネイティブのcollaboration subagentが行う。Remote Desktop Commander経由のローカルCodexはXcodeGen、build、test、Simulator操作だけを行う。
- 各実装taskは、実装担当とは別のspec-review subagentとcode-quality-review subagentの承認を得る。

---

## File Map

### Create

- `YagyoPlayer/Models/ParadeSignal.swift` — 視覚信号の入力、設定、snapshot、純粋reducer。
- `YagyoPlayer/Models/YokaiResidency.swift` — UUID互換割当とresident先導順。
- `YagyoPlayer/Services/ParadeSignalCoordinator.swift` — 15 Hz入力をreducerへ渡す表示専用publisher。
- `YagyoPlayer/Views/KarakasaSprite.swift` — 40×48の唐傘8フレームと限定パレット。
- `YagyoPlayer/Views/ParadePreviewHarness.swift` — `DEBUG`限定のSimulator検証画面。
- `YagyoPlayerTests/ParadeSignalReducerTests.swift` — 時系列、ヒステリシス、strong再武装、異常値。
- `YagyoPlayerTests/YokaiResidencyTests.swift` — 既存割当互換、固定roster、重複なし先導順。
- `YagyoPlayerTests/PixelSpriteContractTests.swift` — 40×48、8状態、色数、anchor、baseline。
- `YagyoPlayerTests/ParadeSignalCoordinatorTests.swift` — publishとresetの表示層境界。
- `docs/CHOREOGRAPHY.md` — 正式な翻訳帳。

### Modify

- `YagyoPlayer/Views/PixelSprites.swift` — 検証可能な`PixelSpriteDefinition`、意味付き唐傘frame、ID lookup。
- `YagyoPlayer/Services/PlaybackController.swift` — coordinatorへの15 Hz入力と意味上のreset hook。再生処理は不変。
- `YagyoPlayer/Views/YagyoParadeView.swift` — snapshot、resident順、唐傘frame、静止代替。
- `YagyoPlayer/Views/ContentView.swift` — 高頻度signalを小さな`@ObservedObject` wrapperへ隔離。
- `YagyoPlayer/Views/VisualComponents.swift` — Reduce Motion時の円形波形位相固定。
- `YagyoPlayer/YagyoPlayerApp.swift` — `DEBUG` launch argumentでpreview harnessを表示。
- `YagyoPlayerTests/PlaybackControllerTests.swift` — pause、seek、load failure、track changeのvisual reset回帰。
- `docs/PRODUCT_DIRECTION.md` — Step 3保留、Step 4の正直な目的、統計の現在地。
- `docs/DESIGN_NAV.md` — 唐傘基準体先行と実装現在地。
- `README.md` — 固定疑似ビートという古い説明を翻訳帳へ合わせる。
- `YagyoPlayer.xcodeproj/project.pbxproj` — Mac上の`xcodegen generate`による機械生成差分のみ。
- `docs/superpowers/plans/2026-07-12-yagyo-emaki-2-karakasa-vertical-slice.md` — 完了checkboxと検証結果。

---

### Task 1: 純粋な視覚信号reducer

**Files:**
- Create: `YagyoPlayer/Models/ParadeSignal.swift`
- Create: `YagyoPlayerTests/ParadeSignalReducerTests.swift`

**Interfaces:**
- Consumes: 15 Hzで得た`Double?` level、`isPlaying`、単調増加する`TimeInterval`。
- Produces: `ParadeSignalConfiguration.production`、`ParadeSignalInput`、`ParadeSignalSnapshot`、`ParadeSignalReducer.ingest(_:)`、`ParadeSignalReducer.reset(isPlaying:)`。

- [x] **Step 1: reducerの失敗テストを書く**

`ParadeSignalReducerTests.swift`に次の表面を固定する。

```swift
import XCTest
@testable import YagyoPlayer

final class ParadeSignalReducerTests: XCTestCase {
    private let configuration = ParadeSignalConfiguration.production

    private func input(_ time: TimeInterval, _ level: Double?, playing: Bool = true) -> ParadeSignalInput {
        ParadeSignalInput(isPlaying: playing, level: level, sampledAt: time)
    }

    func testStoppedUnavailableAndFiniteClampingAreDistinct() {
        var reducer = ParadeSignalReducer(configuration: configuration)
        XCTAssertEqual(reducer.ingest(input(0, 0.5, playing: false)).activity, .stopped)
        XCTAssertEqual(reducer.ingest(input(1, nil)).activity, .unavailable)
        XCTAssertEqual(reducer.ingest(input(2, .nan)).activity, .unavailable)
        XCTAssertEqual(reducer.ingest(input(3, 2)).level, 1)
        XCTAssertEqual(reducer.ingest(input(4, -1)).level, 0)
    }

    func testQuietRequiresDwellAndExitsWithHysteresis() {
        var reducer = ParadeSignalReducer(configuration: configuration)
        _ = reducer.ingest(input(0, 0.05))
        _ = reducer.ingest(input(0.35, 0.05))
        XCTAssertEqual(reducer.ingest(input(0.69, 0.05)).activity, .normal)
        XCTAssertEqual(reducer.ingest(input(0.70, 0.05)).activity, .quietProxy)
        XCTAssertEqual(reducer.ingest(input(0.80, 0.10)).activity, .quietProxy)
        XCTAssertEqual(reducer.ingest(input(0.90, 0.14)).activity, .normal)
    }

    func testLoudStartSeedsBaselineWithoutStrongRise() {
        var reducer = ParadeSignalReducer(configuration: configuration)
        XCTAssertEqual(reducer.ingest(input(0, 0.90)).strongPhase, .inactive)
        XCTAssertEqual(reducer.ingest(input(0.31, 0.90)).strongPhase, .inactive)
        XCTAssertEqual(reducer.snapshot.strongSequence, 0)
    }

    func testStrongRiseFiresOnceMovesThroughPhasesAndRequiresRearm() {
        var reducer = ParadeSignalReducer(configuration: configuration)
        _ = reducer.ingest(input(0, 0.20))
        _ = reducer.ingest(input(0.31, 0.20))
        XCTAssertEqual(reducer.ingest(input(0.40, 0.80)).strongPhase, .anticipate)
        XCTAssertEqual(reducer.ingest(input(0.48, 0.80)).strongPhase, .open)
        XCTAssertEqual(reducer.ingest(input(0.75, 0.80)).strongPhase, .recover)
        XCTAssertEqual(reducer.ingest(input(1.00, 0.80)).strongPhase, .inactive)
        XCTAssertEqual(reducer.snapshot.strongSequence, 1)
        _ = reducer.ingest(input(1.10, 0.20))
        XCTAssertEqual(reducer.ingest(input(1.20, 0.80)).strongSequence, 2)
    }

    func testLargeOrBackwardSampleGapReseedsWithoutStrongRise() {
        var reducer = ParadeSignalReducer(configuration: configuration)
        _ = reducer.ingest(input(1.0, 0.10))
        XCTAssertEqual(reducer.ingest(input(2.0, 0.90)).strongSequence, 0)
        XCTAssertEqual(reducer.ingest(input(1.5, 0.90)).strongSequence, 0)
    }
}
```

- [x] **Step 2: MacのローカルCodexで失敗を確認する**

Run in repository root:

```bash
xcodegen generate
xcodebuild -project YagyoPlayer.xcodeproj -scheme YagyoPlayer -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' -only-testing:YagyoPlayerTests/ParadeSignalReducerTests test
```

Expected: FAIL because the `ParadeSignal*` types do not exist.

- [x] **Step 3: 最小の純粋reducerを実装する**

`ParadeSignal.swift`のpublic-to-module surfaceを次で固定する。

```swift
import Foundation

struct ParadeSignalConfiguration: Equatable, Sendable {
    let quietEnterLevel: Double
    let quietExitLevel: Double
    let quietDwell: TimeInterval
    let strongMinimumLevel: Double
    let strongBaselineDelta: Double
    let baselineTimeConstant: TimeInterval
    let strongCooldown: TimeInterval
    let strongRearmLevel: Double
    let strongRearmDelta: Double
    let anticipateDuration: TimeInterval
    let openDuration: TimeInterval
    let recoverDuration: TimeInterval
    let warmupDuration: TimeInterval
    let maximumSampleGap: TimeInterval

    static let production = Self(
        quietEnterLevel: 0.08, quietExitLevel: 0.14, quietDwell: 0.70,
        strongMinimumLevel: 0.55, strongBaselineDelta: 0.18,
        baselineTimeConstant: 0.80, strongCooldown: 0.45,
        strongRearmLevel: 0.32, strongRearmDelta: 0.06,
        anticipateDuration: 0.07, openDuration: 0.27,
        recoverDuration: 0.20, warmupDuration: 0.30,
        maximumSampleGap: 0.50
    )
}

struct ParadeSignalInput: Equatable, Sendable {
    let isPlaying: Bool
    let level: Double?
    let sampledAt: TimeInterval
}

struct ParadeSignalSnapshot: Equatable, Sendable {
    enum Activity: Equatable, Sendable { case stopped, unavailable, quietProxy, normal }
    enum StrongPhase: Equatable, Sendable { case inactive, anticipate, open, recover }

    fileprivate(set) var level: Double = 0
    fileprivate(set) var activity: Activity = .stopped
    fileprivate(set) var strongPhase: StrongPhase = .inactive
    fileprivate(set) var strongSequence: UInt64 = 0
}

struct ParadeSignalReducer: Sendable {
    let configuration: ParadeSignalConfiguration
    private(set) var snapshot = ParadeSignalSnapshot()

    private var baseline: Double?
    private var lastSampleAt: TimeInterval?
    private var quietCandidateAt: TimeInterval?
    private var warmupUntil: TimeInterval?
    private var strongStartedAt: TimeInterval?
    private var lastStrongAt: TimeInterval?
    private var strongArmed = false

    init(configuration: ParadeSignalConfiguration = .production) {
        self.configuration = configuration
    }

    mutating func ingest(_ input: ParadeSignalInput) -> ParadeSignalSnapshot
    mutating func reset(isPlaying: Bool) -> ParadeSignalSnapshot
}
```

`ingest`はこの順序で実装する。

1. `isPlaying == false`なら時間状態を消し、`.stopped`、level 0、strong inactiveを返す。sequenceだけは保持する。
2. levelが`nil`または非有限なら時間状態を消し、`.unavailable`、strong inactiveを返す。
3. 有限levelを`0...1`へclampする。
4. 初回、時刻逆行、`dt > 0.50`では`baseline = level`、`strongArmed = false`、`warmupUntil = now + 0.30`としてseedし、そのsampleでstrongを出さない。seedしたlevelが`<= 0.08`なら同じ時刻からquiet候補の計時は開始する。
5. quiet候補を`level <= 0.08`から計時し、0.70秒で`.quietProxy`へ入れる。quiet中は`level >= 0.14`だけで`.normal`へ戻す。
6. strong判定前のbaselineとの差を使う。`alpha = 1 - exp(-dt / 0.80)`、`baseline += alpha * (level - baseline)`で判定後に更新する。
7. warmupと0.45秒cooldownを終え、`level <= 0.32`または差`<= 0.06`を一度満たしたときだけ再武装する。
8. 武装中に`level >= 0.55`かつ差`>= 0.18`ならsequenceを1増やし、0.07秒anticipate、続く0.27秒open、続く0.20秒recoverを時刻から選ぶ。一定大音量では再発火しない。

- [x] **Step 4: reducer testsを通す**

Run the Task 1 command again. Expected: `ParadeSignalReducerTests` PASS.

- [x] **Step 5: Task 1をコミットする**

```bash
git add YagyoPlayer/Models/ParadeSignal.swift YagyoPlayerTests/ParadeSignalReducerTests.swift YagyoPlayer.xcodeproj/project.pbxproj
git commit -m "feat: add deterministic parade signal reducer"
```

---

### Task 2: 安定したresident割当と先導順

**Files:**
- Create: `YagyoPlayer/Models/YokaiResidency.swift`
- Create: `YagyoPlayerTests/YokaiResidencyTests.swift`
- Modify: `YagyoPlayer/Views/PixelSprites.swift`

**Interfaces:**
- Consumes: `AudioTrack.ID`、固定sprite ID roster。
- Produces: `YokaiResidency.spriteID(for:)`、`YokaiResidency.processionIDs(residentID:isUshimitsu:)`、`YokaiGallery.sprite(withID:)`。

- [x] **Step 1: 互換割当と重複なし先導順の失敗テストを書く**

```swift
import XCTest
@testable import YagyoPlayer

final class YokaiResidencyTests: XCTestCase {
    func testRosterOrderIsACompatibilityContract() {
        XCTAssertEqual(
            YokaiResidency.stableSpriteIDs,
            ["oni", "mokugyo", "kasa", "kappa", "kitsune", "tengu", "yuki", "biwa"]
        )
    }

    func testKnownLegacyUUIDStillMapsToYuki() throws {
        let id = try XCTUnwrap(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        XCTAssertEqual(YokaiResidency.spriteID(for: id), "yuki")
    }

    func testResidentLeadsWithoutDuplication() {
        let ids = YokaiResidency.processionIDs(residentID: "kasa", isUshimitsu: false)
        XCTAssertEqual(ids.first, "kasa")
        XCTAssertEqual(ids.count, 8)
        XCTAssertEqual(Set(ids).count, 8)
        XCTAssertEqual(Array(ids.dropFirst()), ["oni", "mokugyo", "kappa", "kitsune", "tengu", "yuki", "biwa"])
    }

    func testUnknownResidentFallsBackAndUshimitsuAppendsHitotsume() {
        XCTAssertEqual(
            YokaiResidency.processionIDs(residentID: "unknown", isUshimitsu: true),
            YokaiResidency.stableSpriteIDs + ["hitotsume"]
        )
    }
}
```

- [x] **Step 2: Macで失敗を確認する**

Run `xcodegen generate`, then the Task 1 test command with `-only-testing:YagyoPlayerTests/YokaiResidencyTests`. Expected: missing `YokaiResidency` failures.

- [x] **Step 3: 固定IDモデルを実装する**

```swift
import Foundation

enum YokaiResidency {
    static let stableSpriteIDs = [
        "oni", "mokugyo", "kasa", "kappa", "kitsune", "tengu", "yuki", "biwa"
    ]

    static func spriteID(for trackID: UUID) -> String {
        let sum = trackID.uuidString.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return stableSpriteIDs[sum % stableSpriteIDs.count]
    }

    static func processionIDs(residentID: String?, isUshimitsu: Bool) -> [String] {
        var ids: [String]
        if let residentID, stableSpriteIDs.contains(residentID) {
            ids = [residentID] + stableSpriteIDs.filter { $0 != residentID }
        } else {
            ids = stableSpriteIDs
        }
        if isUshimitsu { ids.append("hitotsume") }
        return ids
    }
}
```

`PixelSprites.swift`では`YokaiGallery.parade`の並びを維持し、次を追加する。

```swift
static func sprite(withID id: String) -> YokaiSprite? {
    if id == hitotsume.id { return hitotsume }
    return parade.first { $0.id == id }
}

static func sprite(for id: UUID) -> YokaiSprite {
    sprite(withID: YokaiResidency.spriteID(for: id)) ?? parade[0]
}
```

- [x] **Step 4: resident testsと既存library testsを通す**

```bash
xcodebuild -project YagyoPlayer.xcodeproj -scheme YagyoPlayer -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' -only-testing:YagyoPlayerTests/YokaiResidencyTests -only-testing:YagyoPlayerTests/AudioLibraryStoreTests test
```

Expected: PASS。既存trackのresident表示が変わらない。

- [x] **Step 5: Task 2をコミットする**

```bash
git add YagyoPlayer/Models/YokaiResidency.swift YagyoPlayer/Views/PixelSprites.swift YagyoPlayerTests/YokaiResidencyTests.swift YagyoPlayer.xcodeproj/project.pbxproj
git commit -m "feat: stabilize resident yokai ordering"
```

---

### Task 3: 検証可能な唐傘SNES基準体（初期アート実装の履歴・造形はsuperseded）

> このTaskの型、40×48 contract、8フレーム接続の実装履歴は保持する。一方、下記Step 4の紫パレット、閉じた横向きシルエット、柄、横に開いた傘骨という造形指示と、その採用結果はユーザー確認で不採用となった。現在の造形判断には参照忠実度再設計spec／planだけを使用する。

**Files:**
- Create: `YagyoPlayer/Views/KarakasaSprite.swift`
- Create: `YagyoPlayerTests/PixelSpriteContractTests.swift`
- Modify: `YagyoPlayer/Views/PixelSprites.swift`

**Interfaces:**
- Consumes: 1文字=1ドットのASCII rowsと`[Character: UInt32]` palette。
- Produces: `PixelSpriteDefinition`、`KarakasaSpriteArt.idle/walk/hush/strong`、意味付き`YokaiSprite` frame accessors。

- [x] **Step 1: pixel source contractの失敗テストを書く**

`PixelSpriteDefinition`は`name / rows / palette / anchorX / baselineY`を保持する前提で、次を検証する。

```swift
import XCTest
@testable import YagyoPlayer

final class PixelSpriteContractTests: XCTestCase {
    func testKarakasaHasExactlyEightSemanticFrames() {
        XCTAssertEqual(KarakasaSpriteArt.idle.count, 1)
        XCTAssertEqual(KarakasaSpriteArt.walk.count, 4)
        XCTAssertEqual(KarakasaSpriteArt.hush.count, 1)
        XCTAssertEqual(KarakasaSpriteArt.strong.count, 2)
    }

    func testEveryKarakasaFrameUsesTheSharedCanvasPaletteAndGroundAnchor() {
        for definition in KarakasaSpriteArt.allDefinitions {
            XCTAssertEqual(definition.rows.count, 48, definition.name)
            XCTAssertTrue(definition.rows.allSatisfy { $0.utf8.count == 40 }, definition.name)
            XCTAssertEqual(definition.anchorX, 20, definition.name)
            XCTAssertEqual(definition.baselineY, 45, definition.name)
            XCTAssertLessThanOrEqual(definition.usedColorCount, 12, definition.name)
            XCTAssertTrue(definition.unknownSymbols.isEmpty, definition.name)
            XCTAssertTrue(definition.hasTransparentTopAndSideMargins, definition.name)
            XCTAssertLessThanOrEqual(definition.lowestOpaqueY, definition.baselineY, definition.name)
        }
    }

    func testRenderedKarakasaFramesStayFortyByFortyEight() {
        for frame in KarakasaSpriteArt.allDefinitions.map({ PixelArt.frame($0) }) {
            XCTAssertEqual(frame.pixelWidth, 40)
            XCTAssertEqual(frame.pixelHeight, 48)
        }
    }
}
```

- [x] **Step 2: Macで失敗を確認する**

Run `xcodegen generate` and only `PixelSpriteContractTests`. Expected: missing contract and art types.

- [x] **Step 3: `PixelSpriteDefinition`と厳格rendererを実装する**

`PixelSprites.swift`へ次の値型を追加し、未定義記号を黙って透明化しない。

```swift
struct PixelSpriteDefinition: Sendable {
    let name: String
    let rows: [String]
    let palette: [Character: UInt32]
    let anchorX: Int
    let baselineY: Int

    var usedSymbols: Set<Character> {
        Set(rows.joined()).subtracting(["."])
    }
    var unknownSymbols: Set<Character> { usedSymbols.subtracting(palette.keys) }
    var usedColorCount: Int { Set(usedSymbols.compactMap { palette[$0] }).count }
    var lowestOpaqueY: Int {
        rows.indices.last { rows[$0].contains { $0 != "." } } ?? -1
    }
    var hasTransparentTopAndSideMargins: Bool {
        guard rows.first?.allSatisfy({ $0 == "." }) == true else { return false }
        return rows.allSatisfy { $0.first == "." && $0.last == "." }
    }
}
```

`PixelArt.frame(_ definition:)`はwidth 40、height 48、unknownSymbols emptyを`precondition`し、既存CGImage生成へ渡す。既存`frame(rows:palette:)`は既存妖怪用に残す。

- [x] **Step 4: 唐傘8フレームを二案作り、独立アートレビューで一案へ絞る（superseded historical step）**

2体のネイティブsubagentへ同じ契約を渡し、別々に`KarakasaSpriteArt`のASCII rowsを提案させる。両者とも次の共通paletteを使う。

```swift
static let palette: [Character: UInt32] = [
    "k": 0x14101c, "w": 0xf7ecd9,
    "p": 0x6e5aa8, "P": 0x3f315f, "v": 0x9f88d1, "V": 0x2b203d,
    "r": 0xd9503a, "R": 0x7c241c,
    "t": 0xcaa46a, "T": 0x76522f,
    "s": 0xf0a63c, "S": 0x8a4f20
]
```

各案は40文字×48行を8枚すべて実データで提出する。idleは閉じた傘、一つ目、舌、柄、一本足が読めること。walkは足だけでなく柄・舌・傘布の慣性を4相でずらすこと。hushはbaselineを変えず低いシルエットにすること。strongは予備動作と開いた傘骨を使い、40 px内で切らないこと。第三のネイティブreview subagentがシルエット、民話的な唐傘らしさ、フレーム連続性、既存paletteとの調和を比較し、採用案または明示的な合成修正を返す。採用データだけを`KarakasaSprite.swift`へ書く。

上のpaletteと造形文は初期制作時の履歴であり、現行候補へ適用しない。現行候補は紫と柄を持たず、赤〜珊瑚色の正面円錐形と中央の顔、一本足／一足の下駄を全8枚で維持し、strongでも正面reactionに留める。

- [x] **Step 5: 意味付きframeを`YokaiSprite`へ接続する**

既存initializerを壊さず、次をdefault付きで追加する。

```swift
let idleFrame: SpriteFrame?
let hushFrame: SpriteFrame?
let strongFrames: [SpriteFrame]

var resolvedIdleFrame: SpriteFrame { idleFrame ?? frames[0] }
var resolvedHushFrame: SpriteFrame { hushFrame ?? resolvedIdleFrame }
```

唐傘だけは`frames = KarakasaSpriteArt.walk.map { PixelArt.frame($0) }`、`idleFrame = PixelArt.frame(KarakasaSpriteArt.idle[0])`、`hushFrame = PixelArt.frame(KarakasaSpriteArt.hush[0])`、`strongFrames = KarakasaSpriteArt.strong.map { PixelArt.frame($0) }`を渡す。legacy `hitFrame`には互換名`strongOpen`のframeを渡すが、現行アート上は正面reactionである。他妖怪はdefault fallbackを使う。

- [x] **Step 6: pixel contract testsを通す**

Run only `PixelSpriteContractTests`. Expected: 8 frames pass every dimension/palette/anchor assertion.

- [x] **Step 7: Task 3をコミットする**

```bash
git add YagyoPlayer/Views/KarakasaSprite.swift YagyoPlayer/Views/PixelSprites.swift YagyoPlayerTests/PixelSpriteContractTests.swift YagyoPlayer.xcodeproj/project.pbxproj
git commit -m "feat: add SNES-grade karakasa reference sprite"
```

---

### Task 4: 15 Hz coordinatorとPlaybackController reset境界

**Files:**
- Create: `YagyoPlayer/Services/ParadeSignalCoordinator.swift`
- Create: `YagyoPlayerTests/ParadeSignalCoordinatorTests.swift`
- Modify: `YagyoPlayer/Services/PlaybackController.swift`
- Modify: `YagyoPlayerTests/PlaybackControllerTests.swift`

**Interfaces:**
- Consumes: Task 1のreducer、既存`updateMeter()`の平滑化済みlevel。
- Produces: `PlaybackController.paradeSignals`、読み取り互換`audioLevel`、明示reset hook。

- [x] **Step 1: coordinatorとPlayback resetの失敗テストを書く**

```swift
import XCTest
@testable import YagyoPlayer

@MainActor
final class ParadeSignalCoordinatorTests: XCTestCase {
    func testIngestPublishesReducerSnapshot() {
        let coordinator = ParadeSignalCoordinator()
        coordinator.ingest(level: 0.2, isPlaying: true, sampledAt: 0)
        XCTAssertEqual(coordinator.snapshot.activity, .normal)
        XCTAssertEqual(coordinator.snapshot.level, 0.2)
    }

    func testUnavailableAndSemanticResetDoNotMasqueradeAsQuiet() {
        let coordinator = ParadeSignalCoordinator()
        coordinator.ingest(level: nil, isPlaying: true, sampledAt: 0)
        XCTAssertEqual(coordinator.snapshot.activity, .unavailable)
        coordinator.reset(reason: .seek, isPlaying: true)
        XCTAssertEqual(coordinator.snapshot.activity, .unavailable)
        coordinator.reset(reason: .pause, isPlaying: false)
        XCTAssertEqual(coordinator.snapshot.activity, .stopped)
    }
}
```

`PlaybackControllerTests`へ、missing file load後、`pause()`後、loaded playerの`seek()`後に`paradeSignals.snapshot`がstrongを保持しない回帰を追加する。audio環境が必要なtestだけは既存方針どおり`XCTSkipUnless`を使う。

- [x] **Step 2: Macで失敗を確認する**

Run coordinator tests and PlaybackControllerTests. Expected: missing coordinator/reset APIs.

- [x] **Step 3: coordinatorを実装する**

```swift
import Combine
import Foundation

enum ParadeSignalResetReason: Sendable {
    case trackLoadStarted, loadFailure, playFailure, pause, seek, stop
}

@MainActor
final class ParadeSignalCoordinator: ObservableObject {
    @Published private(set) var snapshot = ParadeSignalSnapshot()
    private var reducer = ParadeSignalReducer()

    func ingest(level: Double?, isPlaying: Bool, sampledAt: TimeInterval) {
        snapshot = reducer.ingest(
            ParadeSignalInput(isPlaying: isPlaying, level: level, sampledAt: sampledAt)
        )
    }

    func reset(reason _: ParadeSignalResetReason, isPlaying: Bool) {
        snapshot = reducer.reset(isPlaying: isPlaying)
    }
}
```

- [x] **Step 4: PlaybackControllerを最小配線する**

- `@Published private(set) var audioLevel`を削除し、`let paradeSignals = ParadeSignalCoordinator()`、`private var smoothedAudioLevel = 0.0`、`var audioLevel: Double { paradeSignals.snapshot.level }`へ置換する。
- `updateMeter()`の既存normalizeと0.65/0.18平滑化係数は変えず、`smoothedAudioLevel`を更新して`paradeSignals.ingest(... sampledAt: ProcessInfo.processInfo.systemUptime)`へ渡す。
- channelなし、非有限meter、playerなしで再生中なら`level: nil`をingestする。
- `stopMetering()`はTimer invalidateだけを行い、reducerをresetしない。`startMetering()`が`stopMetering()`を呼ぶ現行構造を維持するためである。
- `resetParadeSignal(reason:isPlaying:)`を別に作り、平滑化値を0へ戻してcoordinatorをresetする。第二引数は省略不可とし、呼び出し地点の意味を明示する。
- reset hookは`load`入口を`isPlaying: false`、load catchの最終`.loadFailure`をfalse、play失敗をfalse、`pause()`をfalse、`seek()`の時刻変更前を現在の`isPlaying`、`stopForDeletedTrack()`をfalseとして置く。next/previous/完走は`load()`経由で網羅する。`transitionToPausedStateAfterLoad()`では二重resetしない。

- [x] **Step 5: coordinator、Playback、全既存testを通す**

```bash
xcodebuild -project YagyoPlayer.xcodeproj -scheme YagyoPlayer -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' -only-testing:YagyoPlayerTests/ParadeSignalCoordinatorTests -only-testing:YagyoPlayerTests/PlaybackControllerTests test
```

Expected: PASS。割り込みとroute changeは既存`pause()`経路のまま。

- [x] **Step 6: Task 4をコミットする**

```bash
git add YagyoPlayer/Services/ParadeSignalCoordinator.swift YagyoPlayer/Services/PlaybackController.swift YagyoPlayerTests/ParadeSignalCoordinatorTests.swift YagyoPlayerTests/PlaybackControllerTests.swift YagyoPlayer.xcodeproj/project.pbxproj
git commit -m "feat: connect parade signals without changing playback"
```

---

### Task 5: Canvas振付、Reduce Motion、VoiceOver、preview harness

**Files:**
- Modify: `YagyoPlayer/Views/YagyoParadeView.swift`
- Modify: `YagyoPlayer/Views/ContentView.swift`
- Modify: `YagyoPlayer/Views/VisualComponents.swift`
- Create: `YagyoPlayer/Views/ParadePreviewHarness.swift`
- Modify: `YagyoPlayer/YagyoPlayerApp.swift`

**Interfaces:**
- Consumes: `ParadeSignalSnapshot`、`YokaiResidency`、Task 3の意味付きframes。
- Produces: snapshot駆動の絵巻、resident marker、Reduce Motion静止代替、`-step4-parade-preview` debug surface。

- [x] **Step 1: 描画前のpure presentation helper testsをTask 1 testへ追加する**

`ParadeSignalSnapshot`へ次のcomputed propertiesを実装対象として失敗testを書く。

```swift
XCTAssertEqual(ParadeSignalSnapshot.preview(activity: .quietProxy).levelBand, .low)
XCTAssertEqual(
    ParadeSignalSnapshot.preview(activity: .quietProxy)
        .accessibilityValue(residentName: "唐傘", isUshimitsu: false),
    "再生中、音量は低め、先導は唐傘"
)
XCTAssertEqual(
    ParadeSignalSnapshot.preview(activity: .unavailable)
        .accessibilityValue(residentName: "河童", isUshimitsu: true),
    "再生中、音量表示を利用できません、先導は河童、丑三つ時"
)
XCTAssertEqual(
    ParadeSignalSnapshot.preview(activity: .normal, strongPhase: .open)
        .accessibilityValue(residentName: "天狗", isUshimitsu: false),
    "再生中、音量が強く上昇、先導は天狗"
)
```

`preview(activity:level:strongPhase:strongSequence:)` factoryは`internal`とし、本番state mutationには使わない。level省略時はstopped/unavailableが0、quietが0.05、normalが0.5を使う。strongPhaseとsequenceのdefaultはinactiveと0。`levelBand`は`.unavailable / .low / .medium / .high`、有限levelの境界は`0.20`と`0.65`に固定する。

- [x] **Step 2: `YagyoParadeView`をsnapshotとresident ID入力へ変える**

signatureを次に置換する。

```swift
struct YagyoParadeView: View {
    var signal: ParadeSignalSnapshot
    var residentSpriteID: String?
    var isUshimitsu: Bool
    var onMoonTap: () -> Void
}
```

描画規則を次へ固定する。

- walker IDsは`YokaiResidency.processionIDs(residentID:isUshimitsu:)`で作り、`YokaiGallery.sprite(withID:)`で解決する。
- stoppedまたはReduce Motionなら速度0。quietは14 pt/s、normalとunavailableは46 pt/s。
- 固定サイン波×levelの`react`を削除する。normal bobは固定行進周期で最大`1.3 + level * 0.5` px、quietは0.4 px、stopped/Reduce Motionは0。
- stoppedは`resolvedIdleFrame`、quietは`resolvedHushFrame`、normalは4 fpsのwalk frameを使う。
- 唐傘はstrong anticipate/open/recoverという互換phaseを`strongFrames[0] / strongFrames[1] / resolvedIdleFrame`へ対応させる。`strongFrames[1]`の現行視覚は横に開いた傘ではなく正面reactionである。
- 木魚のバチとsquash、天狗hit、鬼太鼓の小さな持ち上がり、狐火flareはactive strong phaseだけに限定する。河童、雪女、琵琶牧々、一つ目小僧はstrongで変えない。
- resident先頭の上へ6×6 pxの菱形と5 pxのstemからなる先導灯markerを描き、色だけでなく形で区別する。
- Reduce Motionではactive strongを正面reactionの静止姿勢とmarker輪郭で保持し、scale、jump、sway、歩行frameを変えない。内部phase名`.open`は互換性のため維持する。
- accessibility elementは一つに保ち、label、月action、snapshotのaccessibility valueを付ける。自動announcementは追加しない。

- [x] **Step 3: 高頻度観測を`ContentView`の小さなwrapperへ隔離する**

`ContentView.swift`内に`ReactiveVisualStage`を置く。

```swift
private struct ReactiveVisualStage: View {
    @ObservedObject var signals: ParadeSignalCoordinator
    var track: AudioTrack?
    var progress: Double
    var isUshimitsu: Bool
    var onMoonTap: () -> Void

    var body: some View {
        let snapshot = signals.snapshot
        let residentID = track.map { YokaiResidency.spriteID(for: $0.id) }
        YagyoParadeView(
            signal: snapshot,
            residentSpriteID: residentID,
            isUshimitsu: isUshimitsu,
            onMoonTap: onMoonTap
        )
        ArtworkStage(
            track: track,
            progress: progress,
            isPlaying: snapshot.activity != .stopped,
            level: snapshot.level
        )
    }
}
```

root bodyの直接`player.audioLevel`参照を全廃する。trackは`player.currentTrack.id`をキーに`library.tracks`から最新値を引き、見つからない場合だけ`player.currentTrack`へfallbackする。coordinatorは`@Published`にせず、wrapperだけがsnapshotを15 Hz購読する。

- [x] **Step 4: CircularWaveformのReduce Motionを実装する**

`@Environment(\.accessibilityReduceMotion)`を追加する。Reduce Motion時はphaseを0へ固定し、`progress`を長さ計算へ入れない。levelを低・中・高の3段階へ量子化し、暗い短線・中線・長線として即時切替する。通常時の既存位相と配色は維持する。`.accessibilityHidden(true)`は、同じ情報を絵巻の統合valueが伝えるため維持する。

- [x] **Step 5: DEBUG preview harnessを実装する**

`ParadePreviewHarness`はstopped、unavailable、quiet、normal、strong、resident 8種、丑三つ時、Reduce Motionを画面上のPicker/Toggleで切り替える。`previewReduceMotionOverride`を`YagyoParadeView`のinitializerへ明示注入し、静止代替も同じbinaryから確認できるようにする。製品経路ではoverrideを未指定のままにし、読み取り専用の`@Environment(\.accessibilityReduceMotion)`を参照する。

`YagyoPlayerApp`は`#if DEBUG`内でlaunch argumentsに`-step4-parade-preview`がある場合だけharnessをrootへ出す。通常起動、Release build、deep link、library loadは従来`ContentView`経路を使う。

- [x] **Step 6: Macでbuildとfocused testsを通す**

```bash
xcodegen generate
xcodebuild -project YagyoPlayer.xcodeproj -scheme YagyoPlayer -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project YagyoPlayer.xcodeproj -scheme YagyoPlayer -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' -only-testing:YagyoPlayerTests/ParadeSignalReducerTests -only-testing:YagyoPlayerTests/PixelSpriteContractTests -only-testing:YagyoPlayerTests/YokaiResidencyTests test
```

Expected: BUILD SUCCEEDED and focused tests PASS.

- [x] **Step 7: Task 5をコミットする**

```bash
git add YagyoPlayer/Views/YagyoParadeView.swift YagyoPlayer/Views/ContentView.swift YagyoPlayer/Views/VisualComponents.swift YagyoPlayer/Views/ParadePreviewHarness.swift YagyoPlayer/YagyoPlayerApp.swift YagyoPlayer/Models/ParadeSignal.swift YagyoPlayerTests/ParadeSignalReducerTests.swift YagyoPlayer.xcodeproj/project.pbxproj
git commit -m "feat: choreograph the parade from honest level signals"
```

---

### Task 6: 翻訳帳と正本文書の同期

**Files:**
- Create: `docs/CHOREOGRAPHY.md`
- Modify: `docs/PRODUCT_DIRECTION.md`
- Modify: `docs/DESIGN_NAV.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: Task 1–5で実装された事実と定数。
- Produces: ユーザーと次の実装者が同じ意味で読める正本文書。

- [x] **Step 1: `docs/CHOREOGRAPHY.md`を実装値から書く**

冒頭に「入力は15 Hzの`AVAudioPlayer.averagePower`を正規化・平滑化した音量近似で、拍・アタック・デジタル無音・BPM・サビ・曲構成解析ではない」と明記する。表の列は`入力 / 判定 / 通常振付 / Reduce Motion / 実装状態`とし、stopped、unavailable、level、quietProxy、strongRiseProxy、resident、丑三つ時を一行ずつ書く。Task 1の閾値・時間を数値のまま転記する。

- [x] **Step 2: PRODUCT_DIRECTIONの古い現在地とStep 4を更新する**

- Step 3は「iOS 27正式SDKで再検証できるまで保留」とする。
- Step 4目的を「音の大小と変化が、説明可能な振付として伝わる」へ変更する。
- release criteriaを音量、静音近似、強い音量上昇近似、翻訳帳、resident、Reduce Motionへ合わせる。
- §4.3の統計を「記録・永続化済み、絵巻の履歴演出には未接続」へ直す。
- 唐傘縦切りはfeature branch検証中で、全妖怪SNES刷新やStep 4完了とは書かない。

- [x] **Step 3: DESIGN_NAVとREADMEを現在実装へ合わせる**

- DESIGN_NAVに40×48、2倍、最大12色、8フレーム、唐傘→Simulator承認→別仕様という順序を書く。
- 翻訳帳previewを`CHOREOGRAPHY.md`へリンクし、現行の固定サイン波説明を実装後のsnapshot振付へ置換する。
- READMEの「yokai hop to loudness」を、音量帯・低レベル継続・強い上昇近似へ反応する説明に直す。
- stats、mixed art、未実装の残り妖怪を誇張しない。

- [x] **Step 4: 文書整合性を機械確認する**

```bash
rg -n "averagePower|quietProxy|strongRiseProxy|0\.70|0\.45|40×48|最大12色|iOS 27|保留" docs/CHOREOGRAPHY.md docs/PRODUCT_DIRECTION.md docs/DESIGN_NAV.md README.md
rg -n "統計はゼロ|曲を読んでいる|アタック・無音・盛り上がりに反応" docs/PRODUCT_DIRECTION.md docs/DESIGN_NAV.md README.md
```

Expected: first command finds the agreed facts. Second command returns no stale claims except clearly labeled historical quotations in archive files, which are outside this command.

- [x] **Step 5: Task 6をコミットする**

```bash
git add docs/CHOREOGRAPHY.md docs/PRODUCT_DIRECTION.md docs/DESIGN_NAV.md README.md
git commit -m "docs: publish the night parade choreography ledger"
```

---

### Task 7: 二段階レビュー、全テスト、Simulator証拠、Draft PR

**Files:**
- Modify if review requires: files changed by Tasks 1–6 only。
- Modify: `docs/superpowers/plans/2026-07-12-yagyo-emaki-2-karakasa-vertical-slice.md`

**Interfaces:**
- Consumes: complete vertical slice branch。
- Produces: review済みcode、全test結果、Simulator screenshots、GitHub Draft PR。`main` mergeは行わない。

- [x] **Step 1: ネイティブsubagentでspec compliance reviewを行う**

reviewerへdesign spec、plan、`git diff origin/main...HEAD`を渡し、40×48 contract、近似語彙、reset、resident互換、Reduce Motion、非目標を一項ずつ照合させる。BLOCKER/MAJORがあれば実装subagentへ戻し、同じreviewerが解消を確認する。

- [x] **Step 2: 別のネイティブsubagentでcode quality reviewを行う**

純粋reducerの境界、15 Hz publish数、Timer lifecycle、MainActor、SwiftUI再描画範囲、Canvas index safety、pixel source validation、accessibilityを重点レビューする。PlaybackControllerの音声挙動変更、force unwrap、unknown symbolの黙殺、15 Hz root invalidationをblockingとする。

- [x] **Step 3: Remote DesktopのローカルCodexでXcodeGenと全testを実行する**

```bash
xcodegen --version
xcodegen generate
git diff --check
xcodebuild -project YagyoPlayer.xcodeproj -scheme YagyoPlayer -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project YagyoPlayer.xcodeproj -scheme YagyoPlayer -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' test
```

Expected: `BUILD SUCCEEDED`、全tests PASS。環境依存でskipされたPlayback testは件名と理由を記録し、失敗と混同しない。生成された`project.pbxproj`差分だけをscratch worktreeへ戻し、root agentがコミットする。

- [x] **Step 4: Simulator preview harnessを検証する（初期アートの履歴・視覚証跡はsuperseded）**

ローカルCodexはiPhone 17 Proと、利用可能な最小幅iPhone SimulatorへDebug appをinstallし、bundle ID `com.codex.yagyoplayer`を`-step4-parade-preview`付きで起動する。次を操作してscreenshotsを取得した。これは初期の紫色・横向き唐傘に対して実施した履歴であり、各画像と視覚所見は現在候補の承認証跡には使用しない。

1. normal・唐傘resident・通常時を`/tmp/yagyo-step4-normal.png`へ保存。
2. quiet・唐傘resident・通常時を`/tmp/yagyo-step4-quiet.png`へ保存。
3. strong open（互換phase名）・唐傘resident・丑三つ時を`/tmp/yagyo-step4-strong-ushimitsu.png`へ保存。
4. strong open（互換phase名）・唐傘resident・Reduce Motionを`/tmp/yagyo-step4-strong-reduce-motion.png`へ保存。
5. unavailable・別residentを`/tmp/yagyo-step4-unavailable.png`へ保存。

確認点は80×96 ptの唐傘が86 ptのwalker gap内で切れないこと、baselineが変わらないこと、nearest-neighborでにじまないこと、markerが色なしでも読めること、Reduce Motionで座標とscaleが変わらないこと。ローカルCodexはコードを編集・レビューしない。

- [x] **Step 5: 検証結果をplanへ記録して最終コミットする**

Task 1–7のcheckboxを実績どおり更新し、末尾にbuild/test件数、skip、Simulator機種、screenshots、既知の制限「唐傘のみSNES・main未統合」を記録する。

```bash
git add YagyoPlayer.xcodeproj/project.pbxproj docs/superpowers/plans/2026-07-12-yagyo-emaki-2-karakasa-vertical-slice.md
git commit -m "test: verify the karakasa vertical slice"
```

- [x] **Step 6: GitHubプラグインでDraft PRを作る**

base `main`、head `agent/step4-yagyo-emaki-2`。PR本文にdesign spec、implementation plan、test結果、Simulator evidence、Step 3保留、mixed-artのためmerge禁止、ユーザー視覚承認後に残り妖怪の別仕様を作ることを書く。PRはDraftのままにし、mergeしない。

作成済み: [Draft PR #13](https://github.com/tinypony777/YagyoPlayer/pull/13)。Draft・`main`未merge・ユーザー視覚承認待ち。

## 失効した初期アートの検証実績 2026-07-12（履歴）

> 以下は初期の紫色・横向き／長い柄・横に開いた唐傘を含む旧headでの実績である。Xcode 26.6／iOS 26.5のSimulator確認、スクリーンショット、目視所見を削除せず監査履歴として残すが、参照忠実度再設計後の唐傘候補には適用せず、視覚承認証跡として扱わない。旧headのXcode 27 build／full testsも、現在候補のTask 4全suite完了を示すものではない。

- **検証対象:** remote code head `2a6dfdee751a41ba193b5c3cecfec40bb3aaa6de` を fresh clone `/tmp/yagyo-step4-validation-20260712-025257` で検証した。
- **生成とbuild:** XcodeGen 2.45.4による生成に成功。生成前はcleanで、生成後の差分は`project.pbxproj`の生成順による72 insertions / 72 deletionsだけだったため、feature branchへは戻していない。macOS 27.0 / Xcode 27.0 betaのgeneric iOS buildはexit 0。
- **tests:** iOS 27.0のiPhone 17 Proでfocused tests **32 / 32 PASS、skip 0**、`YagyoPlayerTests`全体 **57 / 57 PASS、skip 0**。両`xcresult`ともPassed、`xcodebuild`はexit 0。test完了後の`simctl diagnose`だけが各600秒でtimeoutした。`PlaybackControllerTests`中にAVAudioSessionのmain-thread runtime warningが出たが、test failureはなかった。
- **起動:** Debug appをinstallし、bundle ID `com.codex.yagyoplayer`を`-step4-parade-preview`付きでlaunchできた。
- **iPhone 17 Pro（superseded visual evidence）:** 安定版Xcode 26.6 / iOS 26.5でAX識別子を使い、`normal / kasa / Ushimitsu off / Reduce Motion off`、`quiet / kasa / off / off`、`strong / kasa / on / off`、`strong / kasa / off / on`、`unavailable / kappa / off / off`の5状態を確認した。各画像は1206×2622 px。
- **最小幅（superseded visual evidence）:** iOS 26.5のiPhone 17e（390×844 pt、preview 355×159 pt）で`normal / kasa / Ushimitsu off / Reduce Motion off`を確認した。画像は1170×2532 px。
- **Simulator目視（superseded visual evidence）:** nearest-neighborの整数拡大、足元baseline、菱形+stemのresident marker、quietの`hush`、strongの`open`（互換phase名。当時は横に開いた紫色アート）、丑三つ時の一つ目小僧追加、unavailable時の破線の提灯halo（chochin色を維持）、旧spriteとの衝突と意図しない切れがないことを確認した。viewport端での切れは通常の行進による端通過である。Reduce Motionは座標とscaleの静止表示を確認したが、単一画像の比較だけでは時間経過後も完全に静止することまでは実測していない（code、unit tests、reviewは合格）。40×48 px source、2倍整数表示、80×96 ptはcontract testsとcodeで確認し、画像では整数拡大を確認した。
- **CircularWaveform:** DEBUG `ParadePreviewHarness`にはCircularWaveform自体がないため、unavailableの中立色・破線・位相固定はSimulator画像の目視証拠ではない。これは`CircularWaveformPresentation`のunit testsとcode reviewで確認した。
- **証拠保存先（superseded）:** `/Users/ryuseinaito/automation-mcp/yagyo-step4-validation/`（full screenshots、crops、review images、`ax-summary`）。これらは初期アートの履歴であり、唐傘のユーザー見た目承認には使用しない。
- **review:** native final code reviewはAPPROVED、BLOCKER / MAJOR / MINORはいずれも0。GitHub CIはない。電話 / Siri、イヤホン抜去、バックグラウンド等の手動interrupt確認は今回未実施。
- **公開ゲート:** SNES相当は唐傘だけで、他の妖怪は従来アートのmixed-art状態。Draft PRに留めて`main`へmergeせず、ユーザーの唐傘見た目承認と別frame matrix承認まで残り妖怪へ展開しない。Step 3は保留のままで、FFmpegは採用していない。

## 参照忠実度再設計・現在候補の検証状況 2026-07-12

- **Task 1 RED:** 旧紫アートを参照忠実度契約へ当て、Xcode 27／iOS 27のfocused runで9件実行、3件PASS、6件が期待どおり意味的にFAILした。compile、test discovery、Simulator infrastructureの失敗ではない。
- **focused QA GREEN:** 現在の赤い正面向き候補とtest-only QA artifact rendererを、Xcode 27／iOS 27で **11 / 11 PASS、fail 0、skip 0**（構造9件＋artifact 2件）まで確認した。
- **build／full GREEN:** Xcode 27.0のgeneric iOS buildに成功。checked projectをiOS 27のiPhone 17 Proで **65 / 65 PASS、fail 0、skip 0**。
- **semantic Simulator GREEN:** 座標tapなしで、iPhone 17 ProのNormal／Quiet／Strong／Strong + Ushimitsu state matrix **4 / 4**、Strong + Reduce Motion stability **1 / 1**、最小幅iPhone 17eのdefault Normal + Karakasa **1 / 1**を通過。Reduce Motionの`t0`／`t+2 s` full PNGは同一SHA-256、canvas cropのdiffering bytesは0。最初の17e menu試行失敗とauto diagnostics終了は除外し、follow-up GREENを正本とする。
- **QA artifacts:** 現在ASCIIソースから最近傍2倍のPNG contact sheetと15-frame GIF motion previewを抽出し、デコード／フレーム整合性を確認した。元参照、PNG、GIFを比較した独立native QAはAPPROVED。生成commitは`d1eca866`、画像とSHA-256は[証跡ledger](../../evidence/step4-karakasa/README.md)に集約する。
- **未完了:** 保存済みSimulator画像の最終native目視QA、GitHub同期とDraft PR画像リンクの最終確認、ユーザー見た目承認。旧headの57 / 57結果やiOS 26.5画像をこれらの代用にしない。
- **公開ゲート:** [Draft PR #13](https://github.com/tinypony777/YagyoPlayer/pull/13)をDraftのまま維持し、`main`へmergeしない。現時点は唐傘だけが新画風のmixed-art状態であり、残り妖怪は唐傘のユーザー承認後に別frame matrixを提示し、別途承認されるまで制作しない。
