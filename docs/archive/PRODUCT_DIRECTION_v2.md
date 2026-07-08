# YagyoPlayer Product Direction v2

この文書は、YagyoPlayer の機能追加・デザイン追加・ロードマップ判断で迷ったときの判断基準です。

## 0. One-line Positioning

**YagyoPlayer は、自分の音源をローカルに納めると、音に反応する百鬼夜行が目を覚ます iOS 音楽プレイヤーです。**

英語表現:

> A local-first iOS music player where your private audio library becomes a reactive Hyakki Yagyō procession.

## 1. Core Promise

YagyoPlayer は、ユーザー自身の音源を安全に取り込み、再生という日常操作を、音に反応する夜行絵巻へ変えるローカルファーストの iOS 音楽プレイヤーです。

これは「妖怪スキンを被せたプレイヤー」ではありません。

- 音源はユーザーのもの。
- 再生体験は信頼できるもの。
- 視覚演出は音楽の状態を伝えるもの。
- 日本の民話・文学・ピクセルアートは、操作体系そのものを支えるもの。

## 2. Product North Star

**Press play, and the procession wakes up.**

再生ボタンを押した瞬間、ユーザーは「普通の音楽アプリではなく、YagyoPlayer で聴く理由」を感じる必要があります。

North Star は次の 3 条件を満たすことです。

1. 画面を見なくても、音楽プレイヤーとして信頼できる。
2. 画面を見ると、音の状態が夜行絵巻として伝わる。
3. 使い込むほど、自分の音源がこの世界に住み着いていく。

## 3. Primary Audience

### Primary: 自分の音源を持つ音楽好き

- ストリーミングだけではなく、ローカル音源、デモ、購入音源、録音素材を持っている。
- ファイルを自分で管理したい。
- 派手なクラウド同期より、再生の確実性と所有感を重視する。

### Secondary: 音楽制作者・サウンドクリエイター

- デモ、ラフミックス、マスター候補、参考曲を iPhone で確認したい。
- 音量差、ピーク、構成、質感の違いを、重い DAW ではなく軽いプレイヤーで把握したい。
- AI や DSP の提案は歓迎するが、勝手に音を変えられたくない。

### Tertiary: 日本的な幻想・妖怪・ピクセルアートに強く惹かれるユーザー

- 世界観だけでなく、触って意味のあるインタラクションを求める。
- 「かわいい妖怪」ではなく「音と連動する妖怪」に価値を感じる。

## 4. Strategic Positioning

YagyoPlayer は次の市場ポジションを取ります。

> Streaming-first でも、Hi-Fi spec-first でも、DAW-lite でもない。  
> **Local-first / producer-trust / folklore-reactive music player.**

### 競合から見た差別化

| 競合カテゴリ | 競合の主価値 | YagyoPlayer の勝ち筋 |
|---|---|---|
| Apple Music / Spotify / Qobuz など | カタログ、推薦、同期、ストリーミング | ユーザー所有音源、ローカル信頼、ログイン不要の体験を主役にする |
| VLC / 汎用メディアプレイヤー | 形式対応、動画対応、万能性 | 音楽体験に絞り、再生状態を夜行絵巻として可視化する |
| Flacbox / Evermusic 系 | クラウドストレージ連携、ファイル管理、Hi-Res | クラウドではなく「自分の音源がアプリ内に住む」所有感と世界観を作る |
| JetAudio / EQ 系プレイヤー | EQ、エフェクト、音質調整 | 勝手に音を変えず、制作者が信頼できる分析・比較・A/B を重視する |
| VJ / Visualizer アプリ | ライブ映像、映像生成、演出制作 | 日常の音楽再生に統合された、意味のある音反応ビジュアルにする |

## 5. Product Pillars

### 5.1 Local-first Trust

ユーザーの音源を、ユーザーが予測できる形で安全に扱う。

- ファイルピッカーから取り込む。
- アプリ内ライブラリにコピーする。
- 取り込み結果、失敗理由、重複、保存場所を明確に伝える。
- Apple Music、クラウド、AI、DSP は初期体験の必須条件にしない。

