# YagyoPlayer モダンレトロ UI 全面反映 — 設計仕様

- **日付:** 2026-07-13
- **状態:** Dayモードのコンセプト画と狐火の帳の再構成案をユーザー承認済み。実装・自動検証green、実機描画の最終ユーザー確認待ち
- **対象:** 夜行・行列・巻物・ミニ灯り・狐火の帳・円形波形

## 1. 目的

灯芯で確立した「罫と丸紋」の明治・大正モダンレトロ文法を、YagyoPlayer の全主要画面へ展開する。単に既存カードへ飾り枠を足すのではなく、背景、面、見出し、操作、波形を同じ印刷物の体系へ揃える。

目指すものは、生成りのラベル紙を基本面に、朱・柿・青緑・焦茶を限定的に刷った大正期の商標札やレコードレーベルのようなDayモードである。夜の気配は百鬼夜行の舞台面と丑三つ時の状態表現へ局所化し、画面全体を濃紺で覆わない。添付された三枚の参考画像は、配色、罫線、札形、文字組み、限定色の正本として使う。画像内の英字サンプル、花、人物、鶴、透かしは製品要件として模写しない。

## 2. 優先順位

1. このタスクに対するユーザーの直接指示と、2026-07-13 に承認された推奨案。
2. `docs/PRODUCT_DIRECTION.md` の Local-first Trust、Music Made Visible、Folklore as Interaction Model、iOS-native Ritual。
3. `docs/CHOREOGRAPHY.md` の音量入力、状態、Reduce Motion の意味。
4. 現行 `main` の3タブ、灯芯、ミニ灯り、40×48妖怪、狐火の帳 Phase A。
5. `docs/DESIGN_NAV.md` と既存のモダンレトロコンセプト画像。

既存文書に残る「モダンレトロ全面適用は未承認」「タブ分けは未着手」という記述は、今回の直接承認と `main` の実装事実で supersede される。実装と同じ変更で現在地を同期する。

## 3. スコープ

### 含む

- 画面用カラートークンと印刷物用コンポーネント文法。
- 夜行・行列・巻物・ミニ灯り・狐火の帳の表層刷新。
- 背景、パネル、札見出し、検索欄、行、ボタン、タブ周辺、再生操作、進捗表示の統一。
- 現行 `CircularWaveform` の「レコード盤／丸紋の計器」への全面刷新。
- iPhone 17 Pro と iPhone 17e、Dynamic Type、VoiceOver、Reduce Motion の検証。
- 現行のartifact exportを使った実描画比較とユーザーによる見た目承認。

### 含まない

- 狐火の帳 Phase B のA/B参照とラウドネスマッチ。
- Step 3「一本の耳」のDSP統合、AVAudioEngine移行、解析キャッシュ変更。
- 妖怪40×48ソース、振付reducer、閾値、residency、再生統計の変更。
- 再生キュー、取込、巻物、メタデータのデータモデル変更。
- 参考画像のラスター素材を製品背景や装飾へ直接使用すること。
- カスタムフォント、外部UIライブラリ、新しい依存関係。

## 4. デザイン原則

### 4.1 Dayモードの印刷物

アプリ全体を明るい生成り紙へ統一し、焦茶の文字と罫を基本とする。朱と柿は選択、主操作、注意、現在位置へ限定し、青緑は分析値と狐火の状態へ限定する。大面積のグラデーション、半透明ガラス、ネオンglowは撤去し、フラットな版ずれを思わせる面と線で構成する。

`YagyoBackdrop` は通常時を単色 `canvas` とし、紙面の静かな地として扱う。百鬼夜行のCanvasだけを温かい藍鼠・焦茶の `stage` 面に置き、承認済みピクセル妖怪のコントラストを確保する。丑三つ時は画面全体を暗転させず、舞台面と小さな状態札を既存 `ushiSumi` に近い赤紫へ切り替える。背景pattern自体は動かさず、通常／丑三つ時の切替だけを既存時間でcross-fadeする。

### 4.2 装飾は階層を伝える

- 画面の大見出し: 横長または縦長の札、二重罫、広めの字間。
- 主要パネル: 角を小さく落とした矩形、二重罫、中央または左上の小札。
- 行・検索・副操作: 単罫、装飾なし、情報密度を優先。
- 主操作: 丸紋または印章形。危険操作は朱、通常操作は柿、分析は青緑。

