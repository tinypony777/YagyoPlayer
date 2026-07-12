# Step 5 狐火の帳 Phase A・証跡ledger

[設計仕様](../../superpowers/specs/2026-07-12-kitsunebi-no-tobari-design.md)のPhase A(一画面検聴)の証跡です。

## 実装

- `KitsunebiAnalyzer` / `KitsunebiAnalyzerEngine`: [Mastering-App](https://github.com/tinypony777/Mastering-App)(commit `73e21fa`)の `KWeightingFilter` / `LUFSMeter` / `TruePeakMeter` / `AudioAnalyzer` のstreaming手法を移植し、仕様の補修2点を適用した1パスchunked解析。
  - 補修1: Short-term(3秒)も100msホップ30本のリングでstreaming化。サンプル数に比例するバッファは持たない(Integratedのゲーティングにのみ100msあたり1つのブロックラウドネス値を保持する)。
  - 補修2: クリップ疑いを「|x| ≥ 0.999 が3サンプル以上連続するラン」の回数+開始位置(最大8件)へ。ランはチャンク境界を越えて追跡する。
- `TobariMetrics`: `contentHash` + `analyzerVersion` キーの検聴キャッシュ(library.json後方互換、無限大はnilで表現)。
- `TobariView` / `TobariAnalysisController`: トラック長押し→「狐火の帳で検聴」で開く一画面。解析は低優先度の非同期タスクで、進捗・失敗を明示し再生へ影響しない。hash未保持の旧トラックは解析前にbackfillし、backfill不能時はキャッシュせず表示のみ。

## アルゴリズム検証(Python参照ミラー)

Swift実装と同一の係数式・ゲーティング・FIR設計を [`mirror.py`](mirror.py) に1:1で写像し、既知信号の期待値を導出した。`KitsunebiAnalyzerTests` はこの値を固定する。

| 信号 (48 kHz) | 期待値(ミラー実測) | 意味 |
|---|---|---|
| 997 Hz正弦波 ステレオ -20 dBFS 10s | Integrated **-20.000 LUFS** / Max ST -20.000 / Sample Peak -20.00 dBFS / True Peak -20.00 dBTP / 相関 +1.0 | EBU Tech 3341の基準系と一致(K-weightingの+0.691 dB@997Hzと-0.691オフセットが相殺) |
| 無音 3s | 全指標 計測不能(nil) | 無限大をJSONへ書かない契約 |
| 1 kHzフルスケール方形波 1s | Sample Peak 0.00 dBFS / True Peak **+1.848 dBTP** / クリップ疑い1ラン(0:00) / Integrated +0.825 LUFS | 帯域制限補間のオーバーシュートとクリップ検出 |
| 997 Hz逆相ステレオ 5s | 相関 **-1.0** / Integrated -6.021 LUFS | モノ互換の検出。位相はラウドネスへ影響しない |
| fs/4正弦波 位相π/4 1s | Sample Peak -9.031 dBFS / True Peak **-6.159 dBTP** | インターサンプルピーク(標本値に隠れた真のピーク)。理想-6.021への僅かな未達は48タップFIRの設計どおり |

このほか、チャンク分割不変性(3001サンプル刻み vs 一括)とチャンク境界を跨ぐクリップランの追跡をテストで固定している。

## 未完了(Mac側)

- Xcode build / `KitsunebiAnalyzerTests` を含むfull suiteの実行。
- Simulatorでの帳の表示確認(進捗→目盛→提案、VoiceOver、絵巻が退く共存規則)。
- 実音源での動作確認とユーザー本人の確認。

上記が済むまでPhase A完了とは扱いません。
