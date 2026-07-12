# 夜行絵巻 2.0 — 唐傘基準体と正直な音量振付 設計仕様

**日付:** 2026-07-11
**状態:** 完了。初期の紫色・横向き唐傘とそのSimulator証跡は不採用。参照忠実度再設計の検証・独立QAを経て、2026-07-12にユーザー本人が唐傘(PR #13)と残り8体(PR #14)の見た目を承認し、Step 4は`main`へ統合済み
**対象:** Step 4「夜行絵巻 2.0」の最初の唐傘縦切り。残りの妖怪へ展開する前提となる共通契約

> **2026-07-12 追補・優先関係:** 唐傘の色、姿勢、輪郭、部位、`strong` の見た目は [`2026-07-12-karakasa-reference-fidelity-redesign.md`](./2026-07-12-karakasa-reference-fidelity-redesign.md) と、その [`implementation plan`](../plans/2026-07-12-karakasa-reference-fidelity-implementation.md) を正本とする。本書に残る初期の紫パレット、横向き／長い柄、横に開いた傘の記述と、それを写した検証結果は履歴としてのみ保存され、現行アート仕様・視覚承認証跡には使用しない。reducer の互換フェーズ名 `.open`、`strongOpen`、旧ファイル名に含まれる `open` は残してよいが、見た目は「傘を横に開く」ではなく正面姿勢の reaction を意味する。

## 0. 現在の唐傘正本と検証ゲート

現在候補は、全8フレームで**正面向きの赤〜珊瑚色の円錐形**を守り、**茶色の頭頂、金色の帯、中央の一つ目、曲線の笑い口、桃色の舌、淡色の一本足、一足の茶／金色の下駄**を共有する coherent frame family とする。構成は `idle 1 + walk 4 + hush 1 + strong 2` のまま、`strong` は正面形を保った anticipate／reaction の二次動作で表す。

参照忠実度テストは旧アートに対するTask 1の意味的REDをXcode 27／iOS 27で確認済みである。現在候補は、Xcode 27.0のgeneric iOS build、checked projectの **11 / 11 focused QA GREEN** と **65 / 65 full suite GREEN**（ともにskip 0）を完了した。座標tapなしのsemantic AX validationも、iPhone 17 Proのstate matrix **4 / 4**、Reduce Motion stability **1 / 1**、最小幅iPhone 17eのdefault Normal + Karakasa **1 / 1**をskip 0で通過した。Reduce Motionの`t0`／`t+2 s` full PNGは同一SHA-256で、canvas cropのdiffering bytesは0である。2名の独立native reviewerは同じASCIIソースからのPNG contact sheet／GIFとSimulator画像7枚をすべてAPPROVEDし、BLOCKER／MAJOR／MINORは0。Pro Strongの右端寄りは切断なしのINFOだけである。現在の画像とhashは[証跡ledger](../../evidence/step4-karakasa/README.md)を正本とし、binary evidence commit `150219fea8a13ed95ea65885f5e7b46101cff9e5`で9 binary blob／旧5画像削除／Draft PR本文を確認済み。ユーザー本人の見た目承認は未完了であり、視覚完了とは扱わない。

## 1. 目的

Step 3「狐火の調律」は iOS 27 の Music Understanding / Core AI を正式 SDK で再検証できるまで保留する。Step 4 はそれに依存せず、現行プレイヤーがすでに取得している `AVAudioPlayer.averagePower` だけを、意味の説明できる夜行絵巻の振付へ翻訳する。

同時に、全妖怪を SNES 相当へ描き直す前に唐傘を基準体として完成させ、解像度・色・基準線・必要フレーム・実機上の見え方を固定する。全面刷新を先に行って挙動変更で描き直すことも、現行 8bit 体だけに合わせて振付を固めて後でレイアウトを壊すことも避ける。

この機能は音楽プレイヤーの演出層である。再生音を変更せず、解析結果を音楽的事実として誇張せず、Playback Trust を後退させない。

## 2. 設計着手時の現在地

- 再生経路は `AVAudioPlayer`。15 Hz で全チャンネルの `averagePower` 最大値を読み、`0...1` に正規化して非対称スムージングしている。
- 行列の反応は固定サイン波と音量の積であり、拍・アタック・曲構成を読んでいるわけではない。
- 唐傘と天狗には hit frame、木魚には squash、狐火には flare の器がある。
- `AudioTrack` の `playCount / lastPlayedAt / playHourCounts` と、その記録・永続化経路はすでに実装済み。正本文書の「統計はゼロ」は古い。
- ライブラリ行には UUID 由来の resident が表示されるが、絵巻本体は固定 8 体で resident と未接続。
- 絵巻の Timeline は Reduce Motion で止まるが、静音・強反応・resident の静止代替と VoiceOver 値がない。`CircularWaveform` は Reduce Motion 未対応。

## 3. 成功条件

1. 唐傘の SNES 基準体が iPhone 上で正面の赤い円錐形、頭頂と帯、一つ目、笑い口と舌、一本足と下駄まで読め、全フレームで位置が跳ねない。
2. 再生中の絵巻が `level / quietProxy / strongRiseProxy` に決定論的に反応する。
3. 一定の大音量を強反応として連打せず、いったん落ちて再上昇したときだけ再発火する。
4. 短い音量谷を静音扱いせず、低レベルが継続したときだけ行列が息を潜める。
5. 現在トラックの resident が行列の先導になり、ライブラリ行の妖怪と一致する。
6. Reduce Motion でも音の状態、強反応、resident が静止姿勢・形・VoiceOver で分かる。
7. `docs/CHOREOGRAPHY.md` が、入力・近似の限界・振付・静止代替を正直に説明する。
8. 再生、停止、シーク、次曲、割り込み、ルート変更、バックグラウンド操作を壊さない。

## 4. スコープ

### 4.1 この設計で行うこと

- 行列用 SNES スプライトの共通契約を固定する。
- 唐傘の基準体を先行制作し、通常歩行・静音近似・強い立ち上がり近似を縦切りで成立させる。
- `audioLevel` を入力とする純粋な視覚用 reducer を追加する。
- 固定サイン波×音量による疑似ビートを、状態に意味のある振付へ置き換える。
- resident を現在トラックの先導役として絵巻へ接続する。
- 絵巻と円形波形の Reduce Motion、絵巻の VoiceOver 値を揃える。
- 正本文書の古い現在地と Step 4 の表現を更新し、翻訳帳を公開する。
- 唐傘の Simulator 承認後、同じ契約で残りの行列妖怪を順次刷新する。

### 4.2 今回行わないこと

- Core AI、Music Understanding、FFmpeg、libebur128、FFT、LUFS、オンセット検出、BPM・拍・サビ・曲構成解析。
- `AVAudioEngine` への移行、PCM tap、オフライン解析、再生音への DSP 適用。
- がしゃどくろ、人魂、ぬりかべの本編追加。がしゃどくろ用 125×105 規格を行列へ流用すること。
- 図鑑、解除、レベル、達成率、入手演出、妖怪から曲を逆引きする UI。
- `playCount` 等によるアンロックや段階表示。聴取統計による色・強度変化は、resident の基本接続を検証した後の別設計とする。
- 再生統計のイベント定義変更。現行の半分再生または完走という規則は触らない。

## 5. 唐傘の SNES アセット契約

### 5.1 行列用規格

- 共通キャンバス: **40×48 px**。
- 表示: **2倍の整数倍率を基準**とし、補間は常に `.none`。画面幅に応じた非整数拡縮は行わない。
- 色: 透明を除き **最大 12 色**。濃茶の輪郭／瞳、赤〜珊瑚色、生成りの目、桃色の舌、淡色の脚、茶／金色の頭頂と下駄を名前付きパレットで管理する。初期実装の紫系パレットは不採用で、再導入しない。
- 全フレームで足元基準線、視覚中心、傘の軸を一致させる。強反応でも正面の円錐形を保ち、reactionは裾・目・舌の小さな強調だけで表す。描画 rect の変化で位置を補正しない。
- 元データは現行方式と同じ 1文字=1ドットの行文字列と限定パレットを正本とする。生成画像をそのまま製品アセットにはしない。
- 行列用規格と、背景に置く巨大妖怪の規格は別物として扱う。

### 5.2 唐傘のフレーム

| 状態 | 枚数 | 意味 |
|---|---:|---|
| `idle` | 1 | 停止中の中立姿勢 |
| `walk` | 4 | 固定テンポの足運び。楽曲の拍ではない |
| `hush` | 1 | 静音近似中。傘と身体を低くし、息を潜める |
| `strong` | 2 | 正面の円錐形を保った予備動作とreaction。強い音量上昇近似への一回の反応 |

4枚歩行は一本足と下駄だけでなく、舌・傘布の内部折り／ハイライトを少量ずつずらす。`strong` は既存の `.open` phase／`strongOpen` という互換名を継承するが、表示するのは横に開いた傘や裏面ではなく正面向きのreactionである。Reduce Motion では連続再生せず、`hush` またはreactionの静止画を使う。

### 5.3 基準体ゲート

唐傘は通常時・丑三つ時、resident先導時、Reduce Motion、狭いiPhone幅を座標tapなしのsemantic AX testで検証済みである。Reduce Motionは2秒差のfull PNG同一性とcanvas crop差分0も確認した。保存済みSimulator画像について切れ、補間、基準線、周囲の旧スプライトとの衝突を2名の独立native reviewerがAPPROVED済みである。ユーザー本人が見た目を承認してから残りの妖怪へ展開する。混在状態はfeature branchとDraft PRに留め、唐傘だけが異なる画風の状態では`main`へ統合しない。

## 6. 視覚信号アーキテクチャ

### 6.1 境界と所有者

`PlaybackController` の再生方式、Audio Session、15 Hz メータリング、音量正規化は維持する。新しい `ParadeSignalReducer` はスムージング済み `audioLevel`、メータ利用可否、再生中か、時刻、リセット事由だけを受け取る純粋な値型とする。

`@MainActor` の `ParadeSignalCoordinator: ObservableObject` を `PlaybackController` が `let` プロパティとして所有する。coordinator は再生を操作せず、次だけを担当する。

- 既存 `updateMeter()` の15 Hz tickごとに、スムージング後の level を reducer へ1回渡す。
- reducer が返す単一の `ParadeSignalSnapshot` を1回だけ publish する。
- `pause / stop / seek / track load開始 / track change / load failure` の既存処理から、明示的な `reset(reason:)` を受け取る。

`audioLevel` は coordinator の snapshot.level を返す読み取り専用の互換アクセサにし、高頻度の独立した publisher を増やさない。`YagyoParadeView` と `CircularWaveform` を包む小さな表示コンポーネントだけが coordinator を監視し、root `ContentView`、ライブラリ、プレイリストを15 Hz更新へ巻き込まない。

reducer の出力は単一の `ParadeSignalSnapshot` とする。

```text
averagePower → 既存の正規化・平滑化 → ParadeSignalCoordinator (15 Hz)
                                          │
                                          ▼
                                  ParadeSignalReducer
                                          │
                                          ▼
                                  ParadeSignalSnapshot
                                    ├─ YagyoParadeView
                                    └─ CircularWaveform
```

`ParadeSignalSnapshot` は少なくとも次を持つ。

- `level: Double` — `0...1` に clamp した表示用音量。
- `activity: stopped | unavailable | quietProxy | normal` — 停止、メータ不明、曲中の低レベルを混同しない。
- `strongPhase: inactive | anticipate | open | recover` — 強反応の保持を決定論的に表す。
- `sequence: UInt64` — 新しい強反応だけを識別する単調増加番号。

複数の高頻度 `@Published` 値は増やさず、視覚部分が単一 snapshot を購読する。視覚 reducer が失敗・停止しても再生は継続する。

### 6.2 初期判定値

入力は音響解析結果ではなく、現行のスムージング済み音量である。初期値は実音源と Simulator で調整できる実装定数だが、意味は次で固定する。

- quiet 進入: 利用可能な `level <= 0.08` が **0.70秒**継続。
- quiet 離脱: `level >= 0.14`。異なる閾値でヒステリシスを持たせる。
- strong 候補: `level >= 0.55` かつ、低速基準包絡との差が `>= 0.18`。
- 低速基準包絡: 時定数 **0.80秒**の時間補正 EMA。差分判定は現在サンプルを取り込む前の基準値に対して行う。
- strong 再発火待ち: **0.45秒**。
- strong 再武装: 再発火待ちを終え、かつ `level <= 0.32` または基準包絡との差が `<= 0.06` になった後にだけ許可する。
- strong 表示: anticipate **0.07秒**、open **0.27秒**、recover **0.20秒**。
- reset 後の strong 判定ウォームアップ: **0.30秒**。
- サンプル間隔が負、または **0.50秒**を超えた場合は時間依存状態を reset し、そのサンプルでは strong を発火しない。

低速基準包絡は `alpha = 1 - exp(-dt / 0.80)`、`baseline += alpha * (level - baseline)` で更新する。閾値ぎりぎりの揺れ、一定大音量、メータ更新間隔の軽微な変動で状態がばたつかないことを優先する。

reset直後は `seeded = false`、`strongArmed = false` とする。最初の利用可能な有限サンプルで `baseline = level` と時刻を seed し、そのサンプルでは strong を出さない。ウォームアップ終了後、再武装条件を一度満たしてから `strongArmed = true` にするため、曲頭が大音量というだけでは強反応を出さない。

`pause / stop / seek / track change / load failure` では reducer を reset する。再生再開後はウォームアップが終わるまで strong を出さない。停止は quiet ではない。

### 6.3 語彙の制限

コードと技術文書では `quietProxy`／「静音近似」、`strongRiseProxy`／「強い音量上昇近似」と呼ぶ。ユーザー向け表示では、より直接的に「音量は低め」「音量が強く上昇」と表現してよいが、翻訳帳で `averagePower` 由来の近似と明記する。デジタル無音、アタック、パーカッション、拍、盛り上がり、サビを検出したとは記述しない。

## 7. 振付

| 入力 | 通常表現 | Reduce Motion |
|---|---|---|
| 停止・一時停止 | 行列、歩行フレーム、揺れを停止 | 同じ中立静止画 |
| 通常再生 | 固定歩行4 fpsの一定速度行進。levelはbob振幅と提灯 halo の大きさ・濃さだけに使う | 位置を固定し、提灯 halo の離散的な形で音量帯を示す |
| 静音近似 | 行進速度とbobを落とし、唐傘は`hush`、他の妖怪は`idle`へfallback。強反応は解除 | 唐傘は`hush`、他の妖怪は`idle`へfallbackし、低音量帯の提灯 halo と`CircularWaveform`の離散形状を残す |
| 強い音量上昇近似 | 木魚のバチと squash、唐傘の正面reaction（互換phase名は`.open`）、天狗の hit、鬼太鼓の小さな持ち上がり、狐火の flare | active strong中は正面reactionの静止姿勢と静的な破線輪郭を保持する |
| resident | 現在曲の妖怪を先頭へ移し、先導灯を与える | 同じ先頭位置と先導灯 |
| 丑三つ時 | 一つ目小僧を最後尾へ追加。共通の通常／quiet速度とbobに参加し、strong固有反応は持たない | 同じ静止追加。quietでは共通の`idle` fallbackを使う |

固定サイン波×音量による「音の山」は撤去する。歩行周期は視覚上の行進テンポであり、曲の BPM とは無関係である。強反応の根拠がない河童・雪女・琵琶牧々へ新たな hit 演出は加えない。

## 8. Residency 接続

- resident の候補順は `YokaiGallery.parade` の配列順から切り離し、互換性契約として **`[oni, mokugyo, kasa, kappa, kitsune, tengu, yuki, biwa]`** に固定する。将来 gallery を並べ替えたり追加しても既存 UUID の resident は変えない。
- 現在の UUID 由来割当を維持し、既存ユーザーの割当を移行時に変えない。
- 現在トラックの resident を 8 体の先頭へ移し、元位置からは除いて重複させない。残り 7 体は固定相対順を保つ。
- トラック未選択時は従来の固定順で、先導灯を出さない。
- 行列に渡すトラック情報は `AudioLibraryStore.tracks` の最新値を正とし、`PlaybackController.currentTrack` の古い値コピーへ統計を依存させない。
- 最初の縦切りでは playCount 等を演出へ使わない。resident が「住み着いている」ことと、「何回聴けば何かが変わる」という進行システムを分離する。

## 9. アクセシビリティ

### 9.1 Reduce Motion

- 横移動、bob、sway、連続 scale、歩行フレーム循環、波形リングの位相移動を止める。
- `level` は低・中・高の3形状の halo、quiet は `hush`、strong は正面reactionの姿勢と静的な破線輪郭、resident は先頭位置と先導灯で残す。
- 色だけに依存しない。異なる時刻に描画しても位置と scale が一致する。
- `CircularWaveform` は時間・再生位置による位相を固定し、音量帯が変わったときだけバー形状を離散的に更新する。

### 9.2 VoiceOver

絵巻は一つの accessibility element とし、月のカスタム action は維持する。値は状態変化を自動読み上げせず、フォーカス時に次の情報をまとめて読めるようにする。

```text
再生中、音量は低め、先導は唐傘
再生中、音量が強く上昇、先導は天狗
再生中、音量表示を利用できません、先導は河童
一時停止、先導は狐火
```

妖怪一体ずつを accessibility element にして読み上げを騒がしくしない。

## 10. エラーとフォールバック

- トラック未選択または再生停止は `stopped`、level 0 として描画する。
- メータ取得不能・非有限値は `unavailable` とし、neutralな行進または静止リングへフォールバックする。level 0や `quietProxy` として扱わない。
- 有限な `level` の範囲外入力は clamp する。
- resident ID の解決に失敗した場合は固定順へ戻し、再生には影響させない。
- optional の再生統計がない旧 `library.json` は従来どおり読み込む。
- reducer の reset や描画更新は audio player の play/pause/seek 成否を左右しない。

## 11. テスト

### 11.1 純粋ロジック

- quiet 進入前、0.70秒到達、ヒステリシス帯、離脱。
- strong の一回発火、一定大音量での非連打、0.45秒内の抑止、低下後の再発火。
- strong の anticipate/open/recover 時間。
- reset 後0.30秒の抑止と、pause/seek/track change/load failure の reset。
- `NaN / ±infinity` が `unavailable` となり、`0...1外` の有限値だけが clamp されること。
- reset後の最初の有限サンプルがEMAをseedし、再武装前と曲頭大音量でstrongを出さないこと。
- サンプル間隔に基づくEMA式が、固定入力列に対して決定論的な値を返すこと。
- 同一 UUID の resident が gallery 並べ替え後も同じ sprite ID になること。
- resident を先頭へ移しても8体が一度ずつ現れ、未選択時は固定順になること。

### 11.2 描画・アクセシビリティ

- 唐傘8フレームのキャンバス、baseline、透明境界、最大色数、補間なしを検証する。
- 通常/静音/strong、昼/丑三つ時、resident/非resident の組合せで切れと位置ジャンプがない。
- Reduce Motion では異なる時刻の座標・scale が同一で、静止姿勢と accessibility value が状態を保持する。
- 円形波形が Reduce Motion 中に再生位置だけでは形を変えない。

### 11.3 再生回帰

既存テストをすべて通し、特に play/pause/seek/next/previous/完走、電話・Siri割り込み、イヤホン抜去、Now Playing、欠落ファイル、バックグラウンド操作を再確認する。視覚信号テストは `AVAudioPlayer` を必要としない。

## 12. 文書更新

- `docs/CHOREOGRAPHY.md` を正式公開し、各入力、閾値、振付、Reduce Motion 代替、近似の限界を書く。
- `docs/PRODUCT_DIRECTION.md` の Step 3 を iOS 27正式SDK待ちの保留として明記する。
- 同文書の Step 4 の目的を「曲を読んでいる」から、現段階に正直な「音の大小と変化が、説明可能な振付として伝わる」へ正す。release criteria も「アタック・無音・盛り上がり検出」ではなく「音量・静音近似・強い音量上昇近似」とし、真の解析は完了条件にしない。
- `PRODUCT_DIRECTION.md` と `DESIGN_NAV.md` の「統計はゼロ」を、記録・永続化済み、絵巻への利用は未接続という現在地へ直す。
- `DESIGN_NAV.md` のアセット順を、唐傘基準体 → 縦切り検証 → 残りの妖怪へ更新する。

## 13. 導入順序とゲート

1. **契約:** reducer、residency、唐傘フレームの純粋テストを先に置く。
2. **唐傘基準体:** 40×48 px・8フレームを制作し、既存 renderer で整数倍率表示する。
3. **縦切り:** 唐傘へ quiet/strong/resident と Reduce Motion を接続し、他妖怪には既存アートで同じ snapshot の意味を接続する。
4. **文書:** 翻訳帳と正本の現在地を実装事実へ同期する。
5. **縦切りレビュー:** ネイティブの別サブエージェントがコードと仕様をレビューし、指摘を解消する。
6. **ローカル検証:** Remote Desktop Commander からローカル Codex を呼び、Xcode build/test と Simulator の通常・丑三つ時・Reduce Motion を確認する。ローカル Codex は実装やレビューを行わない。
7. **視覚承認:** 唐傘の Simulator 結果をユーザーが承認し、GitHubのDraft PRへ反映する。混在状態を `main` へ統合しない。
8. **次設計:** 唐傘の承認後、残り7体と一つ目小僧について個別の状態／フレーム matrix を別仕様として提示し、ユーザー承認後に全妖怪展開へ進む。この仕様だけでは全面展開を開始しない。

## 14. 完了の定義

この仕様の完了は、唐傘、視覚 reducer、resident 先導、Reduce Motion、VoiceOver、翻訳帳がfeature branch上で検証でき、ユーザーが唐傘の見た目を承認した時点とする。この時点ではStep 4全体も、SNES刷新も、`main`統合も完了とはしない。

Step 4全体の将来の完了条件は次とするが、残り妖怪の制作は別仕様の承認を必要とする。

- 行列8体と丑三つ時の一つ目小僧が、承認済みの行列用 SNES 契約へ統一されている。
- 混在画風が残っていない。
- すべての振付が `docs/CHOREOGRAPHY.md` の一行へ対応する。
- Playback Trust とアクセシビリティの回帰がない。
- 未使用のぬりかべと背景用がしゃどくろを、完成数の水増しとして行列へ追加していない。
