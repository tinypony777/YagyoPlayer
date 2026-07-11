# デザインナビ

`docs/PRODUCT_DIRECTION.md`（v3・作者の憲章）に追従するビジュアル・リファレンス。ロードマップ、原則、非目標の一次情報は憲章を参照し、音量入力と振付の正式な対応は [夜行絵巻 振付翻訳帳](CHOREOGRAPHY.md) を正本とする。

## Step 4 唐傘縦切りの現在地

Step 4 feature branch では、15 Hz の `AVAudioPlayer.averagePower` から得る単一の `ParadeSignalSnapshot` を、小さな `ReactiveVisualStage` だけが coordinator から購読する。この wrapper が snapshot を夜行絵巻へ、snapshot の `level / activity / levelBand` を円形波形へ渡し、root `ContentView` やライブラリ全体を 15 Hz 更新へ巻き込まない。snapshot は `level / activity / strongPhase / strongSequence` を持ち、停止、meter 利用不可、`quietProxy`、通常状態を区別する。現在トラックの resident は固定 roster による互換割当を保ったまま先導へ移る。

これはまだ製品版の完成表示ではない。ローカル Xcode build / test、Simulator の通常・丑三つ時・Reduce Motion、ユーザーによる唐傘の見た目承認が残っている。新規の SNES 相当アートは唐傘だけで、他の妖怪との混在状態は feature branch と Draft PR に留め、`main` へ統合しない。

| 入力・状態 | snapshot と表示 | 現在地 |
|---|---|---|
| stopped | 中立姿勢で移動、揺れ、歩行フレームを停止 | feature branch 実装・ローカル検証待ち |
| unavailable | 再生は継続するが音量反応は出さず、位相固定・中立色・破線の CircularWaveform と破線の提灯 halo で low / stopped と区別する | feature branch 実装・ローカル検証待ち |
| level | 通常時は固定 4 fps で歩行し、level を bob の振幅、提灯 halo、Reduce Motion の円形波形の離散形状へ翻訳 | feature branch 実装・ローカル検証待ち |
| `quietProxy` | 低レベル継続を遅い行進と小さな bob へ翻訳。専用 `hush` は唐傘だけで、他の妖怪は `idle` fallback | feature branch 実装・ローカル検証待ち |
| `strongRiseProxy` | `anticipate / open / recover` の一回の反応へ翻訳 | feature branch 実装・ローカル検証待ち |
| resident | 現在トラックの妖怪を重複なく先頭へ移し、先導灯と VoiceOver で示す | feature branch 実装。聴取史による進行は未接続 |
| 丑三つ時 | 一つ目小僧を最後尾へ追加。音量由来の状態ではない | 既存機能を snapshot 表示へ接続・ローカル検証待ち |

判定値、reset 境界、Reduce Motion の静止代替は [CHOREOGRAPHY.md](CHOREOGRAPHY.md) に集約する。歩行周期は画面上の行進テンポで、楽曲の BPM ではない。

## 既存スクリーンショットとインタラクティブ版（Step 4 前の記録）

次の画像は Step 4 より前の画面構成、配色、レイアウトを記録したもの。現在の snapshot 振付、resident 先導、唐傘 40×48 基準体、Reduce Motion の検証証拠ではない。

| Day | 丑三つ時（月タップで遷移） |
|---|---|
| ![day](design/screen-day.png) | ![ushimitsu](design/screen-ushimitsu.png) |