すべてを飾り枠にしない。装飾密度は `画面見出し > 主要パネル > 行 > 補助テキスト` の順に下げる。

### 4.3 世界観と情報の境界

妖怪と夜行絵巻は承認済みのピクセルアートを保つ。モダンレトロ化はCanvasの外枠と周囲の印刷面に適用し、妖怪へ非整数scale、ぼかし、影、色フィルタを加えない。

狐火の帳では数値が主役である。装飾は外周と区切りに限定し、指標値、単位、提案根拠の読みやすさを下げない。

### 4.4 承認済みの色配分

- 基本面は生成り紙。濃色の大面積ブロックを画面背景、波形盤、狐火の指標領域へ置かない。
- 百鬼夜行の舞台だけはピクセル妖怪を読ませるため、青へ寄らない温かい藍鼠・焦茶を使う。
- 朱・柿は「いつも見えるテーマ色」ではなく、選択、主操作、再生位置、提案番号、注意へ使う。
- 青緑は狐火の分析値と分析状態へ使う。朱・柿を常設面へ増やさず、後続Phase BのA/B選択中、ラウドネスマッチ有効、注意が必要な提案へ使える余白を残す。

## 5. カラーと描画トークン

既存の `YagyoColor` と `ParadePalette` は音反応・妖怪・夜空の意味を保持する。画面表層用に別の `YagyoPrintColor` を追加し、同名色の一括置換をしない。

| Token | Hex | 用途 |
|---|---:|---|
| `canvas` | `#F2E6CB` | 全画面の明るい紙地 |
| `paper` | `#E8D7B5` | 生成り札、主要パネル |
| `paperRaised` | `#F5ECD8` | 見出し札、入力欄、選択面 |
| `paperMuted` | `#B9A98C` | 副次罫、disabled装飾。本文には使わない |
| `stage` | `#554C46` | 百鬼夜行の温かい藍鼠・焦茶舞台 |
| `ink` | `#35241E` | 紙面上の文字と焦茶罫 |
| `inkMuted` | `#6B5748` | 紙面上の補助文字 |
| `vermillion` | `#C94F35` | 朱の印、再生済み、警告 |
| `vermillionInk` | `#A43D27` | 紙面上の選択文字、警告本文 |
| `persimmon` | `#D77A3D` | 主操作、現在位置 |
| `teal` | `#1B6666` | 紙色上の狐火の帳、分析状態 |
| `tealRule` | `#6F8C84` | 狐火の区切り罫。本文には使わない |
| `brass` | `#B88A45` | 細い強調罫、選択状態 |

描画値:

- 基本罫: 1 pt。
- 二重罫間隔: 3 pt。
- 主要パネル角半径: 12 pt。現行の24〜30 ptの大きな連続角丸は使わない。
- 行角半径: 8 pt。
- 影: 原則なし。押下状態でも色面と線幅だけで伝える。
- 紙テクスチャ: ラスターを使わない。必要なら不透明度3%以下の決定論的な点をCanvasで描くが、初期実装では無地を基準とする。

## 6. 共通コンポーネント

### 6.1 `ModernRetroPanel`

`paper` と `stage` の二toneを持つ表層用modifier。単色面、二重罫、任意の小札を描く。`paper` は `paper` 面＋外側 `ink`＋内側 `paperMuted`、`stage` は `stage` 面＋外側 `ink`＋内側 `paper` とする。狐火の台帳は塗りパネルではないため、このmodifierへ含めず `canvas` 上へ `tealRule` の区切り罫を直接置く。iOS 26 `glassEffect` と `ultraThinMaterial` は使用しない。既存 `ritualPanel` の呼び出しは、画面ごとに意図が分かるこのmodifierへ移す。

### 6.2 `RetroPlaque`

画面またはパネルの見出し。`paper`（生成り地に焦茶文字）、`stage`（舞台色に生成り文字）、`seal`（朱印）の三variant。`seal`は大きな一文字または装飾記号だけに限定し、通常サイズ本文を朱地へ載せない。日本語見出しはsystem serif、英字補助は小さなuppercaseと広いtrackingを使う。

### 6.3 `RetroIconButton`

丸紋または角印の形。SF Symbolは意味とVoiceOverを維持し、装飾のためだけに独自アイコンへ置き換えない。44×44 pt以上の操作領域を確保する。

