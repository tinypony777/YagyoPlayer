# 妖怪 × 浮世絵 × モダンレトロ — 一枚摺の番付 UI 設計仕様

**状態:** 実装済み・最終実機検証中
**作成日:** 2026-07-15
**対象:** 夜行・行列・巻物・ミニ灯り・狐火の帳・一本の耳・音の可視化
**デザイン命題:** 画面をカードの束から一枚の摺り物へ改め、紙上を歩く妖怪、浮世絵の非対称な版面、モダンレトロの編集秩序を同格に扱う。

## 1. 背景と優先順位

2026-07-13 のモダンレトロ UI は、生成り紙、限定色、罫線、Day モードという基礎を確立した。一方で、現在の画面は「大正ラベルの横札」と「暗い夜行舞台」の二層に分かれ、妖怪は暗箱の展示物、浮世絵は参照されない装飾語になっている。円形計器も縦方向の面積を大きく使う割に、作曲者が求める横方向の時間感覚を持たない。

本仕様はユーザーの直接指示を正本とし、視覚上の優先順位を次のように改める。

1. **妖怪:** 紙面に住む案内役・曲ごとの守り神・版元印。
2. **浮世絵:** 非対称な構図、見切れ、霞、版木枠、縦横の文字組み。
3. **モダンレトロ:** 限定色、可読性、編集グリッド、現代の操作性。

「夜行」は削除しない。行列、巻物、狐火など既存の操作語彙とタブ routing は保つ。ただし夜を全画面の基本面にはせず、丑三つ時に紙面の一部が暮れる**時刻状態**へ戻す。この視覚階層については、旧仕様 `2026-07-13-modern-retro-ui-design.md` の夜行中心の構図を本仕様が上書きする。

## 2. 入力となるリファレンス