[Claude Design のインタラクティブ版](https://claude.ai/code/artifact/aa4981af-47ac-4fb9-a764-751f356d6261) も、Step 4 前のコードを写した**歴史的な設計アーティファクト**である。そこで動く旧来の音量連動アニメーションを、現在コードや Simulator 検証の代わりとして扱わない。Claude アカウント限定のプライベートリンクで、共有許可も別途必要になる。

## 実装現在地、早見表

| 項目 | 正直な現在地 |
|---|---|
| 音量入力 | `averagePower` のみ。正規化・非対称平滑化後の level と、その時間変化から `quietProxy` / `strongRiseProxy` を作る。拍、デジタル無音、BPM、セクション、音楽的意味は判定しない |
| 視覚信号 | 純粋 reducer と表示専用 coordinator を feature branch に実装。再生経路と Audio Session は変更しない |
| 行列 | 固定8体 + 丑三つ時だけ一つ目小僧。未使用のぬりかべを完成数に含めない |
| アート | 唐傘だけが新しい 40×48 px・8フレーム基準体。他の行列妖怪は従来アートのまま |
| residency | UUID 由来の安定した割当を維持。feature branch では現在曲の resident が先導する |
| 再生統計 | `playCount / lastPlayedAt / playHourCounts` は記録・永続化済み。歴史による行列振付には未接続 |
| Accessibility | 夜行絵巻の VoiceOver 値と、夜行絵巻・円形波形の Reduce Motion 代替を feature branch に実装。Simulator 検証待ち |
| Step 3 | iOS 27 の正式 SDK で Music Understanding / Core AI を再検証できるまで保留。Core AI / DSP は未実装 |

## 唐傘の SNES 相当アート契約

唐傘は、残りの行列妖怪を描く前に寸法と動きの成立を確かめる**基準体**である。

- 元データ: **40×48 px**。1文字=1ドットの行文字列と名前付き限定パレットを正本にする。
- 表示: **2倍の整数倍率（80×96 pt）**。補間は `.none` とし、非整数拡縮でにじませない。
- 色: 透明を除き **最大12色**。
- 基準: 全フレームで共通の `anchorX = 20`、`baselineY = 45` を保ち、描画 rect の差で位置を補正しない。
- フレーム: **8枚** — `idle 1 + walk 4 + hush 1 + strong 2`。
- `walk` は視覚上の一定テンポで、曲の周期を表さない。`hush` は `quietProxy`、`strong` は `strongRiseProxy` の静止代替にも使う。

確認順序は次で固定する。

1. 唐傘を通常時・丑三つ時、resident 先導、Reduce Motion、狭い iPhone 幅で Simulator 検証する。
2. ユーザーが唐傘の輪郭、目、傘骨、足運び、補間、基準線を承認する。
3. 残り7体と一つ目小僧について、各状態と必要フレームの matrix を別仕様として提示する。
4. matrix のユーザー承認後にだけ、残りの制作へ進む。

したがって、唐傘縦切りは全妖怪の SNES 刷新でも Step 4 完了でもない。背景用の大判妖怪（例: 125×105 のがしゃどくろ案）の規格を、40×48 の行列規格へ流用しない。

## デザイントークン

`YagyoColor` / `ParadePalette`（`DesignTokens.swift`）からの抜粋。

![tokens](design/tokens.png)

| 名前 | 用途 | hex |
|---|---|---|
| 墨 sumi | 夜の地 | `#0b0c14` |
| 宵闇 yoiyami | パネル | `#151726` |
| 月白 geppaku | 文字 | `#e9e4d3` |
| 提灯 chochin | アクセント | `#f0a63c` |
| 朱 shu | 通常打 | `#c2402e` |
| 狐火 kitsunebi | ゴースト | `#6fd3e0` |
| 丑三つ時の月 akaMoon | 丑三つ時アクセント | `#d84040` |
| dim | 副次テキスト | `#8a8fa8` |

## 過去の新規提案（未承認・未実装）

以下は 2026-07-08〜10 に制作したコンセプト記録であり、Step 4 唐傘縦切りのスコープでも、現在の実装でもない。音量入力との対応、追加制作、製品への採用は承認されていない。

### 人魂 — アートワークの視線

アートワーク周辺に民話の語彙を持ち込む視覚案。現在の Step 4 には人魂スプライトも専用振付も追加しない。

![hitodama](design/hitodama-proposal.png)

### がしゃどくろ — 丑三つ時の背景案

歌川国芳「相馬の古内裏」の構図を参照した、125×105 px・限定11色の大判2フレーム案。行列へ加える案ではなく、音量との対応も未承認である。40×48 の行列用契約とは別規格として保管する。

![gashadokuro](design/gashadokuro-proposal.png)

## 狐火の帳コンセプト（未実装）

数値が主役の検聴画面として作成した過去のコンセプト。Step 3 は iOS 27 正式 SDK の再検証まで保留中であり、Core AI / Music Understanding / DSP の実装を示す画像ではない。

![kitsunebi concept](design/kitsunebi-concept.png)

---

## 更新履歴

- 2026-07-12: Step 4 唐傘縦切りの snapshot 振付、正式翻訳帳、resident / 統計の現在地、40×48 基準体と承認ゲートへ同期。旧スクリーンショットと Claude artifact、新規妖怪案を歴史的資料・未承認提案として明記。
- 2026-07-10: 全妖怪を SNES 相当へ刷新する方向案を記録し、がしゃどくろを 125×105 px・限定11色へ更新。
- 2026-07-09: がしゃどくろ案と当時のインタラクティブ版を更新。
- 2026-07-08: 初版。PRODUCT_DIRECTION.md v3 のデザインイメージと人魂・がしゃどくろ案を追加。