### 6.4 `RetroDivider`

中央に小さな菱形または丸を置く単罫。長いカード内の情報区切りにだけ使う。

## 7. 円形波形 — レコード盤／丸紋の計器

現行波形はデジタルな放射バーと大きな角丸のアートワーク枠で、印刷物の文法から外れる。既存の `progress / level / activity / levelBand` と妖怪側の振付契約は保ったまま、描画を全面的に置き換える。2026-07-13のPRレビューを受け、円形波形だけは絶対 `levelBand` を直接表示せず、曲中の局所floor/ceilingから作る表示専用 `waveformLevel / waveformLevelBand` を使用する。

### 7.1 構造

内側から外側へ次の順で描く。

1. 生成り〜薄い黄土の紙色円盤。背景との境界は焦茶の二重円で示す。
2. 焦茶の細い同心円を2本。レコード溝兼、丸紋の輪郭。
3. 焦茶の48本の放射罫。12本ごとに太い主目盛、4本ごとに中目盛を置く。
4. `progress` を示す朱の円弧。12時位置から時計回りに描く。
5. 現在位置を示す柿色の小さな丸紋。円弧末端へ固定する。
6. 中央に同系紙色の小札を置き、停止時は「止」、利用不可時は「—」、lowは「静」、mediumは「響」、highは「烈」と一文字で示す。VoiceOver情報は既存の親要素に残し、この文字は装飾表示として扱う。

`静 / 響 / 烈` はラウドネス規格、サビ、セクションの判定ではない。15 Hzの平滑化済み `averagePower` について、局所floor/ceilingの拡大方向へ即応し、縮小方向へ時定数8秒で追従させ、最小span 0.05で相対化した表示上の近似である。一定の高ラウドネスは中立の `響`へ戻し、小さな相対上昇・下降はヒステリシスと0.55秒holdを通して `烈 / 静`へ残す。再生音、解析値、妖怪の絶対音量帯、VoiceOverは変更しない。

### 7.2 状態表現

| 状態 | 放射罫 | 円弧・輪郭 |
|---|---|---|
| stopped | 全罫を同じ短さ、`paperMuted` | 進捗円弧は保持、輪郭は低コントラスト |
| unavailable | 短い主目盛のみ | 外輪を破線、中央は「—」 |
| low | 短い放射罫 | 朱の進捗円弧、柿の現在位置 |
| medium | 中程度。4本単位の長短 | 同上 |
| high | 長い罫。12本ごとに朱 | 同上。glowやscaleは加えない |

通常モーションでは、`progress` と表示専用 `waveformLevel` から放射罫の長さを連続変化させる。ただし円盤自体は回転させない。Reduce Motionでは `waveformLevelBand` の静止長だけを使い、low / medium / highを形の差で識別できるようにする。

### 7.3 レイアウト

- 標準Dynamic Typeでは夜行の非スクロール1画面を維持する。Accessibilityカテゴリでは内容を切らず、縦ScrollViewへfallbackしてよい。
- 円盤は正方形ではなく円形そのものを視覚境界とし、背後の大きな角丸矩形を撤去する。
- 最小高さ140 ptの契約を保ち、iPhone 17eで絵巻、円盤、操作、灯芯、タブが同時に収まる。
- `DefaultArtwork` は新しい円盤内へ表示せず、盤面はSwiftUI/Canvasの限定色ベクター描画だけで構成する。既存assetはこのUI変更では削除せず、互換性のため残す。

## 8. 画面別適用

### 8.1 夜行

- ヘッダを生成り二重罫の横札へ変更し、「百鬼夜行」を主、英字を副とする。
- 取込ボタンを角印形へ変更。
- 夜行絵巻はピクセル描画を維持し、舞台を`stage`、外周を焦茶＋生成り二重罫へ変更する。濃紺・彩度の高い青を大面積に使わない。
- ArtworkStageを第7章の円盤へ変更。
- 再生操作は丸紋の中央再生ボタン、単罫の前後ボタン、印刷ラベル式の時刻表示へ変更。
- 16マスの進捗は機能を維持し、角丸セル列から短冊状の16目盛へ変更。
- 灯芯は位置写像とVoiceOverを変更せず、表層トークンだけを合わせる。
- iPhone 17eの縦方向予算を増やさない。外周罫は既存領域へのoverlayとし、ヘッダ、絵巻、円盤、Transportの外側へ新しい固定高や縦paddingを足さない。

