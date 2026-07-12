# UI改善「夜行の間取りと灯り」証跡ledger

[設計仕様](../../superpowers/specs/2026-07-12-yagyo-madori-to-akari-design.md)(PR #18で承認)の導入順序に沿った証跡です。

## Step 1: 灯芯スライダー(仕様§4.1)

音量の標準 `Slider`(白い丸ノブ+狐火色tint)を、`StepProgressBar` と同族の自前ビュー `TomoshibiSlider` へ置換。

- **実装**: `VisualComponents.swift`(StepProgressBarと同居)。トラックは墨色の細線、通過側は提灯色の淡いグラデーション、ノブは提灯玉+柔らかなglow。ドラッグ中はglowがわずかに強まり、Reduce Motion時は変化しない。タップ位置ジャンプ+ドラッグ(最小距離8ptはStepProgressBarと同じ)。VoiceOverは `.adjustable`(%読み上げ、一歩5%)。
- **置換箇所**: `ContentView.swift` の音量行のみ。両端のスピーカーアイコン、`volumeBinding`、`PlaybackController` は不変。
- **テスト**: `TomoshibiSliderTests` — 位置→値の写像とクランプ(4)、VoiceOver増減とクランプ(4)、Simulator実描画のQA artifact(2、単色検知つき)。TDD(RED: `Cannot find 'TomoshibiSlider' in scope` → GREEN)で追加。

### Simulator実描画(iPhone 17 Pro / iOS 27.0)

代表値0% / 35% / 88%(ContentViewと同じ音量行構成):

![tomoshibi-slider](tomoshibi-slider.png)

実ContentView統合後の全景(空ライブラリ、音量は既定0.88):

![tomoshibi-contentview](tomoshibi-contentview.png)

## Step 2: タブ分け(仕様§4.2)

未着手。Step 1の承認後に独立PRで実施する。
