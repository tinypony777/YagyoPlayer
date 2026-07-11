# 夜行絵巻 振付翻訳帳

この翻訳帳が扱う入力は、再生中に **15 Hz** で取得する `AVAudioPlayer.averagePower` を `0...1` に正規化し、立ち上がりを速く・下がりを緩やかに平滑化した**音量の近似値**だけです。拍、音楽的なアタック、デジタル無音、BPM、サビやセクション、曲の意味は検出していません。ここにある反応は、取得できた音量とその時間変化を、説明可能な視覚状態へ翻訳したものです。

## 入力から振付への対応

| 入力 | 判定 | 通常振付 | Reduce Motion | 実装状態 |
|---|---|---|---|---|
| stopped | 再生していない、または pause / stop 等で明示的に reset された状態 | 行列の移動、歩行フレーム、揺れを止め、中立姿勢に戻す | 同じ中立静止画を保つ | Step 4 feature branchに実装。unit tests / code review検証済み |
| unavailable | 再生中だが meter 値がない、または値が有限でない状態 | 再生は継続するが音量に根拠のない反応は出さない。提灯 halo を破線にし、CircularWaveform を中立色の破線・位相固定にして low / stopped と区別する | 移動を止めても、同じ破線の提灯 halo と、中立色・破線・位相固定の CircularWaveform を残す。VoiceOver 値は「音量表示を利用できません」 | 実装・unit tests / code review済み。破線の提灯haloはSimulator確認済み |
| level | 利用可能な有限値を `0...1` に clamp し、低・中・高の音量帯へ分ける | 通常時は固定 4 fps で歩行フレームを切り替え、level は bob の振幅と提灯 halo の大きさ・濃さへ反映する。歩行周期は BPM ではない | 横移動・bob・連続 scale・フレーム循環を止め、提灯 halo と円形波形の離散形状で音量帯を残す | unit testsとnormal Simulator表示を検証済み |
| quietProxy | `level <= 0.08` が `0.70 s` 継続すると進入し、`level >= 0.14` で離脱する | 行進を遅くして bob を抑え、唐傘だけを専用 `hush` 姿勢、他の妖怪を `idle` fallback にする | 唐傘の `hush` と他妖怪の `idle` を静止表示し、低音量帯の提灯 halo・円形波形の離散形状・VoiceOver 値を残す | unit testsとquiet Simulator表示を検証済み |
| strongRiseProxy | `level >= 0.55` かつ、更新前の低速基準包絡との差が `>= 0.18` のとき、一度だけ強反応を始める | `anticipate` → `open` → `recover`。唐傘の開き、木魚・天狗・鬼・狐火の既存の強姿勢を使い、根拠のない妖怪へ新しい反応は足さない | 位置と scale を変えず、strong が active の間は開いた静止姿勢と静的な輪郭線を保つ | unit testsとstrong open Simulator表示を検証済み |
| resident | 現在トラックの UUID から互換性を保つ固定 roster で一体を割り当てる。聴取回数による選出ではない | resident を重複なく先頭へ移し、先導灯で示す | 同じ先頭位置、先導灯、VoiceOver の「先導は…」で示す | unit testsとSimulatorの先導markerを検証済み。履歴による演出は未接続 |
| Ushimitsu | 丑三つ時モードが有効な状態。音量解析の結果ではない | 一つ目小僧を最後尾へ追加する。一つ目小僧も共通の通常・`quietProxy` の速度と bob に参加するが、strong 固有反応は持たない | 同じ最後尾の静止追加と VoiceOver の「丑三つ時」で示し、strong 固有の輪郭線は出さない | snapshot振付への接続とSimulatorの追加表示を検証済み |

ローカル検証ではfocused 32 testsと全57 testsがskip 0で合格し、iPhone 17 Proでnormal / quiet / strong / strong + Reduce Motion / unavailable、最小幅iPhone 17eでnormalを確認しました。DEBUG preview harnessにはCircularWaveform自体がないため、unavailable時の中立色・破線・位相固定のCircularWaveformはSimulator画像ではなく、`CircularWaveformPresentation`のunit testsとcode reviewを証拠とします。Reduce Motionは画像上の座標・scale固定を確認しましたが、時間経過後も完全に静止することは単一画像だけでは未実測です。

## 判定定数

実装の正本は `ParadeSignalConfiguration.production` です。初期値は次のとおりです。

- `quietProxy` 進入: `level <= 0.08` が `0.70 s` 継続。離脱: `level >= 0.14`。
- `strongRiseProxy` 候補: `level >= 0.55` かつ、低速基準包絡との差が `>= 0.18`。
- 低速基準包絡: 時定数 `0.80 s` の時間補正 EMA。候補判定には現在サンプルを取り込む前の基準値を使う。
- 再発火 cooldown: `0.45 s`。
- 再武装: cooldown 終了後、`level <= 0.32` または基準包絡との差が `<= 0.06` を一度満たしたとき。
- 強反応の各段階: anticipate `0.07 s`、open `0.27 s`、recover `0.20 s`。
- reset 後の warm-up: `0.30 s`。
- サンプル時刻が逆行するか、間隔が `> 0.50 s` のときは時間依存状態を reseed し、そのサンプルでは強反応を発火しない。

低速基準包絡は `alpha = 1 - exp(-dt / 0.80)`、`baseline += alpha * (level - baseline)` で更新します。一定の大音量だけでは強反応を繰り返さず、いったん再武装条件を満たしてから再上昇したときだけ次の反応を許します。曲頭が大音量の場合も、seed と warm-up により強反応を出しません。

## 状態の境界

`pause`、`stop`、`seek`、track load 開始（次曲を含む）、load failure、play failure では視覚 reducer を reset します。再開後は最初の有限サンプルで基準値を seed し、warm-up が終わるまで `strongRiseProxy` を抑止します。meter timer の張り直しだけは意味上の reset ではありません。

`stopped`、`unavailable`、`quietProxy` は別の状態です。停止を「曲中の静けさ」と解釈せず、meter が読めない状態も低レベルとみなしません。視覚信号が利用できなくても、再生経路そのものは継続します。

## アートと公開のゲート

現在の SNES 相当の基準体は唐傘だけです。唐傘は 40×48 px、2倍整数表示（80×96 pt）、透明を除き最大12色、`idle 1 + walk 4 + hush 1 + strong 2` の8フレームを持ちます。他の行列妖怪は従来アートのままなので、この混在状態は feature branch と Draft PR に留め、`main` へ統合しません。

唐傘を Simulator で確認し、ユーザーが見た目を承認した後に、残りの妖怪ごとの状態と必要フレームを別の matrix として提示します。その matrix が別途承認されるまで、全妖怪への展開や SNES 刷新完了とは扱いません。