### 8.2 行列

- 見出しと取込を一枚の横札としてまとめる。
- 検索、絞り込み、並び替えは装飾を抑えた単罫の計器列にする。
- TrackRowは紙札を積むのではなく、紙地へ焦茶の単罫と小さな朱印を置く。長いライブラリで視覚ノイズを増やさない。
- 空状態の狐火は維持し、説明を生成りの中央札へ置く。

### 8.3 巻物

- 巻物見出しは縦札を直接模写せず、横長の紙ラベルでiPhone幅に適応する。
- PlaylistRowは巻物の表紙ラベルとして二重罫、展開内容は単罫に落とす。
- 再生、改名、削除、並び替えの挙動は変更しない。

### 8.4 ミニ灯りとタブ

- native `TabView`、タブ順、routing、safe areaを維持する。
- タブバーは紙地、焦茶の非選択、朱柿の印と罫を伴う選択。カスタムタブバーへ置き換えず、native `TabView` の背景とtintを調整する。選択文字はコントラストを満たす `vermillionInk` とし、明るい`persimmon`だけで通常サイズ文字を描かない。
- ミニ灯りは一行の横札とし、現在曲に朱の丸印、右端に柿色の再生印を置く。

### 8.5 狐火の帳

- dismiss可能なsheet、静的背景、一画面検聴を維持する。第四のbottom tabにはしない。
- 全面を同じ`canvas`の一枚紙とし、画面全体を囲む入れ子額縁と大面積の塗りパネルを置かない。見出し札と閉じるボタンは他画面と同じ上端リズムに揃える。
- 曲名とartistは独立カードにせず、見出し直下の控えめなレコード注記にする。
- 「狐火の目盛」は開いた台帳・検聴票として、上下の青緑二重罫と行間の細い点罫だけで区切る。metricは左に焦茶の名称、右にmonospacedの深い青緑値という現在の読み順を保つ。
- 「狐火の見立て」は箱で囲まず、各提案へ小さな朱の番号印と青緑の根拠罫を付ける。朱印は常設面を塗り潰さず、注意と読み順を示す。
- 狐火の固有印は小さな一箇所だけに限定し、青い炎や青緑の背景面を大きく置かない。
- 解析中、失敗、完了の状態遷移、キャッシュ、dismissは変更しない。

## 9. 状態、データ、エラー境界

このUI変更は純粋な表層変更である。

- `AudioLibraryStore` と `PlaybackController` の公開契約を変更しない。
- `ParadeSignalSnapshot` と `CircularWaveformPresentation` の意味を変更しない。
- `TobariAnalysisController` と `KitsunebiAnalyzer` を変更しない。
- Import、再生、永続化のエラー表示内容と発火条件を変更しない。
- UIが描けない場合でも再生・取込・解析を止める新しい失敗経路を作らない。

## 10. Accessibility と可変レイアウト

- すべての操作領域は44×44 pt以上。
- SF Symbolと既存accessibilityLabelを維持する。
- 紙色上の文字は`ink`、舞台色上の文字は`paper`を原則とし、通常文字4.5:1、大文字見出し3:1以上を確認する。
- 指定hexの基準コントラストは `ink/canvas = 11.92:1`、`ink/paper = 10.42:1`、`inkMuted/canvas = 5.50:1`、`inkMuted/paper = 4.81:1`、`teal/canvas = 5.40:1`、`teal/paper = 4.72:1`、`paper/stage = 5.91:1`、`vermillionInk/paper = 4.52:1`。`persimmon/canvas = 2.52:1` と `vermillion/canvas = 3.64:1` は通常サイズ文字へ使わず、大きなアイコン、太い罫、印、現在位置へ限定する。不透明度を下げる本文表現は禁止し、装飾罫だけにopacityを許す。
- 色だけで状態を表さない。選択、停止、利用不可、音量帯は線種、長さ、中央記号も変える。
- Reduce Motionでは波形の長さ変化、背景pattern移動、glow、scaleを行わない。
- Dynamic Typeで見出し札を固定高にせず、2行まで伸びる。夜行の主見出しだけは1行を維持し、最小幅ではtrackingを縮める。Accessibilityカテゴリでは夜行も縦ScrollViewへfallbackし、標準カテゴリだけを非スクロール契約とする。
- VoiceOverのタブ順、帳の閉じるボタン、灯芯 `.adjustable`、進捗 `.adjustable` を回帰確認する。