### 5.2 Music Made Visible

妖怪や提灯は装飾ではなく、音量、拍、構造、再生状態を伝える存在にする。

- 再生中だけ意味のある反応をする。
- 無音、強いアタック、盛り上がり、曲終盤などを視覚化する。
- 常時アニメーションではなく、音楽と操作に結びついた動きを優先する。

### 5.3 Folklore as Interaction Model

和風ラベルは雰囲気語で終わらせない。

- 行列 = ライブラリ。
- 巻物 = プレイリスト。
- 提灯 = 再生位置、現在状態、音の反応。
- 狐火 = 分析、ヒント、AI / DSP 提案。
- 丑三つ時 = 時間・操作・特別状態。

### 5.4 Producer-grade Restraint

派手な演出より、再生の信頼性を優先する。

- 再生、停止、シーク、次曲、前曲を壊さない。
- Now Playing、リモートコントロール、バックグラウンド再生を重視する。
- 音を勝手に加工しない。
- 分析や補正は、根拠、比較、取り消し、A/B をセットで出す。

### 5.5 iOS-native Ritual

iOS の作法に従いながら、見た目と語彙は YagyoPlayer らしく保つ。

- MediaPlayer / App Intents / Shortcuts / 将来の MusicKit を活かす。
- VoiceOver、Reduce Motion、コントラストを最初から設計対象にする。
- 標準操作は標準らしく、世界観は体験の入口と状態表現に使う。

## 6. Differentiation Features

### 6.1 Library Confidence

「取り込めたか不安」をなくす。

- インポート結果: 成功数、失敗数、形式、保存先。
- 重複検出: 同名、同尺、同一ハッシュ。
- 削除確認: アプリ内コピーだけ消えるのか、元ファイルに影響がないのかを明示。
- メタデータ編集: title / artist / artwork / notes。
- 検索・並び替え: 追加日、タイトル、長さ、妖怪、巻物。

### 6.2 Reactive Night Parade 2.0

音反応を「ただ跳ねる」から「曲を読んでいる」へ進化させる。

- 音量: 提灯の明滅、妖怪の跳ね。
- アタック: 木魚、天狗、狐火などが強い瞬間に反応。
- 構成: Aメロ、サビ、ブレイクを空・霧・行列密度で表現。
- 終盤: 月、霧、行列速度で曲の終わりを予感させる。
- 無音: 妖怪が息を潜める。

### 6.3 Producer Check Mode

制作者がスマホでラフに確認できる「軽い検聴モード」。

- Peak / RMS / short-term loudness の簡易表示。
- クリップ疑い検出。
- モノ互換チェック。
- A/B 参照プレイリスト。
- 先頭・サビ・ラスサビなどのチェックポイント。
- 結果は自動補正ではなく、狐火の助言として表示。

### 6.4 Scrolls as Listening Contexts

巻物を単なるプレイリストではなく、用途を持つ聴取単位にする。

- Reference Scroll: 参考曲。
- Rough Mix Scroll: 制作中デモ。
- Night Walk Scroll: 気分で聴く。
- Master Check Scroll: マスター候補確認。

### 6.5 Yokai Residency

曲がアプリ内に「住む」感覚を作る。

- 各トラックに安定した妖怪を割り当てる。
- 再生回数、最近聴いた時間帯、音の特徴で反応が少し変わる。
- ただし収集ゲーム化はしない。

### 6.6 Explainable On-device Intelligence

分析や AI は、ブラックボックスではなく説明可能にする。

- 「この曲は低域が強い」ではなく、「80Hz 周辺のエネルギーが他曲より高い」のように根拠を添える。
- 外部送信が必要な処理は opt-in にする。
- 音声ファイルを勝手にアップロードしない。

## 7. Roadmap Boundaries

### Current Foundation

- ファイルピッカー取り込み。
- アプリ内ライブラリ保存。
- AVFoundation 再生。
- Now Playing / remote controls。
- 巻物プレイリスト。
- 音量メータリングに反応する夜行絵巻。
- App Shortcuts。

