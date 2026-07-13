# Core AI / Music Understanding / DSP 実装計画

> Status: **Active — Phase 0 capability and Phase 1 deterministic DSP boundary verified; playback integration next.**
>
> 2026-07-14、ユーザーの明示承認により iOS 27 beta SDK で Step 3 を再開した。正式版 SDK での再検証はリリースゲートとして残す。現時点の再生経路は Music Understanding、Core AI、Listening Profile DSP のいずれにも依存しない。

## 1. 目的とプロダクト境界

YagyoPlayer は音楽プレイヤーであり、自動マスタリング製品ではない。本構想の目的は、ローカル音源の特徴とユーザーの明示的な好みを使って、YagyoPlayer が事前検証した少数の「聴き方」を提案することにある。

- Core AI は許可済み DSP レシピの順位だけを返す。
- ユーザーは **Original + up to three candidates** を同一ラウドネス条件で試聴する。
- 選択した候補だけを Listening Profile として保存する。
- 再生時に動くのは、版を固定した決定論的 DSP だけである。
- 未対応、解析失敗、モデル失敗、検証失敗、ルート変更時の既定値は常に Original とする。

この文書は実装可能性と安全境界を定義する。各 phase は独立して検証し、`.aimodel` 追加と再生グラフ変更は対応 phase の gate を通るまで行わない。

## 2. Evidence labels

### Confirmed facts（iOS 27 beta documentation）

以下は、現時点の Apple の iOS 27 ベータ向けドキュメントから採用する最小限の事実である。正式版 SDK では API 名、入力形式、結果型、対応端末、実行条件を必ず再確認する。

1. Music Understanding は iOS 27 ベータのフレームワークとして案内されている。
2. `MusicUnderstandingSession` は、ファイル解析では `AVAsset`、ストリーム解析では `AsyncSequence<AVReadOnlyAudioPCMBuffer>` を入力境界とする。集約結果は rhythm、key、loudness、pace、structure、`instrumentActivity` を含む。progressive partial result が明示されているのは loudness であり、他の結果まで逐次返るとは扱わない。
   - loudness は BS.1770 に基づく integrated、short-term、momentary、peak を含む。ただし、この peak は true peak として文書化されていないため、true-peak safety の根拠には使わない。
   - instrument activity の分類は bass、drum、vocal、other である。structure は時間境界であり、verse／chorus の意味ラベルではない。
   - これらの境界は、任意のローカルファイル形式、結果の永続化可否、端末条件まで保証しない。
3. Core AI は、開発者が用意する `.aimodel` を使った汎用オンデバイス推論フレームワークであり、名前付きの NDArray／pixel-buffer 値をモデル入出力として扱う。DSP レシピ提案器は内蔵されていないため、YagyoPlayer 用モデル、schema、学習・評価、版管理は開発側で用意する。
4. Phase 0 の作業ブランチには availability-gated `MusicUnderstandingAdapter` があるが、UI、キャッシュ、再生開始、render callback からは未接続である。Core AI と Listening Profile DSP の実行時依存はない。

Apple reference:

- [Music Understanding](https://developer.apple.com/documentation/musicunderstanding)
- [Core AI](https://developer.apple.com/documentation/coreai)

### Verified capability evidence（2026-07-14、Xcode 27 beta）

- Xcode 27.0 build `27A5194q` / iOS 27.0 SDK の Swift interface で、`MusicUnderstandingSession` の `AVAsset` 入力、六つの集約結果、cancellation、loudness stream を確認した。
- iOS 26 deployment target のアプリへ adapter を追加し、生成バイナリが `MusicUnderstanding.framework` を weak link することを `otool -L` で確認した。iOS 26.5 Simulator では framework をロードせず `.requiresIOS27` を返して test host が正常起動した。
- iOS 27 Simulator で、24秒・44.1 kHz・stereo のローカル CAF を `AVURLAsset` から解析し、全結果を Apple 型から版付き Codable 型へ変換した。解析テストは約2.4秒で完了した。
- 合成素材の integrated loudness は Music Understanding `-22.8568916 LUFS`、現行 `KitsunebiAnalyzer` `-22.8568924 LUFS`（差 約 `0.0000008 LU`）。120 BPM、49 beats、13 bars、2 sections、3 segments、6 phrases と楽器 activity も返った。
- Apple `peak` は同素材の sample peak と一致した。API も true peak と明記しないため、True Peak、clip run、stereo correlation は引き続き `KitsunebiAnalyzer` を正本とする。
- momentary loudness用の純粋reducerは `<= -70 LUFS` で無音へ入り、`> -65 LUFS` で抜ける。デジタル無音の `-∞` と未取得を別のapp-owned値として保持し、JSONへ非有限値を保存しない。
- capability lane は六次元の結果、task cancellation、存在しないassetのerror境界を含め `7 / 7`、通常suiteは `151 / 151`、skip 0。framework由来errorはapp-owned failureへ変換し、cancel時は `CancellationError` を優先する。
- Simulator では Core ML / MPSGraph の互換性 warning が記録されたが解析は成功した。性能、警告の有無、対応端末、保護コンテンツ、実曲精度は iOS 27 実機で未確認であり、Phase 0 の残件とする。

### Design inferences（確認済み事実から導く設計判断）

- Apple の結果型をアプリ内部へ直接拡散せず、`MusicUnderstandingAdapter` が版付き `FeatureSnapshot` に変換する。
- Music Understanding で不足する、または正式版 SDK で取得できない少数の特徴だけを、YagyoPlayer の bounded DSP feature extractor が非リアルタイムで補う。
- Core AI の出力をレシピ ID と順位スコアに限定すれば、AI を再生スレッドと係数生成から切り離せる。
- AI の出力と永続化データを同じ `SuggestionValidator` に通し、未知・破損・旧版データを fail closed にできる。
- プレビューは比較のための一時的な機能であり、ユーザーの確定操作なしに再生プロファイルを変更しない。

### Assumptions to validate（未確認の仮定）

以下は正式版 SDK capability spike と実機検証で反証可能な仮定として扱う。

- Listening Profile の初期提供範囲はヘッドホン／イヤホン出力ルートに限定できる。
- Music Understanding の必要な結果を、ライセンスと API 契約に反しない形でアプリ所有の `FeatureSnapshot` としてローカルキャッシュできる。
- ユーザーの好みを、小さな版付き preference vector として端末内に永続化できる。
- 初期の `DSPRecipeCatalog` は人が測定・試聴した少数の固定レシピで十分な選択幅を作れる。
- Original と候補を、正のゲインを足さずに最も静かな候補へ揃える方式で、意味のあるラウドネスマッチ比較ができる。
- `.aimodel` のサイズ、推論時間、メモリ、電力、熱が音楽再生を妨げない範囲に収まる。

### Non-goals（対象外）

- AI が任意のエフェクト、順序、係数、実行可能 DSP グラフを生成すること。
- 曲ごとの自動マスタリング、連続的な自動補正、ユーザー未承認のプロファイル変更。
- 音声、Music Understanding 結果、特徴量、好みをクラウドへアップロードすること。
- 加工済みファイルの破壊的保存、書き出し、配信向けラウドネス仕上げ。
- FFmpeg または FFmpegSwiftSDK の採用。
- ダイナミクス処理、非線形処理、ステレオワイドニング、オーバーサンプリングを v1 に含めること。
- Parade reaction analysis を Listening Profile DSP の解析エンジンとして扱うこと。

## 3. Bounded data flow

論理フローは次の形から広げない。

```text
Local audio
  -> MusicUnderstandingAdapter + bounded DSP feature extractor
  -> FeatureSnapshot
  -> CoreAISuggestionProvider
  -> SuggestionValidator
  -> Versioned DSPRecipeCatalog
  -> Original + up to three loudness-matched previews
  -> explicit user selection
  -> ListeningProfileStore
  -> deterministic DSP runtime
```

Core AI が返せるのは `catalogVersion`、許可リスト内の `recipeID`、有限な `rankingScore` だけである。Core AI は実行可能グラフ、エフェクト順序、周波数、Q、ゲイン、バイカッド係数を返さない。

`SuggestionValidator` は、次のどれか一つでも見つけたら応答全体を拒否し、候補を Original のみに戻す。

- `DSPRecipeCatalog` に存在しない recipe ID
- 重複 recipe ID
- NaN、正負の Infinity を含む特徴量またはスコア
- 現在の出力ルート、チャンネル数、サンプルレート、端末能力と互換性がないレシピ
- 要求した catalog/model/schema version と一致しない応答
- 0〜3 件の上限、型、順序、署名済みアセット境界に違反する応答

候補が 0 件になることは正常系であり、Original のまま再生する。

## 4. Component contracts

### 4.1 `MusicUnderstandingAdapter`

- iOS 27 のコンパイル可否、OS availability、フレームワークのランタイム availability を一か所で判定する。
- `MusicUnderstandingSession` の入力生成と結果読解を閉じ込める。
- Apple の型を再生層や UI へ公開せず、取得元と版を記録したアプリ内部型へ正規化する。
- cancellation、タイムアウト、解析不能、非対応形式を通常の失敗として返す。
- 再生開始を待たせず、解析は render thread 外で行う。

正式版 SDK spike では、少なくともローカル URL／アセットの入力境界、保護コンテンツ、部分ファイル、結果の再利用条件、端末対応条件をコンパイル実験で確定する。

### 4.2 `BoundedDSPFeatureExtractor`

- Music Understanding だけではレシピ順位づけに不足すると実証された特徴だけを計算する。
- 特徴セット、窓長、精度、処理時間、メモリ上限を版付きで固定する。
- 音声全体の再レンダーや mastering target 推定は行わない。
- 有限値チェックに失敗した特徴は破棄し、Snapshot 全体を unavailable とする。
- モデル都合で無制限に特徴を増やさない。

### 4.3 `FeatureSnapshot`

最低限、次の値を持つ immutable value とする。

```text
FeatureSnapshot {
  schemaVersion
  sourceFingerprint
  analyzerVersion
  availability
  boundedFiniteFeatures
  createdAt
}
```

生の音声や Apple の不透明なセッションオブジェクトは保存しない。`sourceFingerprint` はファイル内容を外部へ送らないローカル識別子とし、ファイル変更、analyzer version、OS/API compatibility key の変更でキャッシュを無効化する。

### 4.4 `CoreAISuggestionProvider`

アプリ側は protocol で隔離し、Core AI 実装と deterministic test double を差し替えられるようにする。

```text
rank(snapshot, neutralOrVersionedPreference, catalogManifest)
  -> RankedRecipeIDs
```

- `.aimodel` は許可済み recipe ID の順位づけだけを学習目的とする。
- 入力と出力は小さな型付き schema にする。
- タスク cancellation と一回限りのフォールバックを持つ。
- フレームワーク、モデル、アセット、端末が利用不能ならネットワークへ切り替えず Original を返す。
- 推論は再生開始、seek、route change の同期経路に置かない。

### 4.5 `SuggestionValidator`

AI 応答、fixture、永続化から復元した選択のすべてが通る共通境界とする。

検証順序は **型／版 → `isFinite` → allow-list → compatibility → 数量 → 安全範囲** とする。NaN/Infinity は clamp の前に拒否する。clamp は有限で、わずかに範囲を外れたアプリ所有値にだけ使い、非有限値や未知 ID を「直したこと」にしない。

### 4.6 `Versioned DSPRecipeCatalog`

レシピはコードまたは署名・版管理されたアプリ同梱 manifest で定義し、モデルから生成しない。

```text
DSPRecipe {
  catalogVersion
  recipeID
  localizedIntentKey
  compatibility
  inputHeadroom
  eqBands[3...5]
  outputTrim
  measuredSafetyEvidence
}
```

recipe ID の意味を版の途中で変更しない。削除・調整時は catalog version を上げ、旧プロファイルは Original へ安全に移行する。モデルが参照する catalog manifest とランタイム catalog が一致しない限り候補を表示しない。

### 4.7 Preview and explicit selection

- 比較面には Original と最大 3 候補だけを表示する。
- 各候補は意味を断定する音質評価ではなく、ローカライズ可能な短い聴感意図と recipe ID を持つ。
- ラウドネスマッチは比較集合の最も静かな項目へ減衰で揃え、正の preview gain は使わない。
- 切り替えは短いランプ／クロスフェードを使い、クリック、位相ずれ、再生位置の変化を起こさない。
- 「選択してデフォルトにする」と「Original に戻す」を明示操作にする。試聴だけでは保存しない。
- VoiceOver で Original／候補名／選択状態／適用ボタンを区別できるようにする。

### 4.8 `ListeningProfileStore`

保存対象は、選択済み recipe ID、catalog version、preference schema version、小さな構造化 preference vector、対象ルート範囲だけとする。音声、自由記述プロンプト、自由形式 JSON 係数は保存しない。

読み込み時に必ず `SuggestionValidator` と catalog compatibility を再評価する。未知版、破損、対象外ルートなら削除せず隔離し、再生には Original を使う。ユーザーの選択履歴を暗黙に曲別自動適用ルールへ変換しない。

### 4.9 Deterministic DSP runtime

再生スレッドが受け取るのは、検証済み recipe から control thread 上で作った immutable parameter snapshot だけである。

- render callback 内で Music Understanding、Core AI、キャッシュ、永続化、ログ、ロック、割り当てを呼ばない。
- snapshot は固定容量SPSC mailboxを介し、buffer boundaryの先頭で完成済みの最新1件だけを交換する。mailboxが満杯ならcontrol側の新規投入を拒否し、render側が読んでいるslotを上書きしない。producer／consumer endpointはone-shot builderから各1つだけ取得でき、noncopyableかつmutating APIとして同一endpointの安全でない共有を型で防ぐ。
- bypass／Original は恒久的な first-class path とし、DSP 障害時にも再生を継続する。
- 出力が非有限になった場合は診断をレート制限し、そのバッファを安全化したうえで Original へ latch する。
- interruption、seek、background、route change は解析や推論より再生状態機械を優先する。

## 5. v1 の固定 DSP 契約

v1 は次の固定順序だけを許す。

```text
input headroom
  -> 3–5 band EQ
  -> output trim
```

- EQ band gain は各バンド **±3 dB 以内**。
- Q は事前測定した moderate range だけを catalog が持つ。モデルは Q を出力しない。
- output trim は 0 dB 以下とし、正の出力ゲインを許可しない。
- input headroom は EQ の最悪時ブーストと測定ピークを考慮して各 recipe に固定する。
- レシピ内のバンド数、順序、型は固定し、実行時に挿入・削除・並べ替えをしない。
- v1 に compressor、limiter、saturation、clipper、bass recovery、stereo widening、oversampler を入れない。
- 各レシピは silence、impulse、sine、DC、noise、代表曲コーパスで finite、ピーク、周波数応答、bypass、切替ノイズを検証してから catalog へ追加する。

この小さなチェーンでも良い候補が作れない場合は、段数を増やさず Original のまま止める。

## 6. Mastering-App から借りる境界設計

Mastering-App は依存先ではなく、失敗しにくい境界の参考資料としてのみ扱う。リンクは監査時点の commit `73e21fa47da687c2b6e90ac273e16efb2bce8fda` に固定する。

| Reference | 借りる考え方 | YagyoPlayer での縮小適用 |
|---|---|---|
| [`MasteringAdvising.swift`](https://github.com/tinypony777/Mastering-App/blob/73e21fa47da687c2b6e90ac273e16efb2bce8fda/Mastering-App/Protocols/MasteringAdvising.swift) | structured advisor protocol と dependency injection | `CoreAISuggestionProvider` protocol。Core AI と fixture を同じ型付き契約にする |
| [`AIAdviceController.swift`](https://github.com/tinypony777/Mastering-App/blob/73e21fa47da687c2b6e90ac273e16efb2bce8fda/Mastering-App/Features/AudioProcessor/Controllers/AIAdviceController.swift) | typed state、cancellation、layered fallback | idle/analyzing/suggesting/ready/unavailable の小さな状態機械。失敗は Original へ一方向に戻す |
| [`FMAvailabilityChecker.swift`](https://github.com/tinypony777/Mastering-App/blob/73e21fa47da687c2b6e90ac273e16efb2bce8fda/Mastering-App/Services/FoundationModels/FMAvailabilityChecker.swift) | compile-time、OS、runtime の availability gate | `canImport`、`#available`、runtime availability を adapter 内で三段階確認する |
| [`FMAdviceSchema.swift`](https://github.com/tinypony777/Mastering-App/blob/73e21fa47da687c2b6e90ac273e16efb2bce8fda/Mastering-App/Services/FoundationModels/FMAdviceSchema.swift) | 小さな typed schema。exactly-three candidate schema の表現 | YagyoPlayer は **最大** 3 件の ID/score schema を独自定義する。Mastering-App の exactly-three concept は現在の controller で active ではないため、稼働実績とはみなさない |
| [`AdvicePreferenceTuner.swift`](https://github.com/tinypony777/Mastering-App/blob/73e21fa47da687c2b6e90ac273e16efb2bce8fda/Mastering-App/Services/AI/AdvicePreferenceTuner.swift) | user preference delta と structured neutral state | 版付き preference vector に neutral を明示し、無選択を暗黙の補正値にしない |
| [`MasteringConfigValidator.swift`](https://github.com/tinypony777/Mastering-App/blob/73e21fa47da687c2b6e90ac273e16efb2bce8fda/Mastering-App/Services/ML/MasteringConfigValidator.swift) / [`MasteringDSPSafetyLayer.swift`](https://github.com/tinypony777/Mastering-App/blob/73e21fa47da687c2b6e90ac273e16efb2bce8fda/Mastering-App/Services/Audio/MasteringDSPSafetyLayer.swift) | schema clamp と proposal safety layer を共通境界に置く | ID、版、compatibility、finite、範囲を一度だけ検証し、安全性を UI と DSP の両方で共有する |
| [`MacroToSnapshotMapper.swift`](https://github.com/tinypony777/Mastering-App/blob/73e21fa47da687c2b6e90ac273e16efb2bce8fda/Mastering-App/Services/ML/MacroToSnapshotMapper.swift) / [`MasteringParamSnapshot.swift`](https://github.com/tinypony777/Mastering-App/blob/73e21fa47da687c2b6e90ac273e16efb2bce8fda/Mastering-App/Services/Audio/DSPKernel/MasteringParamSnapshot.swift) | 構造化 proposal から deterministic parameter snapshot への一方向変換 | recipe ID → catalog recipe → immutable EQ snapshot のみを許可する |
| [`RealtimePreviewEngine.swift`](https://github.com/tinypony777/Mastering-App/blob/73e21fa47da687c2b6e90ac273e16efb2bce8fda/Mastering-App/Services/Audio/RealtimePreviewEngine.swift) | preview before commit、schedule 世代管理 | 現在の再生位置を維持した A/B 切替と、試聴から明示保存までの分離だけを借りる |
| [`MasteringOperationalContract.swift`](https://github.com/tinypony777/Mastering-App/blob/73e21fa47da687c2b6e90ac273e16efb2bce8fda/Mastering-App/Services/Audio/DSPKernel/MasteringOperationalContract.swift) | supported stage と bypass の single source of truth | v1 の固定 EQ chain、互換条件、Original path を catalog contract に集約する |
| [`SessionStore.swift`](https://github.com/tinypony777/Mastering-App/blob/73e21fa47da687c2b6e90ac273e16efb2bce8fda/Mastering-App/Services/Learning/SessionStore.swift) / [`ModelAssetManager.swift`](https://github.com/tinypony777/Mastering-App/blob/73e21fa47da687c2b6e90ac273e16efb2bce8fda/Mastering-App/Services/AI/ModelAssetManager.swift) | versioned persistence と model asset 管理 | Snapshot、preference、catalog、`.aimodel` の版互換性を明示し、異なる版を混ぜない |
| [`OfflineNetworkPolicy.swift`](https://github.com/tinypony777/Mastering-App/blob/73e21fa47da687c2b6e90ac273e16efb2bce8fda/Mastering-App/Services/Network/OfflineNetworkPolicy.swift) / [`NetworkZeroTests.swift`](https://github.com/tinypony777/Mastering-App/blob/73e21fa47da687c2b6e90ac273e16efb2bce8fda/Mastering-AppTests/NetworkZeroTests.swift) | offline contract と network-zero verification | 提案経路に remote provider を登録できない構成と、通信ゼロを検出するテストを持つ |
| [`DSPKernelTests.swift`](https://github.com/tinypony777/Mastering-App/blob/73e21fa47da687c2b6e90ac273e16efb2bce8fda/Mastering-AppTests/DSPKernelTests.swift) / [`DSPRegressionTests.swift`](https://github.com/tinypony777/Mastering-App/blob/73e21fa47da687c2b6e90ac273e16efb2bce8fda/Mastering-AppTests/DSPRegressionTests.swift) | 固定 commit が直接示す sine、silence、impulse、DC と、該当テストの 48 kHz・固定 chunk・bypass evidence | 既存 evidence を最小の出発点として使い、YagyoPlayer の EQ chain 用マトリクスは独自に作る |

上記の固定 commit は、noise 入力や 44.1/48/96 kHz 横断マトリクスを既存 evidence としては示していない。これらは §9 で定める **YagyoPlayer の新規検証要件**であり、Mastering-App の実証済み範囲として引用しない。

### 6.1 重要な差分: non-finite validation

監査時点の Mastering-App の `MasteringConfigValidator` は範囲 clamp を持つ一方、入力値に対する明示的な `isFinite` チェックがない。NaN は通常の比較や clamp をすり抜け得るため、この点はコピーしない。

YagyoPlayer は **NaN/Infinity を clamp より前に拒否**し、AI 応答、FeatureSnapshot、保存済み profile、recipe manifest、最終 parameter snapshot の各入口で finite を保証する。DSP 出力側の finite guard は最後の被害抑止であり、入力検証の代用にはしない。

### 6.2 Mastering-App からコピーしないもの

- 10/11-stage mastering chain と、その全段を前提にした operational contract
- 79→9 CoreML pipeline
- rule-generated auto-processing／自動マスタリング提案
- nearest-cluster LocalLLM
- cloud LLM、network provider、remote fallback
- free-form coefficient JSON またはモデル生成 DSP parameter
- LUFS target への re-render、bass recovery、自動ラウドネス補正
- native/Swift oversampler と非線形段
- export 向け limiter、clipper、true-peak mastering contract

これらは YagyoPlayer の「少数の聴き方を明示選択する音楽プレイヤー」という境界を越え、複雑性、故障面、検証コストを増やすため採用しない。

### 6.3 提供された Swift DSP Reference の監査差分

2026-07-14 に提供された `DSP_Reference` は、完成品として直接移植せず設計資料として監査した。`ParamEQKernel.process` は `min(frameCount, maxFrames)` までしか処理せず超過tailを残すこと、snapshotの二面swapはconsumerが旧面をコピー中に次のwriterが上書きできること、previewのoutput gainがユーザー音量と同じmixer経路で正値も許すことを確認した。

YagyoPlayer は次だけを縮小して独自実装する。

- RBJ peaking EQの係数設計をcontrol側で行い、Float化後にもfinite／安定性を再検証する。
- 3〜5 bandの完成済み係数、input headroom、非正output trimを一つのimmutable snapshotにする。
- render側は要求frameを全量処理するか明示失敗し、部分処理しない。
- pure kernelの`invalidBuffers`は未処理outputを変更しない。AVAudioUnit adapter接続時はこの結果を受けて要求frame全体をzero-clearする契約と回帰テストを必須にする。
- Original、DSP safety trim、ユーザー音量、将来のラウドネスマッチ乗数を別の責務として保持する。
- snapshot handoffは二面swapをコピーせず、所有権が明確なcapacity 4のbounded SPSC mailboxとして実装する。noncopyableなproducer／consumerは各1つに限定し、release／acquireでslot公開を同期する。consumerは公開済みbatchの最新snapshotだけを定数時間で取り出す。

## 7. Availability, privacy, and fallback

### Availability

`FMAvailabilityChecker.swift` の分層を参考にしつつ、Music Understanding と Core AI を別々に評価する。

1. SDK に module が存在するか。
2. 実行 OS が API を満たすか。
3. 現在の端末、モデルアセット、ランタイム状態で利用可能か。
4. 入力音源が Music Understanding の対応境界内か。

どの段階の失敗もアプリ起動や通常再生の失敗に昇格させない。Listening Profile UI を unavailable とし、Original で続行する。

### Privacy / offline contract

- 解析、推論、保存、DSP は端末内で完結する。
- remote endpoint、remote model provider、analytics payload に音声・特徴・嗜好を渡さない。
- ネットワークが無い状態を縮退運転ではなく標準のテスト条件にする。
- model/catalog asset の更新方針が将来必要になっても、本計画とは別の明示承認なしにダウンロード経路を追加しない。

### Fail-closed matrix

| Failure | User-visible result | Playback result |
|---|---|---|
| Framework/model unavailable | Listening Profile unavailable | Original |
| Analysis cancelled or unsupported | 候補なし | Original |
| Invalid/non-finite AI output | 候補なし、必要なら非侵襲的な再試行案内 | Original |
| Catalog/model/schema mismatch | 候補なし | Original |
| Saved profile incompatible | 再選択を案内 | Original |
| Route changes outside profile scope | 選択状態を一時停止 | Original |
| DSP finite/safety guard trips | レート制限した診断 | Originalへ latch、再生継続 |

## 8. Phased delivery

各 phase は独立したレビューと合格証拠を必要とする。前 phase の合格は次 phase の自動承認ではない。

### Phase 0 — SDK capability spike（進行中）

- iOS 27 beta SDK で `MusicUnderstandingSession` の境界を先行実証し、正式版 Xcode／iOS SDK で差分を再検証する。
- ローカル音源の入力、結果型、cancellation、availability、対応端末、保護コンテンツ、オンデバイス条件を実機で記録する。
- 最小の開発者提供 `.aimodel` を読み込み、既知入力に対する型付き出力、レイテンシ、メモリ、電力を測る。
- Phase 0 では adapter の弱リンクと app-owned 型への正規化までを許可し、UI、キャッシュ、再生グラフへは接続しない。仮定が成立しなければ本計画を更新し、通常再生を維持する。

**Gate:** API boundary と端末条件をテストで再現でき、Apple beta 前提との差分が文書化されていること。

### Phase 1 — Deterministic DSP catalog and preview without AI（pure core 進行中）

- 固定 EQ chain、Original/bypass、`DSPRecipeCatalog`、snapshot、プレビュー UI を fixture recipe だけで作る。
- 正のゲインを使わないラウドネスマッチと明示選択フローを検証する。
- AI がなくても安全性、音切れ、比較可能性、アクセシビリティを評価できるようにする。

2026-07-14 時点で、3〜5 band peaking EQ、±3 dB、Q `0.5...2.0`、`20 Hz...min(20 kHz, Nyquist × 0.95)`、非正input headroom／output trimを検証してimmutable snapshotへ変換するpure coreを追加した。input headroomは各bandの正boost合計以上の減衰を必須とし、output trimで内部余裕を代用しない。render kernelはmono/stereo、44.1/48/96 kHz、可変chunk、有限入力に対するOriginalのbit transparency、非有限入力のzero化、impulse、中心周波数応答、DC、決定論的noise、denormal、channel独立、全buffer alias、buffer境界適用、invalid state時Original latch、無効frameの非部分処理、同一周波数5-band最大boostをfocused test `16 / 16` で確認した。さらにcapacity 4のSPSC mailboxとrender-owned processorを追加し、one-shot endpoint所有権、満杯時no-overwrite、stale snapshotの定数時間破棄、buffer先頭での最新世代適用、20,000世代のring wrapとpayload整合性をfocused test `3 / 3` とThread Sanitizerで確認した。合同focused testは `19 / 19`。PlaybackControllerにはfailure-atomic load/seek契約とexact schedule identity照合を持つ再生backend境界を追加し、既存controller 22件＋seam 8件を `30 / 30`、app full suiteを `178 / 178`、skip 0で確認した。既定は従来のAVAudioPlayer adapterであり、Fixed EQ、AVAudioEngine、UIは未接続なので再生音は変わらない。

**Gate:** DSP と UX の価値が AI 抜きで成立し、bypass、切替、リアルタイム制約に合格すること。

### Phase 2 — Music Understanding adapter and cache

- Phase 0 adapter を production contract へ昇格し、bounded extractor、`FeatureSnapshot`、app-owned cache を追加する。
- キャッシュ invalidation、キャンセル、非対応音源、破損値、offline を試験する。
- 特徴抽出が再生開始や render callback をブロックしないことを測る。

**Gate:** 必要特徴が安定して有限値へ正規化でき、プライバシーと性能予算を満たすこと。

### Phase 3 — Core AI ranker

- protocol の背後に Core AI provider と `.aimodel` を接続する。
- typed output を `SuggestionValidator` へ通し、0〜3 recipe IDs に限定する。
- fixture dataset で順位品質、neutral preference、偏り、退行、モデル版互換性を評価する。

**Gate:** deterministic baseline より意味のある候補順位を作り、無効入力が 100% Original へ fail closed すること。

### Phase 4 — Explicit Listening Profile persistence

- 明示的な確定／解除、版付き preference vector、route scope、migration を実装する。
- 試聴、キャンセル、アプリ終了、catalog 更新、破損ストアで意図しない保存がないことを確認する。

**Gate:** 保存された選択をユーザーが説明・解除でき、旧版または不正データを自動適用しないこと。

### Phase 5 — Playback integration

- 検証済み immutable snapshot のみを既存再生経路へ渡す。
- interruption、seek、background、queue transition、route change、audio session recovery を回帰試験する。
- Original latch と診断を統合する。

**Gate:** 通常再生の既存契約に退行がなく、render thread に allocation／lock／I/O がないこと。

### Phase 6 — Real-device release gate

- サポート予定の実機、ヘッドホン、有線／Bluetooth ルート、代表フォーマットで長時間試験する。
- battery、thermal、memory、CPU、切替ノイズ、ラウドネスマッチ、accessibility、offline を測定する。
- モデル、catalog、feature schema、profile schema の release versions と rollback を固定する。

**Gate:** 全必須マトリクスに測定証拠があり、未解決の安全・再生退行・privacy 問題がゼロであること。満たさなければ機能を同梱せず Original のみでリリースする。

## 9. Verification plan

### Contract / validator tests

- unknown、duplicate、non-finite、incompatible、out-of-version recipe output を個別 fixture で与え、すべて Original へ戻る。
- NaN、`+Infinity`、`-Infinity` を clamp 前に拒否する。
- 0、1、2、3 件は受理し、4 件以上は応答全体を拒否する。
- catalog/model/schema/profile version の全不一致組合せを拒否する。
- cancellation と availability change が stale proposal を UI または store に到達させない。

### DSP correctness / safety tests

- Original/bypass の sample transparency。避けられない graph latency がある場合は同一 latency で比較し、契約値を固定する。
- silence、impulse、sine sweep、DC、noise、denormal、極端レベルで finite output。
- 44.1/48/96 kHz、mono/stereo、異なる render chunk size で係数と出力が安定する。
- すべての catalog recipe が ±3 dB、moderate Q、非正 output trim、固定順序を満たす。
- 切替時の click/pop、peak excursion、position drift を測る。

### Playback regression tests

- route changes、headphone disconnect、Bluetooth profile change で Original へ安全に戻る。
- interruption、seek、background/foreground、queue transition、end-of-track、audio-session reset 後も選択と再生状態が整合する。
- render thread の allocation、lock、file/network I/O、AI invocation がゼロである。

### Perceptual / UX tests

- Original と全候補の loudness-matched switching が音量差だけの選好を作らない。
- Original が常に見つけられ、1 操作で戻せる。
- 候補 0〜3 件、loading、unavailable、error が VoiceOver、Dynamic Type、Reduce Motion で理解できる。
- ユーザーの確定前に profile が保存・適用されない。

### Device / operational tests

- battery drain、thermal state、CPU、memory、解析時間、推論時間を代表曲と長時間再生で測定する。
- airplane mode、未接続ネットワーク、通信監視下で完全に offline 動作し、外向きリクエストがゼロである。
- `.aimodel` 欠落、破損、旧版、低ストレージ、memory pressure で通常再生が継続する。

## 10. Open questions and stop conditions

正式版 SDK spike で次を解決する。

1. `MusicUnderstandingSession` が YagyoPlayer のローカル音源をどの入力型・権限・DRM 条件で受け取れるか。
2. 結果にレシピ順位づけへ十分な特徴があるか。不足分を bounded extractor で安全に補えるか。
3. Core AI の対応端末、`.aimodel` packaging、更新、署名、メモリ、推論 scheduling の正式契約。
4. ヘッドホンルートだけに安全に限定できるか。Bluetooth codec／sample-rate change と profile compatibility をどう表すか。
5. ラウドネスマッチの許容差と、減衰のみの比較が実機で十分か。
6. preference vector が候補の有用性を改善するか。改善しなければ保存せず neutral のままにする。

次のいずれかに該当したら統合を止め、通常の Original 再生を維持する。

- ローカル音源入力またはオンデバイス条件が Apple の正式契約で成立しない。
- AI を使わない固定 catalog／preview が聴取価値または bypass 安全性を示せない。
- render-thread 制約、battery、thermal、memory の予算を満たせない。
- 通信ゼロ、明示選択、Original fallback を保証できない。
- モデル順位品質が deterministic/neutral baseline を安定して上回らない。

## 11. Related YagyoPlayer documents

- [Product Direction](PRODUCT_DIRECTION.md)
- [WWDC26 Music notes](WWDC26-Music-notes.md)
- [Archived Step 3 DSP draft](../Draft/Step3-One-Ear/README.md)

Listening Profile を production runtime へ接続するには、Phase 0 の実機／正式版 SDK 証拠、Phase 1 の DSP/UX 証拠、更新された正本仕様が必要である。