## 11. 実装境界

主な変更対象:

- `YagyoPlayer/Support/DesignTokens.swift`
- `YagyoPlayer/Views/VisualComponents.swift`
- `YagyoPlayer/Views/ContentView.swift`
- `YagyoPlayer/Views/PlaylistSection.swift`
- `YagyoPlayer/Views/TobariView.swift`
- `YagyoPlayerTests/ParadeSignalReducerTests.swift`
- `YagyoPlayerTests/TomoshibiSliderTests.swift`
- `YagyoPlayerTests/YagyoTabTests.swift`
- `YagyoPlayerTests/KitsunebiAnalyzerTests.swift`
- `docs/DESIGN_NAV.md`
- `docs/evidence/modern-retro-ui/`（実装後の正本artifact）

`YagyoParadeView.swift` と各 `*Sprite.swift` は、外枠接続に必要な場合を除き変更しない。

## 12. 検証と承認ゲート

### 自動検証

- macOS内蔵ディスクの空き容量が逼迫しているため、すべての`xcodebuild`で `TMPDIR=/Volumes/MacBook_Data_Add/CodexDerivedData/YagyoPlayer/tmp` と `-derivedDataPath /Volumes/MacBook_Data_Add/CodexDerivedData/YagyoPlayer/modern-retro-ui/<run-name>` を指定する。接続先はUSB外付けAPFS SSD、空き756 GiBを確認済み。未接続時は内蔵ディスクへfallbackせず、検証を停止して明示する。
- Xcode 27.0 generic iOS build。
- iPhone 17 Pro / iOS 26.5 full suite。PR #23レビュー対応後の基準は127 tests、failure 0、skip 0。
- iOS 27 betaはPlaybackController 12件を除く115件を実行し、Playback 12件はiOS 26.5 full suiteで担保する。
- `CircularWaveformPresentation` の stopped / unavailable / low / medium / high とReduce Motion静止値。
- 高ラウドネスの定常入力が波形上はmediumへ中立化し、小さい相対上昇・下降でhigh / lowへ遷移すること。reset後は局所rangeを次曲へ持ち越さないこと。
- `TomoshibiSlider` の位置逆写像とVoiceOver nudgeを維持。
- 3タブ順、routing、ミニ灯り表示契約を維持。
- 狐火の帳 Phase A の既知信号とartifact exportを維持。

### 実描画検証

- iPhone 17 Pro: 夜行、行列、巻物、ミニ灯り、狐火の帳。
- iPhone 17e: 夜行1画面、行列の検索列、巻物の展開行。
- 夜行波形: stopped / unavailable / low / medium / high / Reduce Motion。
- 通常と丑三つ時。
- Dynamic Typeの標準とAccessibility Large。
- VoiceOver focus orderとコントラスト。
- 妖怪の整数倍率、にじみ、切断が変わっていないこと。

### ユーザー承認

Dayモードのコンセプト画と狐火の帳の情報構成は2026-07-13にユーザー承認済み。ただしコードがgreenでも、実装されたSimulator描画はユーザー本人の最終確認まで完成扱いにしない。最初の実装では最低限、次の比較を同じ端末寸法で提示する。

1. 夜行全画面。
2. レコード盤／丸紋波形の stopped / unavailable / low / medium / high と high + Reduce Motion。
3. 行列と巻物。
4. 狐火の帳。

見た目の修正は表層トークンと共通コンポーネントへ戻し、画面ごとの場当たり的な色・角丸・余白を増やさない。

## 13. 後続工程との境界

このUI縦切りの承認・統合後に、狐火の帳 Phase Bを別仕様・別計画で実装する。Phase Bは基準音量と独立した減衰乗数を追加するが、本仕様の見た目以外へ遡って変更しない。

その後、Step 3「一本の耳」を現行 `main` 上へ再設計して統合する。旧ブランチを丸ごとmergeせず、共有DSP core、現行 `KitsunebiAnalyzer`、キャッシュ、realtime worker、AVAudioEngineを段階的に一本化する。