### Next: Library Confidence

目的: 「取り込む・探す・消す・整理する」に不安がない状態。

Release criteria:

- 検索、並び替え、削除確認がある。
- 重複検出がある。
- インポート結果が成功/失敗で明確に表示される。
- 空状態、失敗状態、長いライブラリで迷わない。
- メタデータとアートワーク編集の入口がある。

### Next: Playback Trust

目的: 画面を閉じても普通の音楽プレイヤーとして信用できる状態。

Release criteria:

- バックグラウンド再生が安定する。
- Lock Screen / Control Center / Bluetooth / AirPods 操作が自然に動く。
- シーク、次曲、前曲、音量、再開が壊れない。
- 再生中の割り込み、オーディオセッション復帰、ファイル欠落に耐える。

### Next: Night Parade Intelligence

目的: 音反応が「見た目」ではなく「曲を感じる体験」になる状態。

Release criteria:

- 音量だけでなく、アタック/無音/盛り上がりに反応する。
- Reduce Motion でも情報が失われない。
- 反応の意味が UI やドキュメントで説明できる。

### Later: Producer Check Mode

目的: 音楽制作者が「iPhoneで軽く検聴するならこれ」と言える状態。

Release criteria:

- 簡易ラウドネス、ピーク、クリップ疑い、モノチェックがある。
- A/B 参照ができる。
- すべて非破壊で、提案には根拠がある。

### Later: MusicKit / Apple Music

目的: ローカル音源を主役にしたまま、発見・照合・補完の層を追加する。

Principles:

- Apple Music 連携は opt-in。
- Apple Music 認可が必要な理由を明示する。
- ローカルファイル体験を置き換えない。

## 8. Non-goals

- 汎用ストリーミングプレイヤーになること。
- SNS、ランキング、収集ゲームを主軸にすること。
- 妖怪を増やすこと自体を目的にすること。
- DAW、マスタリングスイート、VJ ツールになること。
- Apple Music や AI を初期体験の必須条件にすること。
- 音源をユーザーの明確な同意なく外部送信すること。

## 9. Quality Bar

### Playback Quality

- 再生、停止、シーク、次曲、前曲が安定している。
- 画面を閉じても再生操作できる。
- ファイル欠落や読み込み失敗時に壊れた状態で止まらない。

### Library Quality

- 取り込んだ音源がどこにあるか説明できる。
- 削除が何を消すのか説明できる。
- 重複や失敗がユーザーに伝わる。

### Visual Quality

- 画面を見ると、YagyoPlayer で聴いている理由が一瞬で伝わる。
- 妖怪表現がかわいいだけでなく、音楽の状態を伝えている。
- ピクセルアートはにじませない。

### Accessibility Quality

- VoiceOver で主要操作が理解できる。
- Reduce Motion でも体験が破綻しない。
- 色だけに依存しない。

## 10. README Positioning Snippet

README 冒頭に置く推奨文:

```md
# YagyoPlayer

YagyoPlayer is a local-first iOS music player where your private audio library becomes a reactive Hyakki Yagyō procession.

Import your own audio files, keep them inside the app, and press play. The yokai procession, lanterns, moon, and scrolls respond to the sound instead of merely decorating it.

It is not a streaming client, not a DAW, and not a generic visualizer. YagyoPlayer is for people who still care about their own files — demos, references, purchased tracks, field recordings, rough mixes — and want a player that treats listening as a small ritual.
```

## 11. Decision Rubric

新機能は実装前に次の問いを通す。

1. 再生、管理、発見、補正のどれを明確によくするか。
2. ローカルファイル体験を弱めないか。
3. 妖怪や民話語彙が、操作や状態の理解を助けているか。
4. 音楽制作者が見ても信頼できる挙動か。
5. iOS 標準操作、アクセシビリティ、バックグラウンド再生と矛盾しないか。
6. 自動変更ではなく、ユーザーの確認・取り消し・比較があるか。

## 12. Product Mantra

**音を納める。行列が目覚める。聴くたびに、自分の音源が夜に住みつく。**
