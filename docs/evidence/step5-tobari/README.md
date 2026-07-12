# Step 5 狐火の帳 Phase A・証跡ledger

[設計仕様](../../superpowers/specs/2026-07-12-kitsunebi-no-tobari-design.md)のPhase A(一画面検聴)の証跡です。

## 実装

- `KitsunebiAnalyzer` / `KitsunebiAnalyzerEngine`: [Mastering-App](https://github.com/tinypony777/Mastering-App)(commit `73e21fa`)の `KWeightingFilter` / `LUFSMeter` / `TruePeakMeter` / `AudioAnalyzer` のstreaming手法を移植し、仕様の補修2点+レビュー由来の補修を適用した1パスchunked解析。
  - 補修1: Short-term(3秒)も100msホップ30本のリングでstreaming化。サンプル数に比例するバッファは持たない(Integratedのゲーティングにのみ100msあたり1つのブロックラウドネス値を保持する)。
  - 補修2: クリップ疑いを「|x| ≥ 0.999 が3サンプル以上連続するラン」の回数+開始位置(開始時刻の小さい8件・昇順)へ。ランはチャンク境界を越えて追跡する。
  - レビュー補修A: **非48kHzのK-weighting係数式を移植元のRBJ cookbook近似からDe Man系のパラメータ化(pyloudnormと同一)へ差し替え**。旧式は44.1kHzでEBU基準信号が-20.246 LUFS(許容±0.1の外)だった。新式はsr=48000を代入すると公式Table 1/2を機械精度で再現する。
  - レビュー補修B: **非有限値の遮断**。+inf/NaNを含む壊れたfloat音源でも、Sample Peak / True Peak / 相関が非有限のままJSONへ到達しない(nil=計測不能へ)。旧実装ではlibrary.jsonの保存が以後すべて失敗し得た。
  - レビュー補修C: チャンネル重みの決め打ち(index 3=LFE)を撤去。多チャンネルは**チャンネルラベル**(タグはAudioToolboxで展開)からBS.1770の重み(サラウンド1.41、LFE除外)を導くため、MPEG/AAC/AudioUnit等どのタグ順序でも正しく載り、**ラベル不明時は等重みでチャンネルを落とさない**。モノ互換の相関も実際のL/Rラベルの位置で計算する(例: C,L,R,…配置ではch1×ch2)。
- `TobariMetrics`: `contentHash` + `analyzerVersion` キーの検聴キャッシュ(library.json後方互換、無限大はnilで表現)。保存失敗時はメモリ上もロールバック(他の編集系と同じ不変条件)。
  - 設計note: 仕様§6の`AnalysisStore`は独立コンポーネントではなく、`AudioTrack.tobariMetrics`への保存+同一`contentHash`の共有照合(`sharedTobariMetrics`)で実現した。重複取込された同一音源は再解析しない。
- `TobariView` / `TobariAnalysisController`: トラック長押し→「狐火の帳で検聴」で開く一画面。解析・hash backfill(SHA-256のファイル全読み)ともに低優先度のバックグラウンドタスクで、メインスレッドを塞がない。進捗・失敗を明示し再生へ影響しない。帳を閉じても解析は完走し、キャッシュ保存まで済ませる(途中中断で結果を捨てない)。hash backfill不能時はキャッシュせず表示のみ。VoiceOverはタイトル一式が1要素、閉じるボタンは独立フォーカス、目盛は行ごとに結合。

## アルゴリズム検証(Python参照ミラー)

Swift実装と同一の係数式・ゲーティング・FIR設計を [`mirror.py`](mirror.py) に1:1で写像し、既知信号の期待値を導出した。`KitsunebiAnalyzerTests` はこの値を固定する。

| 信号 | 期待値(ミラー実測) | 意味 |
|---|---|---|
| 997 Hz正弦波 ステレオ -20 dBFS 10s @48k | Integrated **-20.000 LUFS** / Max ST -20.000 / Sample Peak -20.00 dBFS / True Peak -20.00 dBTP / 相関 +1.0 | EBU Tech 3341の基準系と一致(K-weightingの+0.691 dB@997Hzと-0.691オフセットが相殺) |
| 同上 @44.1k | Integrated **-19.997 LUFS**(許容±0.1内) | 係数式ブランチの規格適合。残差0.003は双一次変換の周波数歪みでpyloudnormと同一 |
| 無音 3s | 全指標 計測不能(nil) | 無限大をJSONへ書かない契約 |
| 1 kHzフルスケール方形波 1s @48k | Sample Peak 0.00 dBFS / True Peak **+1.848 dBTP** / クリップ疑い1ラン(0:00) / Integrated +0.825 LUFS | 帯域制限補間のオーバーシュートとクリップ検出 |
| 997 Hz逆相ステレオ 5s @48k | 相関 **-1.0** / Integrated -6.021 LUFS | モノ互換の検出。位相はラウドネスへ影響しない |
| fs/4正弦波 位相π/4 1s @48k | Sample Peak -9.031 dBFS / True Peak **-6.159 dBTP** | インターサンプルピーク(標本値に隠れた真のピーク)。理想-6.021への僅かな未達は48タップFIRの設計どおり |

このほか、チャンク分割不変性(3001サンプル刻み vs 一括)、チャンク境界を跨ぐクリップランの追跡、キャッシュ契約(版・hash・自身のhash欠落)、モノラルと計測不能の表示区別をテストで固定している。

## レビュー

- 独立レビューエージェント4体(DSP正当性 / Swift 6コンパイル安全性 / テスト妥当性 / 統合・仕様適合)+GitHub上のCopilot・Codexレビューを実施。
- 採用した主な指摘: 非有限値の遮断(DSP/統合の両レビューが独立に検出)、44.1kHz係数式の規格不適合(テストレビューが数値導出込みで検出)、hash backfillのメインスレッド実行(Copilot/Codex)、チャンネル重みの決め打ち(Codex)、閉じるボタンのVoiceOver独立性、重複トラックのキャッシュ共有、保存失敗時のロールバック。
- Swift 6 strict concurrencyの実コンパイルエラー1件(`[weak self]`のmutable束縛を@Sendableクロージャが参照)はMac上のXcodeビルドで検出し、強参照キャプチャへ変更(帳を閉じても解析を完走させる設計と整合)。

## Mac側検証(Desktop Commander経由・2026-07-12)

- **full suite 96 / 96 成功**(Xcode 27.0 / iPhone 17 Pro Simulator、commit `02bf89a`)。`KitsunebiAnalyzerTests` 12 / 12 を含み、ミラー導出の期待値(EBU -20 LUFS、True Peakオーバーシュート、44.1kHz適合、チャンク不変性、クリップラン境界)が実際のAccelerate / AVFoundation上で成立した。
- Xcode Cloud「Build - iOS」は最新head(`85545a3`)で**成功**。初回コミット(`8ccfeda`)のCI失敗はMac上のビルドで「`[weak self]`のmutable束縛を@Sendableクロージャが参照」というSwift 6エラーと特定し、強参照キャプチャで解消した。

## 未完了

- `85545a3` で追加した2テスト(ファイル経由E2E / 帳のQA artifact)のMac上での実行と、xcresultからの `tobari-screen.png` 抽出。
- Simulatorでの帳の対話的確認(進捗→目盛→提案、VoiceOver、絵巻が退く共存規則)。
- 実音源での動作確認とユーザー本人の確認。

上記が済むまでPhase A完了とは扱いません。