- 明治・大正期を想起させるラベル三枚: 限定色、外題枠、罫線、縦横の文字組み。
- 現代都市を浮世絵化した一枚: 現代機能と木版構図の同居、奥行き、群像。
- 妖怪と現代人物の貼交絵: 妖怪コラージュと新旧対比のみ採用。人物、犬、ゴシック建築は採用しない。
- [国立国会図書館「暁斎百鬼画談」](https://www.ndl.go.jp/imagebank/theme/kyosai100oni): 毛描き、手足の重心、前傾、非対称な群像、限定色の運動正本。
- [国立国会図書館「鳥山石燕の妖怪図鑑でみる妖怪の世界」](https://www.ndl.go.jp/imagebank/column/sekienyokai) と[国際日本文化研究センター 妖怪画像データベース](https://www.nichibun.ac.jp/YoukaiGazou/): 各個体の識別部位と歴史的な姿の正本。
- [佐渡観光交流機構「鬼太鼓」](https://www.visitsado.com/about-sado/tradition/): 鬼太鼓だけに使う片脚を上げた舞、白髪、面、撥の補助正本。
- Canva 方向性ボード: 有効だった「横一本の波形」「大きな余白」「縦の外題」「版木枠」を採用。イベントポスター化、空疎な極小主義は不採用。
- Claude Code Fable の独立批評: 推奨案「一枚摺の番付」を採用。モダンレトロ達成／妖怪軟禁／浮世絵不在という現状診断を設計課題とする。

## 3. デザイン原則

### 3.1 一画面一版

- 主役の二重罫・版木枠は一画面に一つだけ置く。
- 脇役は単罫、点罫、余白で整理し、すべてをカードへ閉じ込めない。
- 角丸の連打をやめ、切り角の版木枠と直線的な台帳面を基本にする。

### 3.2 妖怪を紙面へ解放する

- resident ID、並び順、4歩行／静音／強反応の意味と対象matrixは維持する。旧pixel正本は40 × 48 logical canvasの互換fallbackとして残す。
- 2頭身のピクセルマスコット表現は廃し、個体ごとの正本に基づく木版輪郭・限定色の全身図へ描き直す。成人型は4〜5頭身、一つ目小僧は3〜3.5頭身、河童は3〜4頭身を目安とし、器物・動物型へ人型頭身を強制しない。
- 透過ラスター正本は最低でも @3x 相当を持たせる。承認済みの正方形正本は縦横比を歪めない64 × 64の配置座標へ置き、442px正本のalpha bboxを接地・住人印・静的輪郭の基準にする。40 × 48の旧anchor／baselineはpixel fallbackで維持し、低解像度ピクセルを拡大した見た目には戻さない。
- Day の行列は暗い `stage` 箱から生成りの欄間へ移す。
- 曲の resident は行列の先導に加え、曲札の「守り神印」として再利用する。
- 妖怪へ blur、色フィルタ、非整数 scale、常時 glow を加えない。

#### 3.2.1 Reference の役割分担

Reference は次の責任境界で使い、雰囲気だけを混ぜない。

1. **Canonical identity:** 各個体の正本。「何者か」、固定部位、比率、持ち物を決める。
2. **Line and motion:** 河鍋暁斎『暁斎百鬼画談』。毛・衣・皮膚の線密度、手足の重量、歩行の前傾、群像のばらつきだけを決める。暁斎に描かれた別妖怪の顔や身体を個体へ移植しない。
3. **Color and editorial frame:** ユーザー提供の明治・大正ラベル。生成り、墨茶、弁柄朱、柿、藍摺、少量の青緑、切り角、二重罫、縦外題を決める。ラベル輪郭を妖怪の身体へ変形しない。
4. **Karakasa production method:** `2026-07-12-karakasa-reference-fidelity-redesign.md`。唯一の正本、固定部位、neutral idle、同一baseからの状態差分、contact sheet、独立QA、本人承認という工程だけを全9体へ適用する。承認済み唐傘のピクセル画風を新アセットの画風にはしない。

個体正本と運動正本が衝突する場合は、個体正本を優先する。色が識別部位に含まれる場合はその色を残し、それ以外だけを本作 Palette へ減色する。

#### 3.2.2 個体Reference契約

| resident | canonical identity | 固定する造形 | 禁止する再解釈 |
|---|---|---|---|
| `oni` 鬼太鼓 | [佐渡の鬼太鼓](https://www.visitsado.com/about-sado/tradition/)の舞と、[暁斎百鬼画談](https://www.ndl.go.jp/imagebank/theme/kyosai100oni)の鬼を組み合わせる明示的な複合正本 | 成人の赤鬼、荒い白髪、角、撥、胴前の小太鼓、片脚を高く上げた前傾。既存residentの「鬼＋太鼓」を維持する | 幼児体型、四角い面アイコン、太鼓を丸い腹として処理、常時正面左右対称。歴史上の単一妖怪名を装わない |
| `mokugyo` 木魚 | [鳥山石燕「木魚達磨」](https://commons.wikimedia.org/wiki/File:SekienMokugyo-daruma.jpg) | 巨大な木魚の曲面へ達磨の険しい顔が一体化し、下縁に魚鱗と木の彫りを持つ量塊 | かわいい丸魚、鍋・壺、帽子を載せた顔アイコン、独立した人の頭 |
| `kasa` 唐傘 | 2026-07-12 に承認されたユーザー提供Referenceを唯一の正本とし、[歴史画](https://www.nichibun.ac.jp/cgi-bin/YoukaiGazou/card.cgi?identifier=U426_nichibunken_0081_0027_0000)は素材感の補助に限定 | 正面の赤い円錐形、茶の頭頂と金帯、中央の一眼、笑い口、桃色の舌、淡色の一本脚、下駄 | 横向き和傘、長い柄、腕、複数脚、紫、水平に開く傘。歴史画で承認済みの個体識別を上書きしない |
| `kappa` 河童 | [鳥山石燕「河童」](https://dl.ndl.go.jp/api/iiif/2553975/R000013/2924,916,2132,2940/,1000/0/default.jpg) | 小さい頭皿、低い嘴、濡れた毛、斑点、長い三本指と水掻き、前傾した細身 | 緑のカエル、亀マスコット、大きな丸眼鏡、四角い胴、常時笑顔 |
| `kitsune` 狐火 | [鳥山石燕「狐火」](https://dl.ndl.go.jp/api/iiif/2553975/R000016/2944,948,2152,2940/,1000/0/default.jpg) | 痩せた狐の全身、伏せた耳、長い尾、口元または尾端の小さな火。狐が主体で火は付随 | 胴体のない青い火、白い狐面アイコン、ネオン発光、丸いペット狐。分析用tealを個体主色にしない |
| `tengu` 天狗 | [月岡芳年の人型天狗](https://www.nichibun.ac.jp/cgi-bin/YoukaiGazou/card.cgi?identifier=U426_nichibunken_0138_0001_0005) | 成人の長鼻、頭襟、白い山伏装束、赤い結袈裟／肩衣、羽団扇、険しい横顔 | 赤い丸顔の子ども、鼻を嘴へ置換、帽子だけの記号、短脚のかわいい僧 |
| `yuki` 雪女 | [北斎季親『化物尽絵巻』の雪女](https://www.nichibun.ac.jp/cgi-bin/YoukaiGazou/card.cgi?identifier=U426_nichibunken_0052_0021_0000) | 白い長髪と白衣、細い成人女性、赤い口だけの色点、雪へ溶けて見えない足 | 姫キャラ、紫髪、青い発光、足のある白ワンピース人形、笑顔 |
| `biwa` 琵琶牧々 | [鳥山石燕「琵琶牧々」](https://commons.wikimedia.org/wiki/File:SekienBiwa-bokuboku.jpg) | 琵琶そのものが頭と背、盲僧の前屈、重なる法衣、杖、前へ探る細い手 | 琵琶を背負う普通の人、卵形の顔、楽器アイコン、直立左右対称 |
| `hitotsume` 一つ目小僧 | [月岡芳年の一つ目小僧](https://www.nichibun.ac.jp/cgi-bin/YoukaiGazou/card.cgi?identifier=U426_nichibunken_0109_0008_0002) | 坊主頭の童子、額中央の一眼、長い赤舌、白い小袖、驚かすように上げた両手 | 目玉に棒の手足、アプリアイコン、巨大な光沢眼、幼児アニメ顔、頭だけ |

鬼太鼓だけは既存アプリのresident意味を保つための複合造形であり、単一の古典図像をcanonicalと偽らない。唐傘は既に本人承認された個体正本を歴史資料より優先する。全9体とも、上表で定めた個体正本を別の妖怪Referenceへ差し替えない。

#### 3.2.3 制作順と承認ゲート

1. 1体につき個体正本1枚と、必要なら補助Reference最大1枚を登録する。
2. 透明背景の `neutral idle` を1体ずつ制作する。全9体の idle が揃うまで歩行、静音、強反応を制作しない。
3. 同じ比較シートで、等身、線密度、限定色、光学中心、baseline、小サイズの識別性を確認する。
4. 独立native visual QAに加え、ユーザー本人が9体の idle を明示承認する。
5. 承認された同じbase artからのみ、既存の4歩行／静音／強反応を派生する。各フレームを独立生成しない。
6. Asset Catalogへ透過アセットとして統合し、欄間、曲札の守り神印、iPhone 17 Pro Max／17e、Day／丑三つ時で確認する。

未承認の idle からアニメーションを量産しない。`cute yokai`、`chibi`、`flat vector mascot`、`app icon` を生成指示に含めず、genericな妖怪シートを正本にしない。博物館・データベース画像はReference比較にのみ使い、アプリへ複製収録しない。

### 3.3 夜は状態であり、基本面ではない

- Day は紙地が基本。暗い大面積を置かない。
- 丑三つ時は妖怪欄間だけを暮色へ変え、横長の音表示・本文・背景紙は維持する。時刻はヘッダの小さな朱印でも告げる。
- 月の操作、時刻判定、既存 announcement、Reduce Motion 契約は維持する。

### 3.4 青緑を分析専用に戻す

- `teal` は LUFS、解析状態、根拠罫など狐火・分析の細いインクに限定する。
- artist、通常メタデータ、広い背景面へは使わない。
- 青緑の面積で階層を作らず、墨茶、朱、柿、余白で作る。

## 4. Palette

既存色を再配分し、新しい依存やカラーモードは増やさない。

| 名称 | HEX | 用途 |
|---|---:|---|
| 胡粉紙 | `#F2E6CB` | 全画面の紙地 |
| 薄香紙 | `#E8D7B5` / `#F5ECD8` | 台帳面、持ち上がった紙片 |
| 墨茶 | `#35241E` | 本文、版木枠、常用罫 |
| 藍摺 | `#283B4A` / `#647983` | 外題、版木枠、細い色版。大面積背景には使わない |
| 弁柄朱 | `#C94F35` / `#A43D27` | 印、選択、再生済み、警告 |
| 柿 | `#D77A3D` | 主操作、再生位置、現在点 |
| 狐火青緑 | `#1B6666` | 分析値と分析状態のみ |

`#554C46` の暮色は常用 Palette ではなく、丑三つ時の局所状態としてのみ使う。

## 5. Typography

- **題字・外題:** Apple system serif、semantic text style、semibold、広めの tracking。短い語だけを一字ずつ縦積みして浮世絵の外題柱にする。
- **本文・操作:** Apple system sans、semantic text style。長文と操作名は追跡幅を増やさない。
- **計器・時刻:** Apple system monospaced + `monospacedDigit()`。LUFS、dB、BPM、再生時刻に限定する。
- Accessibility Dynamic Type では縦積み外題を横書きへ戻す。VoiceOver は常に通常語順で読む。

## 6. Signature element — 版木枠の横一本「音の足跡」

大胆さは主画面の横長可視化へ一箇所だけ使う。

- 生成りの盤面、切り角の版木枠、墨茶の左右対称バー、最新点の柿、強い音の階層を示す朱。
- 右辺に短い縦外題、角に resident 妖怪の版元印。
- 円形計器の `stopped / unavailable / low / medium / high` と `止 / — / 静 / 響 / 烈` の意味は維持する。
- 初段は既存 15 Hz の `waveformLevel` を短い表示専用履歴へ保存し、「直近の音の足跡」を描く。全曲ピーク列や曲構成を装わない。
- 全曲の再生位置は波形枠の外にある既存の短冊目盛だけで示し、直近履歴と同じ時間軸に見せない。
- 全曲 waveform は別 phase。Step 3 の共有 offline cacheへ bounded peak/RMS 列を追加し、容量、version、失敗状態を仕様化してから接続する。
- 追加の DSP、再生音変更、音声ファイル再読込は本 PR では行わない。
- Reduce Motion は履歴を静止させ、音量帯ごとの形と一文字印を残す。

## 7. 画面構成

### 7.1 夜行 — 妖怪音の一枚摺

```text
┌──────────────────────────────┐
│ YAGYO PLAYER   [妖]   [耳][納] │
│ 欄間: 紙上を妖怪が歩く          │
│ ╔═ 版木枠・直近の音の足跡 ═══╗宵│
│ ║▂▅▇▆▃▂▄▇█▅▃▄▆            ║の│
│ ║ [守り神印] 曲名 / artist     ║底│
│ ╚═══════════════════════════╝  │
│        ◀◀    ▶    ▶▶           │
│ 短冊進捗 / 時刻 / 灯芯           │
└──────────────────────────────┘
```

- Header のブランドは `YAGYO PLAYER` を主とし、「百鬼夜行」は小さな印・tab 語彙へ退く。
- 行列 Canvas は紙の欄間へ変更し、地面罫で妖怪を接地させる。
- 円形計器は横長の音の足跡へ置換する。
- 曲名札を独立した中央カードにせず、版木枠内の外題へ統合する。
- `FooterView` の説明は主役の欄外注記へ統合する。

### 7.2 行列 — 妖怪番付

```text
┌──────────────────────────────┐
│行│ 検索                       [+]│
│列│ 巻物範囲 / 並び順       2曲 │
│──┴───────────────────────────│
│[守り神] 宵の底 / 作者     3:37 ▶│
│‥‥‥‥‥‥‥‥‥‥‥‥‥‥‥│
│[守り神] 雨の茶舗 / 作者   4:12 ▶│
└──────────────────────────────┘
```

- 上部だけを主役版面とし、各曲は単罫の番付行にする。
- resident は正方形カードではなく小さな守り神印として置く。
- artist は `inkMuted`、再生中だけ朱を使う。

### 7.3 巻物 — 外題と綴じ順

```text
┌──────────────────────────────┐
│巻│                         [+]│
│物│ 明治の夜行 / 2曲         ⌄│
│  │  一  宵の底             ▶│
│  │  二  雨の茶舗           ▶│
│  │  欄外注: 長押しで曲を綴る │
└──────────────────────────────┘
```

- PlaylistRow を表紙ラベル、展開行を綴じ順として扱う。
- 空白には短い欄外注記を置き、放置された余白に見せない。

### 7.4 狐火の帳 — 数値を主役にした分析台帳

- 現行の一枚紙・点罫・桁揃えは維持する。
- Header を狐火の外題柱へ、A/B を二枚の比較札へ揃える。
- 青緑は数値、解析 progress、根拠の細罫だけに限定する。
- A/B 同時刻、減衰専用 match、帳外での解除境界は変更しない。

### 7.5 一本の耳 — 曲相と試聴札

- Header、曲相、原音／Fixed EQ、試作カーブを一枚の試聴台帳へ揃える。
- `区間` を **`構成`**、値を **`4幕`** と表示する。VoiceOver は「構成、4幕」と読む。
- Music Understanding の sectionCount 自体、cache、解析開始境界は変更しない。

## 8. 共通 SwiftUI 部品

- `WoodblockFrameShape`: InsettableShape の切り角版木枠。
- `WoodblockPanel`: 紙面、単罫／二重罫、局所 accent をまとめる modifier。既存 `modernRetroPanel` の呼び出し側は段階的に維持可能。
- `VerticalTitleColumn`: 短い外題の縦積み。Accessibility サイズでは横書きへ fallback。
- `WoodblockWaveform`: 円形計器の状態契約を横長へ移植し、bounded な直近履歴を描く。
- `WoodblockSectionHeader`: 題字、英字副題、印、操作を一つの編集グリッドへ揃える。
- `YagyoBackdrop`: 静的な和紙繊維に、低 opacity の霞と青海波を追加する。背景 pattern はアニメーションしない。

## 9. 実装範囲

### In scope

- `DesignTokens.swift` の用途整理と共通版木部品。
- `ParadeSignal.swift` の表示専用 bounded 履歴（再生音とDSPには影響させない）。
- `VisualComponents.swift` の背景・panel・横長音表示。
- `ContentView.swift` の主画面、行列、行、ミニ灯りの構図。
- `YagyoParadeView.swift` の Day 欄間化。丑三つ時の既存意味は維持。
- resident IDと反応matrixを維持し、個体Reference契約とidle承認ゲートに基づく妖怪全9体の木版画化。
- `PlaylistSection.swift`、`TobariView.swift`、`TobariABComparisonView.swift`、`FixedEQAuditionView.swift` の共通文法適用。
- Visual artifact、Dynamic Type、Reduce Motion、VoiceOver、最小幅の検証。

### Out of scope

- 全曲 peak/RMS waveform の offline 解析と cache schema 変更。
- 再生 backend、DSP、A/B、ラウドネスマッチ、Music Understanding の挙動変更。
- 新しい妖怪、外部 font、UI library、追加dependency。
- Tab の順序、URL routing、データモデル、取込、削除、playback queue の変更。

## 10. Accessibility と performance

- すべての操作領域は 44 pt 以上。
- 本文は WCAG 相当 4.5:1 を目標に墨茶を使い、朱・柿単独へ本文情報を載せない。
- 外題柱は短語限定。Accessibility Dynamic Type では横書きへ fallbackする。
- 紙纹、霞、青海波、版木の欠けは accessibilityHidden、決定論的、静止。
- 横長音表示は既存 publisher を観測するだけで、新しい audio tap、timer、DSP を増やさない。
- 履歴は固定上限とし、track 変更・停止時の扱いを決定論的にする。
- `YagyoParadeView` の Timeline は現行 pause 条件を維持し、追加 Canvas は timeline を持たない。

## 11. Acceptance criteria

- [x] Day の最大暗色面がなく、妖怪が生成り紙の欄間に接地して見える。
- [x] 最大視覚要素が横長の版木枠「音の足跡」で、円形計器が残っていない。
- [x] 表示が直近信号であることを UI・仕様ともに偽らず、全曲波形と表現しない。
- [x] 丑三つ時は妖怪欄間だけが暮れ、横長の音表示・背景紙・本文は読める。
- [x] teal が通常 artist／本文／広い面に使われず、分析用途に限定される。
- [x] 妖怪9体のneutral idleが個体Reference契約どおりに見え、ユーザー本人の承認後に同じbase artから状態差分が派生され、resident ID・歩行・静音・強反応matrixが変わらない。
- [x] 行列、巻物、狐火の帳、一本の耳が同じ版木枠・外題・単罫体系に見える。
- [x] 一本の耳に `区間` が残らず、表示と VoiceOver が `構成 n幕` になる。
- [x] native TabView、三タブ順、ミニ灯り、A/B、Fixed EQ、取込、再生契約が不変。
- [x] iPhone 17 Pro Max、iPhone 17e、Accessibility Dynamic Type で切れ・重なりがない。
- [x] stopped / unavailable / low / medium / high / Reduce Motion の横長音表示を形で判別できる。
- [ ] Reduce Motion の比較画像で、時間経過による差分がない。
- [ ] 外付け SSD の DerivedData/TMPDIR で focused test、full suite、Release build が成功する（focused 50件、再生系2クラスを除く200件、Releaseは成功。Simulatorの既存Audio Session系35件はtest host終了のため実機で最終確認中）。
- [ ] 実機へ署名付き build を install・launch し、主要五画面を目視確認する。

## 12. Screenshot matrix

1. iPhone 17 Pro Max: 夜行 Day / 丑三つ時 / 行列 / 巻物 / 狐火の帳 / 一本の耳。
2. iPhone 17e: 夜行 Day / 行列 / 展開済み巻物。
3. Accessibility: 夜行 / 行列 / 狐火の帳 / 一本の耳。
4. 横長音表示: stopped / unavailable / low / medium / high / Reduce Motion。
5. Reduce Motion: 同一 state の `t0` / `t+2s`。
